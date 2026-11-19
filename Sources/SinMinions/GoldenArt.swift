import AppKit
import QuartzCore
import SinMinionsCore

/// Что нужно окну персонажа от рисунка: корень слоёв, тело для свечения и попаданий, глаза для моргания и взгляда.
@MainActor
protocol CompanionArt: AnyObject {
    var root: CALayer { get }
    var body: CAShapeLayer { get }
    var eyes: CALayer { get }
    var bodyPath: CGPath { get }
    var eyesHome: CGPoint { get }
    var glowScale: CGFloat { get }
}

extension GhostArt: CompanionArt {}

/// Второй персонаж: золотой страж, коренастый, в мультяшном стиле (толстый контур, тень и блик на каждой детали).
/// Рисунок собран по макету 200×232; весь он вписан в тот же прямоугольник, что и призрак (48×56 на единицу размера).
@MainActor
final class GoldenArt: CompanionArt {
    let scale: CGFloat
    let root = CALayer()
    let body = CAShapeLayer()
    let eyes = CALayer()
    private(set) var bodyPath: CGPath = CGPath(rect: .zero, transform: nil)
    private(set) var eyesHome = CGPoint.zero
    var glowScale: CGFloat { 1 }

    private let size: CGSize
    private let kx: CGFloat
    private let ky: CGFloat
    private let figure = CALayer()

    private struct Shade {
        let base: NSColor
        let shade: NSColor
        let hi: NSColor
    }

    private static func rgb(_ hex: UInt32) -> NSColor { CompanionView.Palette.rgb(hex) }

    private let outline = GoldenArt.rgb(0x1c1206)
    private let gold = Shade(base: GoldenArt.rgb(0xe1aa3a), shade: GoldenArt.rgb(0xa9731f), hi: GoldenArt.rgb(0xf9db7c))
    private let dark = Shade(base: GoldenArt.rgb(0xb98428), shade: GoldenArt.rgb(0x7e5413), hi: GoldenArt.rgb(0xe0b04e))
    private let red = Shade(base: GoldenArt.rgb(0xa3261e), shade: GoldenArt.rgb(0x661410), hi: GoldenArt.rgb(0xd4564a))
    private let cream = Shade(base: GoldenArt.rgb(0xebdfc3), shade: GoldenArt.rgb(0xbfae86), hi: GoldenArt.rgb(0xfbf4e2))
    private let skin = GoldenArt.rgb(0xf0c9a4)
    private let faceLine = GoldenArt.rgb(0x2a160c)
    private let beardColor = GoldenArt.rgb(0x3a281d)

    /// Пропорции макета: ширина и высота рисунка в его единицах.
    private static let designWidth: CGFloat = 200
    private static let designHeight: CGFloat = 232

    init(scale: CGFloat) {
        self.scale = scale
        size = CGSize(width: MothShape.size.width * scale, height: MothShape.size.height * scale)
        kx = size.width / Self.designWidth
        ky = size.height / Self.designHeight
        root.bounds = CGRect(origin: .zero, size: size)
        figure.frame = root.bounds
        build()
    }

    // MARK: - Помощники

    private var flip: CGAffineTransform {
        CGAffineTransform(a: kx, b: 0, c: 0, d: -ky, tx: 0, ty: size.height)
    }

