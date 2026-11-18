import AppKit
import QuartzCore
import SinMinionsCore

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
    static let headroom: CGFloat = 28
    /// Поля вокруг персонажа под свечение, в единицах рисунка.
    static let glowMargin: CGFloat = 12

    static func windowSize(scale: CGFloat) -> CGSize {
        CGSize(width: (MothShape.size.width + glowMargin * 2) * scale,
               height: (MothShape.size.height + headroom + glowMargin * 2) * scale)
    }

    /// Палитра терминала из claudesiniakov/summary.
    enum Palette {
        static func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
            NSColor(srgbRed: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255,
                    blue: CGFloat(hex & 0xff) / 255, alpha: alpha)
        }
        static let green = rgb(0x5cf542)
        static let greenDim = rgb(0x3a9e28)
        static let greenDark = rgb(0x1a4a10)
        static let body = rgb(0x1a3a12)
        static let bodyStroke = rgb(0x3a8a28)
        static let pupil = rgb(0xcfffca)
        static let panel = rgb(0x0e140c)
    }

    let scale: CGFloat
    let style: GhostStyle
    private let art: GhostArt
    private let moth: CALayer
    private let body: CAShapeLayer
    private let eyes: CALayer
    private let zzz = CATextLayer()
    private let bodyPath: CGPath
    private var sleeping = false
    private var eyesHome = CGPoint.zero

    var onClick: () -> Void = {}
    var onDoubleClick: () -> Void = {}
    var onShoo: () -> Void = {}
    var onDragBegan: () -> Void = {}
    var onDragMoved: (CGPoint) -> Void = { _ in }
    var onDragEnded: () -> Void = {}

    private(set) var isDragging = false
    private var downMouse = CGPoint.zero
    private var downOrigin = CGPoint.zero
    private var pendingClick: Task<Void, Never>?

    init(scale: CGFloat, style: GhostStyle = .classic) {
        self.scale = scale
        self.style = style
        art = GhostArt(style: style, scale: scale)
        moth = art.root
        body = art.body
        eyes = art.eyes
        bodyPath = art.bodyPath
        super.init(frame: CGRect(origin: .zero, size: Self.windowSize(scale: scale)))
        wantsLayer = true
        layer?.backgroundColor = .clear

        let size = CGSize(width: MothShape.size.width * scale, height: MothShape.size.height * scale)
        let inset = Self.glowMargin * scale
        moth.frame = CGRect(origin: CGPoint(x: inset, y: inset), size: size)

        eyesHome = art.eyesHome
        layer?.addSublayer(moth)

        // «z z z» над спящим.
        zzz.string = "z z z"
        zzz.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        zzz.fontSize = max(9, 7.5 * scale)
        zzz.foregroundColor = Palette.greenDim.cgColor
        zzz.contentsScale = NSScreen.main?.backingScaleFactor ?? 2
        zzz.alignmentMode = .left
        zzz.frame = CGRect(x: moth.frame.maxX - 10 * scale, y: moth.frame.maxY - 4 * scale,
                           width: 20 * scale, height: 12 * scale)
        zzz.opacity = 0
        layer?.addSublayer(zzz)
        startFloating()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) не используется") }

    /// Прямоугольник персонажа в координатах окна (без запаса под анимацию).
    var mothFrame: CGRect { moth.frame }

    // MARK: - Анимации

    private func keyframes(_ keyPath: String, _ values: [CGFloat], _ times: [NSNumber]) -> CAKeyframeAnimation {
        let animation = CAKeyframeAnimation(keyPath: keyPath)
        animation.values = values
        animation.keyTimes = times
        animation.timingFunctions = Array(
            repeating: CAMediaTimingFunction(name: .easeInEaseOut), count: max(values.count - 1, 1)
        )
        return animation
    }

    /// Парение призрака: медленный дрейф с лёгким наклоном и мерцанием, цикл 5 с; во сне — тише и тусклее.
    /// Вместе с ним пульсирует свечение (цикл 3 с).
    func startFloating() {
        let degree = CGFloat.pi / 180
        let group = CAAnimationGroup()
        let glowRadius = CABasicAnimation(keyPath: "shadowRadius")
        let glowOpacity = CABasicAnimation(keyPath: "shadowOpacity")
        if sleeping {
            let times: [NSNumber] = [0, 0.5, 1]
            group.animations = [
                keyframes("transform.translation.y", [0, 4 * scale, 0], times),
                keyframes("transform.rotation.z", [1.5 * degree, -1.5 * degree, 1.5 * degree], times),
                keyframes("opacity", [0.55, 0.7, 0.55], times),
            ]
            group.duration = 6
            glowRadius.fromValue = 1.5 * scale * art.glowScale
            glowRadius.toValue = 2.5 * scale * art.glowScale
            glowOpacity.fromValue = 0.12
            glowOpacity.toValue = 0.2
        } else {
            let times: [NSNumber] = [0, 0.2, 0.5, 0.75, 1]
            group.animations = [
                keyframes("transform.translation.y", [0, 9 * scale, 6 * scale, 11 * scale, 0], times),
                keyframes("transform.translation.x", [0, 3 * scale, -2 * scale, 4 * scale, 0], times),
                // В CSS положительный поворот — по часовой стрелке, в слое с осью y вверх — против.
                keyframes("transform.rotation.z", [0, -1.5 * degree, 1 * degree, -1 * degree, 0], times),
                keyframes("opacity", [0.82, 1, 0.9, 1, 0.82], times),
            ]
            group.duration = 5
            glowRadius.fromValue = 3 * scale * art.glowScale
            glowRadius.toValue = 8 * scale * art.glowScale
            glowOpacity.fromValue = 0.35
            glowOpacity.toValue = 0.8
        }
        group.repeatCount = .infinity
        moth.add(group, forKey: "float")

        for glow in [glowRadius, glowOpacity] {
            glow.duration = 1.5
            glow.autoreverses = true
            glow.repeatCount = .infinity
            glow.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        }
        body.add(glowRadius, forKey: "glowRadius")
        body.add(glowOpacity, forKey: "glowOpacity")

        zzz.removeAnimation(forKey: "drift")
        if sleeping {
            let drift = CAAnimationGroup()
            drift.animations = [
                keyframes("transform.translation.x", [0, 4 * scale, 8 * scale], [0, 0.5, 1]),
                keyframes("transform.translation.y", [0, 8 * scale, 16 * scale], [0, 0.5, 1]),
                keyframes("opacity", [0.3, 0.8, 0], [0, 0.5, 1]),
            ]
            drift.duration = 3
            drift.repeatCount = .infinity
            zzz.add(drift, forKey: "drift")
        }
    }

    /// Щелчок: подпрыгивание и вспышка свечения.
    func hop() {
        let hop = CAKeyframeAnimation(keyPath: "transform.translation.y")
        hop.values = [0, 14 * scale, 0]
        hop.keyTimes = [0, 0.45, 1]
        hop.duration = 0.36
        hop.isAdditive = true
        hop.timingFunctions = [CAMediaTimingFunction(name: .easeOut), CAMediaTimingFunction(name: .easeIn)]
        moth.add(hop, forKey: "hop")

        let burst = CAKeyframeAnimation(keyPath: "shadowRadius")
        burst.values = [8, 11, 8].map { $0 * scale * art.glowScale }
        burst.duration = 0.5
        let flash = CAKeyframeAnimation(keyPath: "shadowOpacity")
        flash.values = [0.8, 1, 0.8]
        flash.duration = 0.5
        body.add(burst, forKey: "burst")
        body.add(flash, forKey: "flash")
    }

    /// Танец: оборот вокруг оси с подскоком и вспышкой свечения.
    func spin() {
        let degree = CGFloat.pi / 180
        let rotation = CABasicAnimation(keyPath: "transform.rotation.z")
        rotation.fromValue = 0
        rotation.toValue = 360 * degree
        let jump = CAKeyframeAnimation(keyPath: "transform.translation.y")
        jump.values = [0, 18 * scale, 0]
        jump.keyTimes = [0, 0.5, 1]
        for animation in [rotation, jump] {
            animation.duration = 0.7
            animation.isAdditive = true
            animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        }
        moth.add(rotation, forKey: "spinRotation")
        moth.add(jump, forKey: "spinJump")
        let flash = CAKeyframeAnimation(keyPath: "shadowOpacity")
        flash.values = [0.8, 1, 0.8]
        flash.duration = 0.7
        body.add(flash, forKey: "spinFlash")
    }

    /// Испуг: быстрая дрожь с наклоном и вспышкой свечения.
    func shake() {
        let degree = CGFloat.pi / 180
        let x = CAKeyframeAnimation(keyPath: "transform.translation.x")
        x.values = [0, -6, 6, -4, 4, 0].map { $0 * scale }
        let rotation = CAKeyframeAnimation(keyPath: "transform.rotation.z")
        rotation.values = [0, -4, 4, -2, 2, 0].map { $0 * degree }
        for animation in [x, rotation] {
            animation.duration = 0.45
            animation.isAdditive = true
        }
        moth.add(x, forKey: "shakeX")
        moth.add(rotation, forKey: "shakeRotation")
        let flash = CAKeyframeAnimation(keyPath: "shadowOpacity")
        flash.values = [0.8, 1, 0.8]
        flash.duration = 0.45
        body.add(flash, forKey: "shakeFlash")
    }

    /// Втягивание в портал: призрак сжимается до точки, поворачиваясь, и остаётся невидимым.
    func vanish(duration: Double) {
        var gone = CATransform3DMakeScale(0.05, 0.05, 1)
        gone = CATransform3DRotate(gone, .pi, 0, 0, 1)
        let animation = CABasicAnimation(keyPath: "transform")
        animation.fromValue = NSValue(caTransform3D: CATransform3DIdentity)
        animation.toValue = NSValue(caTransform3D: gone)
        animation.duration = duration
        animation.timingFunction = CAMediaTimingFunction(name: .easeIn)
        animation.fillMode = .forwards
        animation.isRemovedOnCompletion = false
        moth.add(animation, forKey: "portal")
    }

    /// Выход из портала: обратное движение, после которого парение продолжается.
    func appear(duration: Double) {
        moth.removeAnimation(forKey: "portal")
        var gone = CATransform3DMakeScale(0.05, 0.05, 1)
        gone = CATransform3DRotate(gone, .pi, 0, 0, 1)
        let animation = CABasicAnimation(keyPath: "transform")
        animation.fromValue = NSValue(caTransform3D: gone)
        animation.toValue = NSValue(caTransform3D: CATransform3DIdentity)
        animation.duration = duration
        animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
        moth.add(animation, forKey: "portal")
    }

    func clearPortalEffect() {
        moth.removeAnimation(forKey: "portal")
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

    override func rightMouseDown(with event: NSEvent) {
        pendingClick?.cancel()
        pendingClick = nil
        onShoo()
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
