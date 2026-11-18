import AppKit
import QuartzCore
import SinMinionsCore

/// Слои призрака одного из пяти стилей. Силуэт и глаза общие для всех (SVG 48×56 из claudesiniakov/summary),
/// стили отличаются заливкой, деталями и собственной анимацией. Один и тот же рисунок использует окно призрака
/// и монитор в терминале.
@MainActor
final class GhostArt {
    let style: GhostStyle
    let scale: CGFloat
    /// Корень рисунка размером с призрака; положение задаёт тот, кто его вставляет.
    let root = CALayer()
    /// Тело: от него считается свечение, оно же пульсирует при парении.
    let body = CAShapeLayer()
    /// Глаза: моргают сжатием к линии глаз и смещаются за курсором.
    let eyes = CALayer()
    let bodyPath: CGPath
    let eyesHome: CGPoint
    /// Слои, которые мерцают (стиль «Терминал»).
    private var flickerLayers: [CALayer] = []

    var glowScale: CGFloat { CGFloat(style.glowScale) }

    private let size: CGSize
    private let transform: CGAffineTransform

    private enum Color {
        static let green = CompanionView.Palette.green
        static let dim = CompanionView.Palette.greenDim
        static let body = CompanionView.Palette.body
        static let stroke = CompanionView.Palette.bodyStroke
        static let pupil = CompanionView.Palette.pupil
        static let amber = CompanionView.Palette.rgb(0xffb033)
        static let light = CompanionView.Palette.rgb(0xb6ffa8)
        static let pale = CompanionView.Palette.rgb(0xeffff0)
        static let ink = CompanionView.Palette.rgb(0x0b1a08)
        static let deep = CompanionView.Palette.rgb(0x0f260b)
        static let mid = CompanionView.Palette.rgb(0x2f6a20)
        static let hot = CompanionView.Palette.rgb(0x3f8d2a)
        static let suit = CompanionView.Palette.rgb(0x12310c)
        static let tint = CompanionView.Palette.rgb(0x0d2a08)
    }

    init(style: GhostStyle, scale: CGFloat) {
        self.style = style
        self.scale = scale
        size = CGSize(width: MothShape.size.width * scale, height: MothShape.size.height * scale)
        // SVG → слой: масштаб и переворот оси y.
        transform = CGAffineTransform(a: scale, b: 0, c: 0, d: -scale, tx: 0, ty: MothShape.size.height * scale)
        bodyPath = MothShape.body(transform)
        eyesHome = CGPoint(x: size.width / 2, y: (MothShape.size.height - MothShape.eyeLineY) * scale)
        root.bounds = CGRect(origin: .zero, size: size)

        body.path = bodyPath
        body.shadowPath = bodyPath
        body.shadowColor = Color.green.cgColor
        body.shadowOffset = .zero
        body.shadowRadius = 3 * scale * glowScale
        body.shadowOpacity = 0.35

        eyes.bounds = CGRect(origin: .zero, size: size)
        eyes.anchorPoint = CGPoint(x: 0.5, y: eyesHome.y / size.height)
        eyes.position = eyesHome

        switch style {
        case .classic: buildClassic()
        case .detailed: buildDetailed()
        case .warden: buildWarden()
        case .terminal: buildTerminal()
        case .radiation: buildRadiation()
        }
    }

    // MARK: - Помощники

    /// Путь, нарисованный в координатах SVG (ось y вниз), переносится в координаты слоя.
    private func svg(_ draw: (CGMutablePath) -> Void) -> CGPath {
        let path = CGMutablePath()
        draw(path)
        var m = transform
        return path.copy(using: &m) ?? path
    }

    private func ellipse(_ cx: CGFloat, _ cy: CGFloat, _ rx: CGFloat, _ ry: CGFloat, rotation degrees: CGFloat = 0) -> CGPath {
        svg { path in
            let rect = CGRect(x: cx - rx, y: cy - ry, width: rx * 2, height: ry * 2)
            let turn = CGAffineTransform(translationX: cx, y: cy)
                .rotated(by: degrees * .pi / 180)
                .translatedBy(x: -cx, y: -cy)
            path.addEllipse(in: rect, transform: turn)
        }
    }