    /// Правая половина фигуры зеркалится от левой: x → 200 − x.
    private var mirror: CGAffineTransform { CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: 200, ty: 0) }

    /// Путь из SVG-подобной записи (M L H V Q C Z, координаты абсолютные) в координаты слоя.
    private func path(_ d: String, _ t: CGAffineTransform = .identity) -> CGPath {
        let result = CGMutablePath()
        let chars = Array(d)
        var i = 0
        var command: Character = "M"
        var numbers: [CGFloat] = []
        var current = CGPoint.zero
        var start = CGPoint.zero
        let m = t.concatenating(flip)

        func flush() {
            switch command {
            case "M":
                var j = 0
                while j + 1 < numbers.count {
                    let point = CGPoint(x: numbers[j], y: numbers[j + 1])
                    if j == 0 { result.move(to: point, transform: m); start = point } else { result.addLine(to: point, transform: m) }
                    current = point
                    j += 2
                }
            case "L":
                var j = 0
                while j + 1 < numbers.count {
                    current = CGPoint(x: numbers[j], y: numbers[j + 1])
                    result.addLine(to: current, transform: m)
                    j += 2
                }
            case "H":
                for x in numbers { current = CGPoint(x: x, y: current.y); result.addLine(to: current, transform: m) }
            case "V":
                for y in numbers { current = CGPoint(x: current.x, y: y); result.addLine(to: current, transform: m) }
            case "Q":
                var j = 0
                while j + 3 < numbers.count {
                    let control = CGPoint(x: numbers[j], y: numbers[j + 1])
                    current = CGPoint(x: numbers[j + 2], y: numbers[j + 3])
                    result.addQuadCurve(to: current, control: control, transform: m)
                    j += 4
                }
            case "C":
                var j = 0
                while j + 5 < numbers.count {
                    let c1 = CGPoint(x: numbers[j], y: numbers[j + 1])
                    let c2 = CGPoint(x: numbers[j + 2], y: numbers[j + 3])
                    current = CGPoint(x: numbers[j + 4], y: numbers[j + 5])
                    result.addCurve(to: current, control1: c1, control2: c2, transform: m)
                    j += 6
                }
            case "Z":
                result.closeSubpath()
                current = start
            default: break
            }
            numbers = []
        }

        while i < chars.count {
            let c = chars[i]
            if c.isLetter {
                flush()
                command = c
                if c == "Z" { flush() }
                i += 1
            } else if c == " " || c == "," {
                i += 1
            } else {
                var j = i
                if chars[j] == "-" { j += 1 }
                while j < chars.count, chars[j].isNumber || chars[j] == "." { j += 1 }
                if let value = Double(String(chars[i..<j])) { numbers.append(CGFloat(value)) }
                i = max(j, i + 1)
            }
        }
        flush()
        return result
    }

    private func ellipse(_ cx: CGFloat, _ cy: CGFloat, _ rx: CGFloat, _ ry: CGFloat, _ t: CGAffineTransform = .identity) -> CGPath {
        var m = t.concatenating(flip)
        return CGPath(ellipseIn: CGRect(x: cx - rx, y: cy - ry, width: rx * 2, height: ry * 2), transform: &m)
    }

    private func layer(_ path: CGPath, fill: NSColor? = nil, stroke: NSColor? = nil, width: CGFloat = 1, opacity: Float = 1) -> CAShapeLayer {
        let l = CAShapeLayer()
        l.frame = root.bounds
        l.path = path
        l.fillColor = fill?.cgColor
        l.strokeColor = stroke?.cgColor
        l.lineWidth = width * kx
        l.lineJoin = .round
        l.lineCap = .round
        l.opacity = opacity
        return l
    }

    /// Мультяшная заливка: тень на всю форму, основной цвет со сдвигом (остаётся полоса тени), блик по краю, контур сверху.
    private func piece(_ p: CGPath, _ c: Shade, sx: CGFloat = -4, sy: CGFloat = -4, width: CGFloat = 3) {
        let wrap = CALayer()
        wrap.frame = root.bounds
        let clip = CALayer()
        clip.frame = root.bounds
        let mask = CAShapeLayer()
        mask.frame = root.bounds
        mask.path = p
        mask.fillColor = NSColor.black.cgColor
        clip.mask = mask
        var shift = CGAffineTransform(translationX: sx * kx, y: -sy * ky)
        var shiftHi = CGAffineTransform(translationX: sx * 0.7 * kx, y: -sy * 0.7 * ky)
        clip.addSublayer(layer(p, fill: c.shade))
        clip.addSublayer(layer(p.copy(using: &shift) ?? p, fill: c.base))
        clip.addSublayer(layer(p.copy(using: &shiftHi) ?? p, stroke: c.hi, width: 2.6, opacity: 0.9))
        wrap.addSublayer(clip)
        wrap.addSublayer(layer(p, stroke: outline, width: width))
        figure.addSublayer(wrap)
    }

    private func add(_ l: CALayer) { figure.addSublayer(l) }

    private func place(_ x: CGFloat, _ y: CGFloat, _ k: CGFloat, _ extra: CGAffineTransform = .identity) -> CGAffineTransform {
        CGAffineTransform(a: k, b: 0, c: 0, d: k, tx: x, ty: y).concatenating(extra)
    }

    // MARK: - Детали

    private static let wings = "M50 24 Q30 0 2 8 Q18 12 24 24 Q10 24 0 36 Q20 34 32 42 Q40 36 50 38 Q60 36 68 42 Q80 34 100 36 Q90 24 76 24 Q82 12 98 8 Q70 0 50 24 Z"

    private func eagle(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ c: Shade, _ extra: CGAffineTransform = .identity) {
        let k = w / 100
        piece(path(Self.wings, place(x, y, k, extra)), c, sx: -3 * k, sy: -3 * k, width: 3)
    }

    private func skull(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ extra: CGAffineTransform = .identity) {
        let t = place(x, y, w / 20, extra)
        let k = w / 20
        add(layer(path("M10 1 C16 1 19 5 18 10 C17.6 12.6 15.6 13.4 15 15 L15 18.5 Q15 20 13.5 20 L6.5 20 Q5 20 5 18.5 L5 15 C4.4 13.4 2.4 12.6 2 10 C1 5 4 1 10 1 Z", t),
                  fill: Self.rgb(0xf5e9c6), stroke: outline, width: 1.6 * k))
        add(layer(ellipse(6.8, 9.6, 2.4, 2.8, t), fill: Self.rgb(0x140b03)))
        add(layer(ellipse(13.2, 9.6, 2.4, 2.8, t), fill: Self.rgb(0x140b03)))
        add(layer(path("M10 12.4 L8.8 15 L11.2 15 Z", t), fill: Self.rgb(0x3a2508)))
        add(layer(path("M7.5 17.2 V20 M10 17.2 V20 M12.5 17.2 V20", t), stroke: outline, width: 0.9 * k))
    }

    private func leg(_ extra: CGAffineTransform) {
        piece(path("M40 194 Q30 214 48 216 L92 216 Q100 206 92 192 Z", extra), dark, sx: -3, sy: -4)
        piece(path("M54 164 L92 164 L90 198 L56 198 Z", extra), gold)
        piece(path(circlePath(72, 181, 11), extra), gold, sx: -3, sy: -3)
        add(layer(ellipse(72, 181, 3.2, 3.2, extra), fill: red.base, stroke: outline, width: 1.6))
    }

    private func circlePath(_ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat) -> String {
        // Окружность четырьмя квадратичными дугами достаточно точна для мелких деталей.
        return "M\(cx - r) \(cy) Q\(cx - r) \(cy - r) \(cx) \(cy - r) Q\(cx + r) \(cy - r) \(cx + r) \(cy) Q\(cx + r) \(cy + r) \(cx) \(cy + r) Q\(cx - r) \(cy + r) \(cx - r) \(cy) Z"
    }

    private func pauldron(_ extra: CGAffineTransform) {
        piece(path("M0 112 Q-4 68 34 62 Q68 64 70 98 Q68 134 34 140 Q2 138 0 112 Z", extra), gold, sx: -5, sy: -5)
        piece(path("M4 120 Q34 110 66 122 L64 132 Q34 124 6 132 Z", extra), dark, sx: 0, sy: -2, width: 2)
        eagle(10, 76, 48, dark, extra)
        skull(23, 94, 16, extra)
        add(layer(ellipse(10, 100, 3, 3, extra), fill: gold.hi, stroke: outline, width: 1.4))
        add(layer(ellipse(60, 104, 3, 3, extra), fill: gold.hi, stroke: outline, width: 1.4))
    }

    /// Рука висит вниз от плеча; `angle` — поворот по часовой стрелке вокруг плеча, как на макете.
    private func arm(pivot: CGPoint, angle: CGFloat) {
        let t = CGAffineTransform(translationX: pivot.x, y: pivot.y).rotated(by: angle * .pi / 180)
        let line = path("M0 0 L0 44", t)
        add(layer(line, stroke: outline, width: 29))
        add(layer(line, stroke: gold.shade, width: 23))
        var shift = CGAffineTransform(translationX: -2 * kx, y: 2 * ky)
        add(layer(line.copy(using: &shift) ?? line, stroke: gold.base, width: 18))
        var shiftHi = CGAffineTransform(translationX: -5 * kx, y: 4 * ky)
        add(layer(line.copy(using: &shiftHi) ?? line, stroke: gold.hi, width: 3))
        piece(path("M-9 40 H9 Q15 40 15 46 V58 Q15 65 9 65 H-9 Q-15 65 -15 58 V46 Q-15 40 -9 40 Z", t), dark, sx: -3, sy: -3)
        add(layer(path("M-4 44 V61 M5 44 V61", t), stroke: outline, width: 1.6, opacity: 0.8))
    }

    // MARK: - Лицо (по фото: широкое, зачёс назад, крупная борода)

    private func face() {
        let t = CGAffineTransform(translationX: 70, y: 22)
        func line(_ d: String, _ color: NSColor, _ w: CGFloat) -> CAShapeLayer { layer(path(d, t), stroke: color, width: w) }
        add(layer(ellipse(4.6, 33, 3, 5, t), fill: skin, stroke: faceLine, width: 1.8))
        add(layer(ellipse(55.4, 33, 3, 5, t), fill: skin, stroke: faceLine, width: 1.8))
        add(layer(path("M6 27 Q5 7 30 6 Q55 7 54 27 L55.5 38 Q54 56 30 60 Q6 56 4.5 38 Z", t), fill: skin, stroke: faceLine, width: 1.8))
        add(layer(ellipse(14, 40, 6, 4.5, t), fill: Self.rgb(0xe59a7e), opacity: 0.45))
        add(layer(ellipse(46, 40, 6, 4.5, t), fill: Self.rgb(0xe59a7e), opacity: 0.45))
        add(layer(path("M3.5 31 Q-1.5 2 30 -0.5 Q61.5 2 56.5 31 Q55 21 50 16 Q46 12 41 14 Q36 10 30 13 Q24 10 19 14 Q14 12 10 16 Q5 21 3.5 31 Z", t),
                  fill: Self.rgb(0x2b1d15), stroke: faceLine, width: 1.8))
        add(line("M12 12 Q30 2 48 12 M9 18 Q30 7 51 18 M20 10 Q30 5 40 10", Self.rgb(0x5f402e), 1.3))
        add(line("M30 29 Q27.8 37 26 39.6 Q30 42.4 34 39.6 Q32.2 37 30 29", Self.rgb(0xb07a55), 1.3))
        add(layer(path("M2.5 33 Q1 60 30 68 Q59 60 57.5 33 Q55 46 46 47.5 Q38 44 30 45 Q22 44 14 47.5 Q5 46 2.5 33 Z", t),
                  fill: beardColor, stroke: faceLine, width: 1.8))
        add(line("M10 56 Q30 65 50 56 M13 50 Q30 58 47 50 M20 61 Q30 64 40 61", Self.rgb(0x5f402e), 1.2))
        add(layer(ellipse(30, 50.4, 5, 2, t), fill: Self.rgb(0xb56a58), stroke: faceLine, width: 1))
        add(layer(path("M16 47.5 Q24 40.5 30 43.6 Q36 40.5 44 47.5 Q36 49.4 30 46.4 Q24 49.4 16 47.5 Z", t),
                  fill: beardColor, stroke: faceLine, width: 1.4))
        add(line("M13.5 24.8 Q20.5 21.4 28.4 24.6 M31.6 24.6 Q39.5 21.4 46.5 24.8", Self.rgb(0x1e130b), 3))
        // Глаза: отдельный слой, моргает и смотрит за курсором.
        let socket = faceLine
        for (cx, px, sx) in [(21.4, 21.8, 22.6), (38.6, 38.2, 39.0)] as [(CGFloat, CGFloat, CGFloat)] {
            eyes.addSublayer(layer(ellipse(cx, 29.4, 5.3, 3.5, t), fill: Self.rgb(0xfbf3e6), stroke: socket, width: 1.3))
            eyes.addSublayer(layer(ellipse(px, 29.4, 2.5, 2.5, t), fill: Self.rgb(0x3a281b)))
            eyes.addSublayer(layer(ellipse(px, 29.4, 1.1, 1.1, t), fill: Self.rgb(0x100905)))
            eyes.addSublayer(layer(ellipse(sx, 28.5, 0.8, 0.8, t), fill: .white))
        }
    }

    // MARK: - Сборка

    private func build() {
        // Плащ, воротник, ноги, табард, корпус, пояс, наплечники, руки, горжет и лицо — в порядке рисования макета.
        piece(path("M40 96 Q4 150 12 216 L188 216 Q196 150 160 96 Z"), red, sx: -6, sy: 0)
        piece(path("M56 100 L48 46 Q100 26 152 46 L144 100 Z"), dark, sx: -4, sy: -3)
        leg(.identity)
        leg(mirror)
        piece(path("M88 170 H112 L110 202 L100 210 L90 202 Z"), cream)
        add(layer(path("M100 176 V200"), stroke: red.base, width: 3))
        piece(path("M40 98 Q34 130 44 156 L156 156 Q166 130 160 98 Q130 82 100 82 Q70 82 40 98 Z"), gold)
        piece(path("M62 104 Q100 92 138 104 L132 146 Q100 154 68 146 Z"), dark, sx: -3, sy: -3)
        eagle(66, 112, 68, gold)
        skull(90, 118, 20)
        piece(path("M44 152 H156 Q160 152 160 156 V168 Q160 172 156 172 H44 Q40 172 40 168 V156 Q40 152 44 152 Z"), dark)
        piece(path(circlePath(100, 162, 11)), gold, sx: -3, sy: -3)
        skull(93, 155, 14)
        pauldron(.identity)
        pauldron(mirror)
        arm(pivot: CGPoint(x: 24, y: 116), angle: 5)
        // Правая рука прижата к груди, как на выбранном варианте «Рука к сердцу».
        arm(pivot: CGPoint(x: 176, y: 116), angle: 96)
        piece(path("M66 82 Q100 100 134 82 L138 98 Q100 114 62 98 Z"), gold, sx: -3, sy: -3)
        piece(path(circlePath(100, 100, 4)), red, sx: -1, sy: -1, width: 2)
        face()

        // Силуэт для попаданий мыши и для свечения: корпус, наплечники, голова, ноги.
        let silhouette = CGMutablePath()
        for d in [
            "M40 96 Q4 150 12 216 L188 216 Q196 150 160 96 Z",
            "M40 98 Q34 130 44 156 L156 156 Q166 130 160 98 Q130 82 100 82 Q70 82 40 98 Z",
            "M0 112 Q-4 68 34 62 Q68 64 70 98 Q68 134 34 140 Q2 138 0 112 Z",
            "M56 100 L48 46 Q100 26 152 46 L144 100 Z",
        ] {
            silhouette.addPath(path(d))
        }
        silhouette.addPath(path("M0 112 Q-4 68 34 62 Q68 64 70 98 Q68 134 34 140 Q2 138 0 112 Z", mirror))
        silhouette.addPath(path("M40 194 Q30 214 48 216 L92 216 Q100 206 92 192 Z"))
        silhouette.addPath(path("M40 194 Q30 214 48 216 L92 216 Q100 206 92 192 Z", mirror))
        silhouette.addPath(ellipse(100, 55, 32, 34))
        bodyPath = silhouette

        body.frame = root.bounds
        body.path = bodyPath
        body.fillColor = dark.shade.cgColor
        body.shadowPath = bodyPath
        body.shadowColor = Self.rgb(0xe8b84a).cgColor
        body.shadowOffset = .zero
        body.shadowRadius = 3 * scale
        body.shadowOpacity = 0.35

        // Статичная часть кэшируется: окно двигается и парит, а рисунок остаётся прежним.
        figure.shouldRasterize = true
        figure.rasterizationScale = NSScreen.main?.backingScaleFactor ?? 2

        eyes.bounds = root.bounds
        eyesHome = CGPoint(x: size.width / 2, y: size.height - 51.4 * ky)
        eyes.anchorPoint = CGPoint(x: 0.5, y: eyesHome.y / size.height)
        eyes.position = eyesHome

        root.addSublayer(body)
        root.addSublayer(figure)
        root.addSublayer(eyes)
    }
}
