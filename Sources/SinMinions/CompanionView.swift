import AppKit
import QuartzCore

/// Контуры призрака Moth из claudesiniakov/summary (SVG 48×56, ось y вниз).
enum MothShape {
    static let size = CGSize(width: 48, height: 56)
    static let eyeCenters = [CGPoint(x: 17, y: 24), CGPoint(x: 31, y: 24)]
    static let eyeRadii = CGSize(width: 3, height: 3.5)
    static let shineCenters = [CGPoint(x: 18.2, y: 22.5), CGPoint(x: 32.2, y: 22.5)]
    static let eyeLineY: CGFloat = 24

    static func body(_ transform: CGAffineTransform) -> CGPath {
        let path = CGMutablePath()
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y) }
        path.move(to: p(4, 24), transform: transform)
        path.addCurve(to: p(24, 4), control1: p(4, 12.954), control2: p(13.163, 4), transform: transform)
        path.addCurve(to: p(44, 24), control1: p(34.837, 4), control2: p(44, 12.954), transform: transform)
        path.addLine(to: p(44, 44), transform: transform)
        path.addCurve(to: p(36, 44), control1: p(44, 44), control2: p(40, 40), transform: transform)
        path.addCurve(to: p(24, 44), control1: p(32, 48), control2: p(28, 44), transform: transform)
        path.addCurve(to: p(12, 44), control1: p(20, 44), control2: p(16, 48), transform: transform)
        path.addCurve(to: p(4, 44), control1: p(8, 40), control2: p(4, 44), transform: transform)
        path.addLine(to: p(4, 24), transform: transform)
        path.closeSubpath()
        return path
    }

    static func ellipse(center: CGPoint, radii: CGSize, _ transform: CGAffineTransform) -> CGPath {
        let rect = CGRect(x: center.x - radii.width, y: center.y - radii.height,
                          width: radii.width * 2, height: radii.height * 2)
        let path = CGMutablePath()
        path.addEllipse(in: rect, transform: transform)
        return path
    }
}

/// Персонаж: слои тела и глаз, парение, моргание, взгляд, сон; щелчки и перетаскивание.
@MainActor
final class CompanionView: NSView {
    /// Запас над персонажем под парение и подпрыгивание, в единицах рисунка.
    static let headroom: CGFloat = 22
    static let margin: CGFloat = 2

    static func windowSize(scale: CGFloat) -> CGSize {
        CGSize(width: MothShape.size.width * scale + margin * 2,
               height: (MothShape.size.height + headroom) * scale + margin * 2)
    }

    let scale: CGFloat
    private let moth = CALayer()
    private let eyes = CALayer()
    private let bodyPath: CGPath
    private var sleeping = false
    private var eyesHome = CGPoint.zero

    var onClick: () -> Void = {}
    var onDoubleClick: () -> Void = {}
    var onDragBegan: () -> Void = {}
    var onDragMoved: (CGPoint) -> Void = { _ in }
    var onDragEnded: () -> Void = {}

    private(set) var isDragging = false
    private var downMouse = CGPoint.zero
    private var downOrigin = CGPoint.zero
    private var pendingClick: Task<Void, Never>?

    init(scale: CGFloat) {
        self.scale = scale
        // SVG → слой: масштаб и переворот оси y.
        let transform = CGAffineTransform(a: scale, b: 0, c: 0, d: -scale, tx: 0, ty: MothShape.size.height * scale)
        bodyPath = MothShape.body(transform)
        super.init(frame: CGRect(origin: .zero, size: Self.windowSize(scale: scale)))
        wantsLayer = true
        layer?.backgroundColor = .clear

        let size = CGSize(width: MothShape.size.width * scale, height: MothShape.size.height * scale)
        moth.frame = CGRect(origin: CGPoint(x: Self.margin, y: Self.margin), size: size)

        let body = CAShapeLayer()
        body.path = bodyPath
        body.fillColor = NSColor(srgbRed: 0xd8 / 255, green: 0xd0 / 255, blue: 0xf0 / 255, alpha: 1).cgColor
        body.strokeColor = NSColor(srgbRed: 0xb8 / 255, green: 0xae / 255, blue: 0xe0 / 255, alpha: 1).cgColor
        body.lineWidth = 1.5 * scale
        moth.addSublayer(body)

        // Глаза — отдельный слой с опорной точкой на линии глаз: моргание сжимает их к этой линии.
        eyesHome = CGPoint(x: size.width / 2, y: (MothShape.size.height - MothShape.eyeLineY) * scale)
        eyes.bounds = CGRect(origin: .zero, size: size)
        eyes.anchorPoint = CGPoint(x: 0.5, y: eyesHome.y / size.height)
        eyes.position = eyesHome
        for center in MothShape.eyeCenters {
            let eye = CAShapeLayer()
            eye.path = MothShape.ellipse(center: center, radii: MothShape.eyeRadii, transform)
            eye.fillColor = NSColor(white: 0.2, alpha: 1).cgColor
            eyes.addSublayer(eye)
        }
        for center in MothShape.shineCenters {
            let shine = CAShapeLayer()
            shine.path = MothShape.ellipse(center: center, radii: CGSize(width: 1, height: 1), transform)
            shine.fillColor = NSColor.white.cgColor
            eyes.addSublayer(shine)
        }
        moth.addSublayer(eyes)
        layer?.addSublayer(moth)
        startFloating()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) не используется") }