    private func shape(
        _ path: CGPath, fill: NSColor? = nil, stroke: NSColor? = nil, width: CGFloat = 1,
        dash: [CGFloat]? = nil, opacity: Float = 1
    ) -> CAShapeLayer {
        let layer = CAShapeLayer()
        layer.frame = root.bounds
        layer.path = path
        layer.fillColor = fill?.cgColor
        layer.strokeColor = stroke?.cgColor
        layer.lineWidth = width * scale
        layer.lineCap = .round
        layer.lineJoin = .round
        layer.opacity = opacity
        if let dash { layer.lineDashPattern = dash.map { NSNumber(value: Double($0 * scale)) } }
        return layer
    }

    /// Дуга или ломаная по точкам SVG: первая точка — начало, дальше пары (управляющая, конец) квадратичных кривых
    /// или одиночные точки для отрезков.
    private func line(_ points: [(CGFloat, CGFloat)]) -> CGPath {
        svg { path in
            path.move(to: CGPoint(x: points[0].0, y: points[0].1))
            for point in points.dropFirst() { path.addLine(to: CGPoint(x: point.0, y: point.1)) }
        }
    }

    private func quad(_ x1: CGFloat, _ y1: CGFloat, _ cx: CGFloat, _ cy: CGFloat, _ x2: CGFloat, _ y2: CGFloat) -> CGPath {
        svg { path in
            path.move(to: CGPoint(x: x1, y: y1))
            path.addQuadCurve(to: CGPoint(x: x2, y: y2), control: CGPoint(x: cx, y: cy))
        }
    }

    /// Контейнер, обрезающий всё внутри силуэта тела.
    private func clipped() -> CALayer {
        let container = CALayer()
        container.frame = root.bounds
        let mask = CAShapeLayer()
        mask.frame = root.bounds
        mask.path = bodyPath
        container.mask = mask
        return container
    }

    /// Радиальный градиент; центр и радиусы — доли рисунка от левого верхнего угла.
    private func radial(_ colors: [NSColor], _ locations: [Double], center: CGPoint, radius: CGSize) -> CAGradientLayer {
        let gradient = CAGradientLayer()
        gradient.type = .radial
        gradient.frame = root.bounds
        gradient.colors = colors.map(\.cgColor)
        gradient.locations = locations.map { NSNumber(value: $0) }
        gradient.startPoint = CGPoint(x: center.x, y: 1 - center.y)
        gradient.endPoint = CGPoint(x: center.x + radius.width, y: 1 - center.y + radius.height)
        return gradient
    }

    /// Тень к подолу: сверху прозрачно, снизу темнее.
    private func hemShade(from top: CGFloat, to bottom: CGFloat, opacity: CGFloat) -> CAGradientLayer {
        let gradient = CAGradientLayer()
        gradient.frame = root.bounds
        gradient.colors = [NSColor.black.withAlphaComponent(0).cgColor, NSColor.black.withAlphaComponent(opacity).cgColor]
        gradient.startPoint = CGPoint(x: 0.5, y: 1 - top / MothShape.size.height)
        gradient.endPoint = CGPoint(x: 0.5, y: 1 - bottom / MothShape.size.height)
        return gradient
    }

    private func text(_ string: String, size fontSize: CGFloat, color: NSColor, weight: NSFont.Weight = .bold,
                      x: CGFloat, baselineY: CGFloat, width: CGFloat, centered: Bool = true) -> CATextLayer {
        let layer = CATextLayer()
        layer.string = string
        layer.font = NSFont.monospacedSystemFont(ofSize: fontSize * scale, weight: weight)
        layer.fontSize = fontSize * scale
        layer.foregroundColor = color.cgColor
        layer.contentsScale = NSScreen.main?.backingScaleFactor ?? 2
        layer.alignmentMode = centered ? .center : .left
        let height = fontSize * 1.3 * scale
        // Низ рамки чуть ниже базовой линии: на высоту подвыносной части шрифта.
        layer.frame = CGRect(x: x * scale, y: (MothShape.size.height - baselineY - fontSize * 0.28) * scale,
                             width: width * scale, height: height)
        return layer
    }

    private func finish() {
        root.addSublayer(eyes)
        for layer in flickerLayers {
            let flicker = CAKeyframeAnimation(keyPath: "opacity")
            flicker.values = [1, 1, 0.55, 0.95, 0.8, 1, 1]
            flicker.keyTimes = [0, 0.47, 0.48, 0.5, 0.83, 0.84, 1]
            flicker.duration = 3.4
            flicker.repeatCount = .infinity
            layer.add(flicker, forKey: "flicker")
        }
    }

    // MARK: - Классический

    private func buildClassic() {
        body.fillColor = Color.body.cgColor
        body.strokeColor = Color.stroke.cgColor
        body.lineWidth = 1.5 * scale
        root.addSublayer(body)
        for center in MothShape.eyeCenters {
            eyes.addSublayer(shape(ellipse(center.x, center.y, 3, 3.5), fill: Color.green))
        }
        for center in MothShape.shineCenters {
            eyes.addSublayer(shape(ellipse(center.x, center.y, 1, 1), fill: Color.pupil))
        }
        finish()
    }

    // MARK: - Детальный

    private func buildDetailed() {
        body.fillColor = Color.body.cgColor
        root.addSublayer(body)

        let clip = clipped()
        clip.addSublayer(radial([Color.mid, Color.body, Color.deep], [0, 0.6, 1],
                                center: CGPoint(x: 0.5, y: 0.42), radius: CGSize(width: 0.7, height: 0.7)))
        clip.addSublayer(hemShade(from: 34, to: 48, opacity: 0.55))
        // Блики на левом боку и сверху справа.
        clip.addSublayer(shape(ellipse(14, 14, 7, 4, rotation: -28), fill: Color.light, opacity: 0.16))
        clip.addSublayer(shape(line([(30, 9), (36, 10), (40, 15)]), stroke: Color.light, width: 0.8, opacity: 0.28))
        clip.addSublayer(shape(quad(5.2, 26, 5, 15, 11, 11), stroke: Color.light, width: 1.1, opacity: 0.55))
        root.addSublayer(clip)

        let rim = shape(bodyPath, stroke: Color.green, width: 1.4, opacity: 0.85)
        root.addSublayer(rim)
        // Складки подола.
        root.addSublayer(shape(quad(9, 41, 14, 47, 16, 44), stroke: Color.stroke, width: 0.8, opacity: 0.7))
        root.addSublayer(shape(quad(27, 44, 31, 47, 33, 43), stroke: Color.stroke, width: 0.8, opacity: 0.7))
        // Веснушки, румянец, брови и рот.
        for (x, y, r) in [(9.5, 19.0, 0.5), (11.5, 21.0, 0.4), (38.5, 19.0, 0.5), (36.5, 21.0, 0.4)] as [(CGFloat, CGFloat, CGFloat)] {
            root.addSublayer(shape(ellipse(x, y, r, r), fill: Color.green, opacity: 0.5))
        }
        for x in [11, 37] as [CGFloat] {
            root.addSublayer(shape(ellipse(x, 30, 2.6, 2.6), fill: Color.green, opacity: 0.12))
        }
        root.addSublayer(shape(quad(13.2, 19.6, 17, 17.6, 20.4, 19.2), stroke: Color.dim, width: 1))
        root.addSublayer(shape(quad(27.6, 19.2, 31, 17.6, 34.8, 19.6), stroke: Color.dim, width: 1))
        root.addSublayer(shape(quad(21.5, 33, 24, 34.6, 26.5, 33), stroke: Color.green, width: 1.1, opacity: 0.8))

        for x in [17, 31] as [CGFloat] {
            eyes.addSublayer(shape(ellipse(x, 24.2, 3.2, 3.8), fill: Color.green))
            eyes.addSublayer(shape(ellipse(x, 24.6, 1.2, 1.8), fill: Color.deep))
        }
        for (x, y, r, a) in [(18.3, 22.6, 1.05, 1.0), (32.3, 22.6, 1.05, 1.0), (15.8, 26.0, 0.55, 0.7), (29.8, 26.0, 0.55, 0.7)] as [(CGFloat, CGFloat, CGFloat, Float)] {
            eyes.addSublayer(shape(ellipse(x, y, r, r), fill: Color.pale, opacity: a))
        }
        glowEyes()
        finish()
    }