    /// Прямоугольник персонажа в координатах окна (без запаса под анимацию).
    var mothFrame: CGRect { moth.frame }

    // MARK: - Анимации

    /// Парение: 6 единиц вверх-вниз, цикл 3 с (во сне — вдвое медленнее).
    func startFloating() {
        let float = CABasicAnimation(keyPath: "transform.translation.y")
        float.fromValue = 0
        float.toValue = 6 * scale
        float.duration = sleeping ? 3 : 1.5
        float.autoreverses = true
        float.repeatCount = .infinity
        float.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        moth.add(float, forKey: "float")
    }

    func hop() {
        let hop = CAKeyframeAnimation(keyPath: "transform.translation.y")
        hop.values = [0, 14 * scale, 0]
        hop.keyTimes = [0, 0.45, 1]
        hop.duration = 0.36
        hop.isAdditive = true
        hop.timingFunctions = [CAMediaTimingFunction(name: .easeOut), CAMediaTimingFunction(name: .easeIn)]
        moth.add(hop, forKey: "hop")
    }

    func blink() {
        guard !sleeping else { return }
        let blink = CAKeyframeAnimation(keyPath: "transform.scale.y")
        blink.values = [1, 0.1, 1]
        blink.duration = 0.18
        eyes.add(blink, forKey: "blink")
    }

    func setSleeping(_ value: Bool) {
        guard value != sleeping else { return }
        sleeping = value
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.3)
        eyes.transform = value ? CATransform3DMakeScale(1, 0.12, 1) : CATransform3DIdentity
        eyes.position = eyesHome
        CATransaction.commit()
        startFloating()
    }

    /// Глаза смещаются в сторону курсора не больше чем на 1,5 единицы рисунка.
    func look(at screenPoint: CGPoint) {
        guard !sleeping, let window else { return }
        let center = CGPoint(x: window.frame.minX + moth.frame.midX, y: window.frame.minY + moth.frame.minY + eyesHome.y)
        let dx = screenPoint.x - center.x, dy = screenPoint.y - center.y
        let distance = hypot(dx, dy)
        let reach = min(distance / 120, 1) * 1.5 * scale
        let offset = distance > 0.5 ? CGPoint(x: dx / distance * reach, y: dy / distance * reach) : .zero
        let target = CGPoint(x: eyesHome.x + offset.x, y: eyesHome.y + offset.y)
        guard abs(target.x - eyes.position.x) > 0.05 || abs(target.y - eyes.position.y) > 0.05 else { return }
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.12)
        eyes.position = target
        CATransaction.commit()
    }

    // MARK: - Попадание

    /// Точка экрана лежит на силуэте персонажа (с учётом текущего смещения парения).
    func silhouetteContains(screenPoint: CGPoint) -> Bool {
        guard let window else { return false }
        let lift = (moth.presentation()?.value(forKeyPath: "transform.translation.y") as? CGFloat) ?? 0
        let local = CGPoint(
            x: screenPoint.x - window.frame.minX - moth.frame.minX,
            y: screenPoint.y - window.frame.minY - moth.frame.minY - lift
        )
        return bodyPath.contains(local)
    }

    // MARK: - Мышь

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        downMouse = NSEvent.mouseLocation
        downOrigin = window?.frame.origin ?? .zero
        isDragging = false
    }

    override func mouseDragged(with event: NSEvent) {
        let mouse = NSEvent.mouseLocation
        let dx = mouse.x - downMouse.x, dy = mouse.y - downMouse.y
        if !isDragging {
            guard hypot(dx, dy) > 3 else { return }
            isDragging = true
            pendingClick?.cancel()
            pendingClick = nil
            onDragBegan()
        }
        onDragMoved(CGPoint(x: downOrigin.x + dx, y: downOrigin.y + dy))
    }

    override func mouseUp(with event: NSEvent) {
        if isDragging {
            isDragging = false
            onDragEnded()
            return
        }
        pendingClick?.cancel()
        pendingClick = nil
        if event.clickCount >= 2 {
            onDoubleClick()
            return
        }
        // Одиночный щелчок срабатывает только после интервала двойного, чтобы не мешать ему.
        let delay = NSEvent.doubleClickInterval
        pendingClick = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self else { return }
            self.pendingClick = nil
            self.onClick()
        }
    }
}