    /// Глаза светятся: тень берётся от нарисованных глаз.
    private func glowEyes() {
        eyes.shadowColor = Color.green.cgColor
        eyes.shadowOpacity = 0.85
        eyes.shadowRadius = 2 * scale
        eyes.shadowOffset = .zero
    }

    // MARK: - Смотритель Убежища

    private func buildWarden() {
        body.fillColor = Color.body.cgColor
        root.addSublayer(body)

        let clip = clipped()
        clip.addSublayer(radial([Color.mid, Color.body, Color.deep], [0, 0.6, 1],
                                center: CGPoint(x: 0.5, y: 0.42), radius: CGSize(width: 0.7, height: 0.7)))
        // Комбинезон: всё ниже воротника.
        let suit = svg { path in
            path.move(to: CGPoint(x: 4, y: 30.4))
            path.addLine(to: CGPoint(x: 14, y: 29.2))
            path.addLine(to: CGPoint(x: 24, y: 36))
            path.addLine(to: CGPoint(x: 34, y: 29.2))
            path.addLine(to: CGPoint(x: 44, y: 30.4))
            path.addLine(to: CGPoint(x: 44, y: 48))
            path.addLine(to: CGPoint(x: 4, y: 48))
            path.closeSubpath()
        }
        clip.addSublayer(shape(suit, fill: Color.suit, opacity: 0.9))
        clip.addSublayer(shape(line([(4, 30.4), (14, 29.2), (24, 36), (34, 29.2), (44, 30.4)]), stroke: Color.amber, width: 1.5))
        clip.addSublayer(shape(line([(24, 36), (24, 38.4)]), stroke: Color.amber, width: 1, dash: [1.2, 1.2], opacity: 0.8))
        clip.addSublayer(hemShade(from: 38, to: 48, opacity: 0.5))
        root.addSublayer(clip)
        root.addSublayer(shape(bodyPath, stroke: Color.stroke, width: 1.5))
        root.addSublayer(text("111", size: 4.4, color: Color.amber, x: 14, baselineY: 42.8, width: 20))

        // Руки-ладошки по бокам и Пип-бой на левой.
        for x in [2.6, 45.4] as [CGFloat] {
            root.addSublayer(shape(ellipse(x, 35, 2.4, 2.9), fill: Color.body, stroke: Color.stroke, width: 1.1))
        }
        let pipRect = svg { $0.addRoundedRect(in: CGRect(x: -3.4, y: 33, width: 4.6, height: 3.4), cornerWidth: 0.5, cornerHeight: 0.5) }
        root.addSublayer(shape(pipRect, fill: Color.deep, stroke: Color.amber, width: 0.7))
        root.addSublayer(shape(svg { $0.addRect(CGRect(x: -2.4, y: 33.9, width: 2.6, height: 1.5)) }, fill: Color.amber, opacity: 0.85))

        // Сведённые брови и улыбка.
        root.addSublayer(shape(line([(12.6, 18.4), (20.6, 20.4)]), stroke: Color.green, width: 1.3))
        root.addSublayer(shape(line([(35.4, 18.4), (27.4, 20.4)]), stroke: Color.green, width: 1.3))
        root.addSublayer(shape(quad(20.5, 30.6, 24, 32.4, 27.5, 30.6), stroke: Color.green, width: 1.1))
        for x in [17, 31] as [CGFloat] {
            eyes.addSublayer(shape(ellipse(x, 24.5, 3, 3.5), fill: Color.green))
        }
        for x in [18.2, 32.2] as [CGFloat] {
            eyes.addSublayer(shape(ellipse(x, 23, 1, 1), fill: Color.pupil))
        }
        finish()
    }

    // MARK: - Терминал

    private func buildTerminal() {
        // Второй контур со сдвигом — остаточное свечение.
        let ghosting = shape(bodyPath, stroke: Color.dim, width: 1.2, opacity: 0.5)
        ghosting.transform = CATransform3DMakeTranslation(0.9 * scale, -0.5 * scale, 0)
        root.addSublayer(ghosting)

        body.fillColor = Color.tint.withAlphaComponent(0.7).cgColor
        body.strokeColor = Color.green.cgColor
        body.lineWidth = 1.3 * scale
        body.lineDashPattern = [NSNumber(value: Double(3 * scale)), NSNumber(value: Double(1.4 * scale))]
        root.addSublayer(body)

        let clip = clipped()
        // Строки развёртки.
        let rows = CAReplicatorLayer()
        rows.frame = root.bounds
        rows.instanceCount = 22
        rows.instanceTransform = CATransform3DMakeTranslation(0, -2 * scale, 0)
        let row = CALayer()
        row.backgroundColor = Color.green.withAlphaComponent(0.22).cgColor
        row.frame = CGRect(x: 0, y: (MothShape.size.height - 4.7) * scale, width: size.width, height: 0.7 * scale)
        rows.addSublayer(row)
        clip.addSublayer(rows)
        // Сетка.
        let grid = svg { path in
            for y in [12, 20, 28, 36] as [CGFloat] { path.move(to: CGPoint(x: 4, y: y)); path.addLine(to: CGPoint(x: 44, y: y)) }
            for x in [12, 20, 28, 36] as [CGFloat] { path.move(to: CGPoint(x: x, y: 4)); path.addLine(to: CGPoint(x: x, y: 48)) }
        }
        clip.addSublayer(shape(grid, stroke: Color.green, width: 0.25, opacity: 0.18))
        // Луч развёртки ползёт сверху вниз.
        let beam = CALayer()
        beam.backgroundColor = Color.green.withAlphaComponent(0.22).cgColor
        beam.frame = CGRect(x: 2 * scale, y: (MothShape.size.height - 7) * scale, width: 44 * scale, height: 3 * scale)
        let travel = CABasicAnimation(keyPath: "transform.translation.y")
        travel.fromValue = 0
        travel.toValue = -40 * scale
        travel.duration = 3.6
        travel.repeatCount = .infinity
        beam.add(travel, forKey: "beam")
        clip.addSublayer(beam)
        root.addSublayer(clip)
        flickerLayers = [ghosting, body, clip]

        // Приглашение и мигающий курсор.
        root.addSublayer(text(">_", size: 5, color: Color.green, weight: .regular, x: 13, baselineY: 36.4, width: 10, centered: false))
        let cursor = CALayer()
        cursor.backgroundColor = Color.green.cgColor
        cursor.frame = CGRect(x: 23.4 * scale, y: (MothShape.size.height - 37) * scale, width: 2.8 * scale, height: 4.6 * scale)
        let blink = CAKeyframeAnimation(keyPath: "opacity")
        blink.values = [1, 1, 0, 0]
        blink.keyTimes = [0, 0.5, 0.5, 1]
        blink.duration = 0.9
        blink.repeatCount = .infinity
        blink.calculationMode = .discrete
        cursor.add(blink, forKey: "cursor")
        root.addSublayer(cursor)

        // Квадратные глаза с квадратными бликами.
        for x in [14, 28] as [CGFloat] {
            eyes.addSublayer(shape(svg { $0.addRect(CGRect(x: x, y: 20.5, width: 6, height: 7)) }, fill: Color.green))
            eyes.addSublayer(shape(svg { $0.addRect(CGRect(x: x + 1.2, y: 21.6, width: 2, height: 2)) }, fill: Color.pale))
        }
        glowEyes()
        finish()
    }

    // MARK: - Радиация

    private func buildRadiation() {
        // Два кольца-импульса расходятся от призрака и гаснут; нижний слой.
        for delay in [0.0, 1.4] {
            let ring = shape(ellipse(24, 26, 23, 26), stroke: Color.green, width: 0.8, opacity: 0)
            ring.anchorPoint = CGPoint(x: 0.5, y: 1 - 26 / MothShape.size.height)
            ring.position = CGPoint(x: size.width / 2, y: (MothShape.size.height - 26) * scale)
            let grow = CABasicAnimation(keyPath: "transform.scale")
            grow.fromValue = 0.7
            grow.toValue = 1.4
            let fade = CAKeyframeAnimation(keyPath: "opacity")
            fade.values = [0.6, 0]
            let group = CAAnimationGroup()
            group.animations = [grow, fade]
            group.duration = 2.8
            group.repeatCount = .infinity
            group.timingFunction = CAMediaTimingFunction(name: .easeOut)
            group.beginTime = CACurrentMediaTime() + delay
            group.fillMode = .backwards
            ring.add(group, forKey: "ring")
            root.addSublayer(ring)
        }
        // Искры поднимаются от подола.
        for (index, spot) in [(6.0, 42.0), (41.0, 38.0), (24.0, 46.0), (33.0, 46.0)].enumerated() {
            let spark = shape(ellipse(spot.0, spot.1, 0.85, 0.85), fill: Color.light)
            spark.opacity = 0
            let rise = CABasicAnimation(keyPath: "transform.translation.y")
            rise.fromValue = 0
            rise.toValue = 16 * scale
            let fade = CAKeyframeAnimation(keyPath: "opacity")
            fade.values = [0, 1, 0]
            fade.keyTimes = [0, 0.15, 1]
            let group = CAAnimationGroup()
            group.animations = [rise, fade]
            group.duration = 3
            group.repeatCount = .infinity
            group.beginTime = CACurrentMediaTime() + Double(index) * 0.8
            group.fillMode = .backwards
            spark.add(group, forKey: "spark")
            root.addSublayer(spark)
        }

        body.fillColor = Color.body.cgColor
        body.shadowOpacity = 0.6
        root.addSublayer(body)
        let clip = clipped()
        clip.addSublayer(radial([Color.hot, CompanionView.Palette.rgb(0x1f4b15), Color.deep], [0, 0.55, 1],
                                center: CGPoint(x: 0.5, y: 0.42), radius: CGSize(width: 0.7, height: 0.7)))
        clip.addSublayer(shape(ellipse(24, 26, 20, 22), fill: Color.green, opacity: 0.08))
        clip.addSublayer(hemShade(from: 34, to: 48, opacity: 0.5))
        // Пятна и жилки.
        for (x, y, r, a) in [(12.0, 36.0, 1.1, 0.3), (35.0, 14.0, 0.9, 0.3), (38.0, 36.0, 1.4, 0.25)] as [(CGFloat, CGFloat, CGFloat, Float)] {
            clip.addSublayer(shape(ellipse(x, y, r, r), fill: Color.green, opacity: a))
        }
        clip.addSublayer(shape(quad(9, 30, 12, 34, 11, 40), stroke: Color.green, width: 0.6, opacity: 0.35))
        clip.addSublayer(shape(quad(39, 24, 36, 29, 37, 34), stroke: Color.green, width: 0.6, opacity: 0.35))
        root.addSublayer(clip)
        root.addSublayer(shape(bodyPath, stroke: Color.green, width: 1.6))
        root.addSublayer(shape(quad(21.5, 34, 24, 35.4, 26.5, 34), stroke: Color.green, width: 1.1, opacity: 0.85))

        // Светящиеся прищуренные глаза с белым ядром.
        for x in [17, 31] as [CGFloat] {
            eyes.addSublayer(shape(ellipse(x, 24, 3.4, 2.6), fill: Color.pale))
            eyes.addSublayer(shape(ellipse(x, 24, 2, 1.7), fill: Color.green))
        }
        eyes.shadowColor = Color.green.cgColor
        eyes.shadowOpacity = 1
        eyes.shadowRadius = 3.2 * scale
        eyes.shadowOffset = .zero
        finish()
    }
}
