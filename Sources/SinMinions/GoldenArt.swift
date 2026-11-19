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
    private let coffee: Bool
    let outfit: Outfit
    /// Контейнер всего рисунка: опускается, когда страж садится.
    private let figure = CALayer()
    /// Куда сейчас рисуются детали (группа, которую собирает `build`).
    private var sink = CALayer()
    private var capeG = CALayer()
    private var legLG = CALayer()
    private var legRG = CALayer()
    private var upperG = CALayer()
    private var armLG = CALayer()
    private var armRG = CALayer()
    private var padG = CALayer()
    private var headG = CALayer()
    private var mouthG = CALayer()
    private var cupG = CALayer()

    /// Основная поза; короткие реакции (клич, поклон) идут поверх неё.
    enum Pose { case idle, walk, sit, play }
    private(set) var pose: Pose = .idle
    private var armLAngle: CGFloat = 0
    private var armRAngle: CGFloat = 0
    private var cheering = false
    private var singing = false
    private var notesG: CALayer?

    private struct Shade {
        let base: NSColor
        let shade: NSColor
        let hi: NSColor
    }

    private static func rgb(_ hex: UInt32) -> NSColor { CompanionView.Palette.rgb(hex) }

    private let outline: NSColor
    private let pink = Shade(base: GoldenArt.rgb(0xf6adc0), shade: GoldenArt.rgb(0xd27791), hi: GoldenArt.rgb(0xffd9e3))
    private let white = Shade(base: GoldenArt.rgb(0xfbf1f3), shade: GoldenArt.rgb(0xd9c3c9), hi: GoldenArt.rgb(0xffffff))
    private let plum = Shade(base: GoldenArt.rgb(0x7a3350), shade: GoldenArt.rgb(0x4d1d32), hi: GoldenArt.rgb(0xa85a78))
    private let bare = Shade(base: GoldenArt.rgb(0xf0c9a4), shade: GoldenArt.rgb(0xcf9f78), hi: GoldenArt.rgb(0xfbe3cb))
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

    init(scale: CGFloat, coffee: Bool = false, outfit: Outfit = .armor) {
        self.scale = scale
        self.coffee = coffee
        self.outfit = outfit
        outline = outfit == .pajamas ? GoldenArt.rgb(0x2a1420) : GoldenArt.rgb(0x1c1206)
        size = CGSize(width: MothShape.size.width * scale, height: MothShape.size.height * scale)
        kx = size.width / Self.designWidth
        ky = size.height / Self.designHeight
        root.bounds = CGRect(origin: .zero, size: size)
        figure.frame = root.bounds
        sink = figure
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
    private func piece(_ p: CGPath, _ c: Shade, sx: CGFloat = -4, sy: CGFloat = -4, width: CGFloat = 3,
                       stripes: [CGRect] = [], stripeT: CGAffineTransform = .identity) {
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
        if !stripes.isEmpty {
            let bars = CGMutablePath()
            let m = stripeT.concatenating(flip)
            for r in stripes { bars.addRect(r, transform: m) }
            clip.addSublayer(layer(bars, fill: NSColor.white.withAlphaComponent(0.6)))
        }
        clip.addSublayer(layer(p.copy(using: &shiftHi) ?? p, stroke: c.hi, width: 2.6, opacity: 0.9))
        wrap.addSublayer(clip)
        wrap.addSublayer(layer(p, stroke: outline, width: width))
        sink.addSublayer(wrap)
    }

    private func add(_ l: CALayer) { sink.addSublayer(l) }

    /// Вертикальные полоски пижамы: шаг 9, ширина 4,2 (единицы макета).
    private func stripeRects(from x0: CGFloat, to x1: CGFloat, y: CGFloat, height: CGFloat) -> [CGRect] {
        var rects: [CGRect] = []
        var x = x0
        while x < x1 {
            rects.append(CGRect(x: x, y: y, width: 4.2, height: height))
            x += 9
        }
        return rects
    }

    /// Группа слоёв с осью поворота в точке макета: внутри координаты те же, что у корня.
    private func group(pivot: CGPoint, raster: Bool = true) -> CALayer {
        let g = CALayer()
        g.bounds = root.bounds
        g.anchorPoint = CGPoint(x: pivot.x * kx / size.width, y: 1 - pivot.y * ky / size.height)
        g.position = CGPoint(x: pivot.x * kx, y: size.height - pivot.y * ky)
        if raster {
            g.shouldRasterize = true
            g.rasterizationScale = NSScreen.main?.backingScaleFactor ?? 2
        }
        return g
    }

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
    private func arm(pivot: CGPoint) {
        let t = CGAffineTransform(translationX: pivot.x, y: pivot.y)
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

    // MARK: - Геймпад, кружка, рот

    private func gamepad() {
        let t = CGAffineTransform(translationX: 100, y: 140)
        let padShade = Shade(base: Self.rgb(0x3a4150), shade: Self.rgb(0x1d222c), hi: Self.rgb(0x7a86a0))
        piece(path("M-31 -6 Q-36 8 -31 15 Q-26 23 -18 15 L-10 9 H10 L18 15 Q26 23 31 15 Q36 8 31 -6 Q20 -14 0 -14 Q-20 -14 -31 -6 Z", t), padShade, sx: -2, sy: -2, width: 2.4)
        add(layer(path("M-11 -11 H11 V-5 H-11 Z", t), fill: Self.rgb(0x566074), stroke: outline, width: 1.4))
        add(layer(path("M-23 -4 H-15 M-19 -8 V0", t), stroke: Self.rgb(0xe8eefb), width: 3))
        for (x, y, color) in [(19, -8, 0x37c871), (24, -3, 0xe0453a), (19, 2, 0x4a8dff), (14, -3, 0xe07ab8)] as [(CGFloat, CGFloat, UInt32)] {
            add(layer(ellipse(x, y, 2.5, 2.5, t), fill: Self.rgb(color), stroke: outline, width: 1))
        }
        for x in [-8, 8] as [CGFloat] {
            add(layer(ellipse(x, 6, 4.6, 4.6, t), fill: Self.rgb(0x161a22), stroke: outline, width: 1.6))
            add(layer(ellipse(x, 6, 2, 2, t), fill: Self.rgb(0x4a5266)))
        }
        add(layer(path("M-6 -14 H6", t), stroke: Self.rgb(0x4fc3ff), width: 1.6))
    }

    /// Кружка в левой руке и пар над ней (режим «кофе»); `dy` — на сколько кисть ниже, чем у доспешной версии.
    private func cup(dy: CGFloat = 0) {
        let t = CGAffineTransform(translationX: 0, y: dy)
        let porcelain = Shade(base: Self.rgb(0xf3efe6), shade: Self.rgb(0xc9c1ad), hi: .white)
        add(layer(path("M34 156 Q43 158 41 168 Q39 173 34 172", t), stroke: outline, width: 6))
        add(layer(path("M34 156 Q43 158 41 168 Q39 173 34 172", t), stroke: porcelain.base, width: 3))
        piece(path("M12 152 H34 V172 Q34 179 27 179 H19 Q12 179 12 172 Z", t), porcelain, sx: -3, sy: -3, width: 2)
        add(layer(ellipse(23, 152.5, 11, 2.6, t), fill: Self.rgb(0x5a3a22), stroke: outline, width: 1.2))
        let steamX: [CGFloat] = [19, 27]
        for (index, x) in steamX.enumerated() {
            let steam = layer(path("M\(x) 148 Q\(x + 3) 144 \(x) 140 Q\(x - 3) 136 \(x) 132", t), stroke: .white, width: 1.6, opacity: 0)
            let fade = CAKeyframeAnimation(keyPath: "opacity")
            fade.values = [0, 0.75, 0.75, 0]
            fade.keyTimes = [0, 0.3, 0.7, 1]
            let rise = CABasicAnimation(keyPath: "transform.translation.y")
            rise.fromValue = 0
            rise.toValue = 4 * ky
            let both = CAAnimationGroup()
            both.animations = [fade, rise]
            both.duration = 2.2
            both.beginTime = CACurrentMediaTime() + Double(index) * 1.1
            both.repeatCount = .infinity
            steam.add(both, forKey: "steam")
            add(steam)
        }
    }

    /// Открытый рот для клича «В бой!»: поверх закрытого.
    private func mouth() {
        let t = CGAffineTransform(translationX: 70, y: 22)
        add(layer(ellipse(30, 51.5, 7, 5.6, t), fill: Self.rgb(0x2a0c0c), stroke: faceLine, width: 1.2))
        add(layer(ellipse(30, 54.5, 4, 2.2, t), fill: Self.rgb(0xb24a4a)))
    }

    // MARK: - Сборка

    private func buildArmorBody() {
        // Плащ, воротник, ноги, табард, корпус, пояс, наплечники, руки, горжет и лицо — в порядке рисования макета.
        // Подвижные части собраны в группы с осью поворота: бёдра у ног, плечи у рук, пояс у корпуса.
        capeG = group(pivot: CGPoint(x: 100, y: 96))
        sink = capeG
        piece(path("M40 96 Q4 150 12 216 L188 216 Q196 150 160 96 Z"), red, sx: -6, sy: 0)
        figure.addSublayer(capeG)

        legLG = group(pivot: CGPoint(x: 73, y: 164))
        sink = legLG
        leg(.identity)
        figure.addSublayer(legLG)
        legRG = group(pivot: CGPoint(x: 127, y: 164))
        sink = legRG
        leg(mirror)
        figure.addSublayer(legRG)

        upperG = group(pivot: CGPoint(x: 100, y: 170), raster: false)
        let torsoG = group(pivot: CGPoint(x: 100, y: 170))
        sink = torsoG
        piece(path("M56 100 L48 46 Q100 26 152 46 L144 100 Z"), dark, sx: -4, sy: -3)
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
        upperG.addSublayer(torsoG)

        // Руки висят вниз от плеч; нужный угол задаёт поза.
        armLG = group(pivot: CGPoint(x: 24, y: 116), raster: !coffee)
        sink = armLG
        arm(pivot: CGPoint(x: 24, y: 116))
        cupG = group(pivot: CGPoint(x: 24, y: 160))
        sink = cupG
        if coffee { cup() }
        armLG.addSublayer(cupG)
        upperG.addSublayer(armLG)
        armRG = group(pivot: CGPoint(x: 176, y: 116))
        sink = armRG
        arm(pivot: CGPoint(x: 176, y: 116))
        upperG.addSublayer(armRG)
    }

    // MARK: - Пижама и колпак

    private func pajamaLeg(_ extra: CGAffineTransform) {
        piece(path("M44 214 Q34 226 52 228 L90 228 Q98 220 92 214 Z", extra), plum, sx: -3, sy: -3)
        piece(path("M48 150 L98 150 L97 214 L43 214 Z", extra), pink, stripes: stripeRects(from: 40, to: 100, y: 140, height: 90), stripeT: extra)
        add(layer(path("M43 208 L97 208", extra), stroke: white.base, width: 4))
        add(layer(path("M43 208 L97 208", extra), stroke: outline, width: 1, opacity: 0.5))
    }

    /// Рукав с манжетой и кистью вниз от плеча (0, 0); `t` ставит плечо на место, у правой руки с отражением.
    private func pajamaSleeve(_ t: CGAffineTransform) {
        piece(path("M-14 -6 Q-18 24 -14 54 L12 54 Q14 24 12 -6 Q-1 -16 -14 -6 Z", t), pink, width: 2.8,
              stripes: stripeRects(from: -20, to: 18, y: -20, height: 90), stripeT: t)
        piece(path("M-15 50 L13 50 L13 60 L-15 60 Z", t), white, sx: -2, sy: -2, width: 2.2)
        piece(path("M-12 58 Q-14 76 -2 78 Q12 76 12 58 Z", t), bare, sx: -3, sy: -3, width: 2.4)
        add(layer(path("M-6 70 V76 M2 70 V76", t), stroke: outline, width: 1.4, opacity: 0.6))
    }

    private func buildPajamaBody() {
        capeG = group(pivot: CGPoint(x: 100, y: 96))
        figure.addSublayer(capeG)

        legLG = group(pivot: CGPoint(x: 73, y: 164))
        sink = legLG
        pajamaLeg(.identity)
        figure.addSublayer(legLG)
        legRG = group(pivot: CGPoint(x: 127, y: 164))
        sink = legRG
        pajamaLeg(mirror)
        figure.addSublayer(legRG)

        upperG = group(pivot: CGPoint(x: 100, y: 170), raster: false)
        let torsoG = group(pivot: CGPoint(x: 100, y: 170))
        sink = torsoG
        let bars = stripeRects(from: 30, to: 175, y: 70, height: 110)
        piece(path("M36 100 Q30 134 38 168 L162 168 Q170 134 164 100 Q132 84 100 84 Q68 84 36 100 Z"), pink, stripes: bars)
        add(layer(path("M38 164 L162 164"), stroke: white.base, width: 4))
        add(layer(path("M38 168 L162 168"), stroke: outline, width: 1, opacity: 0.5))
        piece(path("M80 86 Q100 98 120 86 L100 126 Z"), bare, sx: -2, sy: -2, width: 2.4)
        piece(path("M78 84 L98 128 L84 134 L62 100 Z"), pink, width: 2.6, stripes: stripeRects(from: 60, to: 100, y: 80, height: 60))
        piece(path("M78 84 L98 128 L84 134 L62 100 Z", mirror), pink, width: 2.6, stripes: stripeRects(from: 60, to: 100, y: 80, height: 60), stripeT: mirror)
        add(layer(path("M100 128 V168"), stroke: outline, width: 2, opacity: 0.6))
        piece(path("M116 124 H138 V142 H116 Z"), pink, sx: -2, sy: -2, width: 2, stripes: stripeRects(from: 114, to: 140, y: 120, height: 26))
        for y in [138, 150, 162] as [CGFloat] {
            add(layer(ellipse(100, y, 3, 3), fill: white.base, stroke: outline, width: 1.6))
        }
        upperG.addSublayer(torsoG)

        armLG = group(pivot: CGPoint(x: 26, y: 112), raster: !coffee)
        sink = armLG
        pajamaSleeve(CGAffineTransform(translationX: 26, y: 112))
        cupG = group(pivot: CGPoint(x: 26, y: 170))
        sink = cupG
        if coffee { cup(dy: 14) }
        armLG.addSublayer(cupG)
        upperG.addSublayer(armLG)
        armRG = group(pivot: CGPoint(x: 174, y: 112))
        sink = armRG
        pajamaSleeve(CGAffineTransform(translationX: 26, y: 112).concatenating(mirror))
        upperG.addSublayer(armRG)
    }

    /// Ночной колпак: белая лента на лбу, полосатый конус и свисающий хвост с помпоном.
    private func nightcap() {
        piece(path("M66 44 Q62 16 92 8 Q124 0 146 28 Q160 52 154 82 L140 84 Q146 60 132 44 Q118 30 100 30 Q82 30 66 44 Z"), pink, width: 3,
              stripes: stripeRects(from: 60, to: 165, y: 0, height: 90))
        piece(path("M62 44 Q100 22 138 44 L136 54 Q100 34 64 54 Z"), white, sx: -2, sy: -3, width: 2.6)
        piece(path(circlePath(147, 88, 8)), white, sx: -2, sy: -2, width: 2.6)
    }

    private func build() {
        if outfit == .pajamas { buildPajamaBody() } else { buildArmorBody() }

        padG = group(pivot: CGPoint(x: 100, y: 140))
        sink = padG
        gamepad()
        padG.opacity = 0
        upperG.addSublayer(padG)

        headG = group(pivot: CGPoint(x: 100, y: 80), raster: false)
        let headStatic = group(pivot: CGPoint(x: 100, y: 80))
        sink = headStatic
        if outfit == .pajamas {
            add(layer(path("M86 82 H114 V98 H86 Z"), fill: bare.shade))
            face()
            nightcap()
        } else {
            piece(path("M66 82 Q100 100 134 82 L138 98 Q100 114 62 98 Z"), gold, sx: -3, sy: -3)
            piece(path(circlePath(100, 100, 4)), red, sx: -1, sy: -1, width: 2)
            face()
        }
        headG.addSublayer(headStatic)
        mouthG = group(pivot: CGPoint(x: 100, y: 80))
        sink = mouthG
        mouth()
        mouthG.opacity = 0
        headG.addSublayer(mouthG)
        headG.addSublayer(eyes)
        upperG.addSublayer(headG)
        figure.addSublayer(upperG)
        sink = figure

        // Силуэт для попаданий мыши и для свечения: корпус, наплечники, голова, ноги.
        let silhouette = CGMutablePath()
        if outfit == .pajamas {
            silhouette.addPath(path("M36 100 Q30 134 38 168 L162 168 Q170 134 164 100 Q132 84 100 84 Q68 84 36 100 Z"))
            silhouette.addPath(path("M-14 -6 Q-18 24 -14 54 L12 78 L12 -6 Z", CGAffineTransform(translationX: 26, y: 112)))
            silhouette.addPath(path("M-14 -6 Q-18 24 -14 54 L12 78 L12 -6 Z", CGAffineTransform(translationX: 26, y: 112).concatenating(mirror)))
            silhouette.addPath(path("M43 150 L98 150 L97 228 L38 228 Z"))
            silhouette.addPath(path("M43 150 L98 150 L97 228 L38 228 Z", mirror))
            silhouette.addPath(ellipse(100, 55, 32, 34))
            silhouette.addPath(path("M66 44 Q62 16 92 8 Q124 0 146 28 Q160 52 154 82 L140 84 Q146 60 132 44 Z"))
        } else {
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
        }
        bodyPath = silhouette

        body.frame = root.bounds
        body.path = bodyPath
        body.fillColor = dark.shade.cgColor
        body.shadowPath = bodyPath
        body.shadowColor = Self.rgb(outfit == .pajamas ? 0xf6adc0 : 0xe8b84a).cgColor
        body.shadowOffset = .zero
        body.shadowRadius = 3 * scale
        body.shadowOpacity = 0.35

        eyes.bounds = root.bounds
        eyesHome = CGPoint(x: size.width / 2, y: size.height - 51.4 * ky)
        eyes.anchorPoint = CGPoint(x: 0.5, y: eyesHome.y / size.height)
        eyes.position = eyesHome

        root.addSublayer(body)
        root.addSublayer(figure)
        applyPose(animated: false)
        // Едва заметное дыхание: страж стоит на месте, но не замирает.
        upperG.add(additive("transform.translation.y", [0, 1.2 * ky, 0], duration: 3.2, times: [0, 0.5, 1]), forKey: "breath")
    }

    // MARK: - Позы и анимации

    private func radians(_ degrees: CGFloat) -> CGFloat { degrees * .pi / 180 }

    private func rotation(_ degrees: CGFloat) -> CATransform3D { CATransform3DMakeRotation(radians(degrees), 0, 0, 1) }

    /// Углы рук по позе в градусах слоя (против часовой стрелки): левая висит чуть наружу, правая прижата к груди.
    private func armAngles(for pose: Pose) -> (left: CGFloat, right: CGFloat) {
        if outfit == .pajamas {
            return pose == .play ? (66.5, -66.5) : (-4, 4)
        }
        switch pose {
        case .idle: return (-5, -96)
        case .walk: return (-5, 5)
        case .sit: return (-5, -96)
        case .play: return (66.5, -66.5)
        }
    }

    /// Сменить основную позу: стойка, ходьба (перелёт), посадка (сон) или игра на приставке.
    func setPose(_ newPose: Pose) {
        guard newPose != pose else { return }
        pose = newPose
        applyPose(animated: true)
    }

    private func turnArm(_ layer: CALayer, from: CGFloat, to: CGFloat, duration: CFTimeInterval = 0.35) {
        let turn = CABasicAnimation(keyPath: "transform.rotation.z")
        turn.fromValue = radians(from)
        turn.toValue = radians(to)
        turn.duration = max(duration, 0.001)
        turn.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        layer.transform = rotation(to)
        layer.add(turn, forKey: "turn")
    }

    private func applyPose(animated: Bool) {
        for g in [legLG, legRG, armLG, armRG, upperG] {
            g.removeAnimation(forKey: "walk")
            g.removeAnimation(forKey: "step")
            g.removeAnimation(forKey: "sing")
        }
        headG.removeAnimation(forKey: "sing")
        upperG.removeAnimation(forKey: "step2")
        if singing { stopSingingEffects() }
        for g in [legLG, legRG, upperG] { g.removeAnimation(forKey: "walk2") }
        CATransaction.begin()
        CATransaction.setAnimationDuration(animated ? 0.35 : 0)
        let seated = pose == .sit || pose == .play
        figure.transform = CATransform3DMakeTranslation(0, seated ? -(pose == .play ? 32 : 24) * ky : 0, 0)
        let legScale: CGFloat = seated ? (pose == .play ? 0.5 : 0.6) : 1
        let splay: CGFloat = seated ? (pose == .play ? 26 : 16) : 0
        legLG.transform = CATransform3DConcat(CATransform3DMakeScale(1, legScale, 1), rotation(-splay))
        legRG.transform = CATransform3DConcat(CATransform3DMakeScale(1, legScale, 1), rotation(splay))
        padG.opacity = pose == .play ? 1 : 0
        cupG.opacity = pose == .play ? 0 : 1
        // Голова поворачивается к телевизору и чуть наклоняется.
        headG.transform = pose == .play
            ? CATransform3DConcat(rotation(-5), CATransform3DMakeTranslation(3 * kx, -6 * ky, 0))
            : CATransform3DIdentity
        upperG.transform = pose == .play ? CATransform3DMakeScale(1, 0.95, 1) : CATransform3DIdentity
        CATransaction.commit()

        let target = armAngles(for: pose)
        let d: CFTimeInterval = animated ? 0.35 : 0.001
        if !cheering {
            turnArm(armLG, from: armLAngle, to: target.left, duration: d)
            turnArm(armRG, from: armRAngle, to: target.right, duration: d)
            armLAngle = target.left
            armRAngle = target.right
        } else {
            turnArm(armLG, from: armLAngle, to: target.left, duration: d)
            armLAngle = target.left
        }
        if pose == .walk { startWalking() }
        if pose == .play { startPlayingMotion() }
    }

    private func additive(_ keyPath: String, _ values: [CGFloat], duration: CFTimeInterval, times: [NSNumber], repeats: Float = .infinity) -> CAKeyframeAnimation {
        let a = CAKeyframeAnimation(keyPath: keyPath)
        a.values = values
        a.keyTimes = times
        a.duration = duration
        a.repeatCount = repeats
        a.isAdditive = true
        return a
    }

    /// Шаг: ноги поднимаются по очереди, руки качаются навстречу, корпус подпрыгивает и покачивается.
    private func startWalking() {
        let t: [NSNumber] = [0, 0.25, 0.5, 0.75, 1]
        // Шаг заметный: нога поднимается высоко, корпус клонится в сторону опорной ноги и подпрыгивает.
        let lift = 16 * ky, swing = radians(18), sway = radians(3.5), period: CFTimeInterval = 0.55
        legLG.add(additive("transform.translation.y", [0, lift, 0, 0, 0], duration: period, times: t), forKey: "walk")
        legRG.add(additive("transform.translation.y", [0, 0, 0, lift, 0], duration: period, times: t), forKey: "walk")
        legLG.add(additive("transform.rotation.z", [0, radians(-8), 0, 0, 0], duration: period, times: t), forKey: "walk2")
        legRG.add(additive("transform.rotation.z", [0, 0, 0, radians(8), 0], duration: period, times: t), forKey: "walk2")
        armLG.add(additive("transform.rotation.z", [0, swing, 0, -swing, 0], duration: period, times: t), forKey: "walk")
        armRG.add(additive("transform.rotation.z", [0, -swing, 0, swing, 0], duration: period, times: t), forKey: "walk")
        upperG.add(additive("transform.translation.y", [0, 4 * ky, 0, 4 * ky, 0], duration: period, times: t), forKey: "walk")
        upperG.add(additive("transform.rotation.z", [0, sway, 0, -sway, 0], duration: period, times: t), forKey: "walk2")
    }

    /// Переступание на месте: несколько шагов подряд, затем стойка. Идёт только в спокойной стойке.
    func stepInPlace() {
        guard pose == .idle, !cheering, !singing else { return }
        let t: [NSNumber] = [0, 0.25, 0.5, 0.75, 1]
        let cycles = Float(Int.random(in: 2...4))
        let lift = 12 * ky, swing = radians(10), sway = radians(2.5), period: CFTimeInterval = 0.6
        legLG.add(additive("transform.translation.y", [0, lift, 0, 0, 0], duration: period, times: t, repeats: cycles), forKey: "step")
        legRG.add(additive("transform.translation.y", [0, 0, 0, lift, 0], duration: period, times: t, repeats: cycles), forKey: "step")
        armLG.add(additive("transform.rotation.z", [0, swing, 0, -swing, 0], duration: period, times: t, repeats: cycles), forKey: "step")
        armRG.add(additive("transform.rotation.z", [0, -swing, 0, swing, 0], duration: period, times: t, repeats: cycles), forKey: "step")
        upperG.add(additive("transform.translation.y", [0, 3 * ky, 0, 3 * ky, 0], duration: period, times: t, repeats: cycles), forKey: "step")
        upperG.add(additive("transform.rotation.z", [0, sway, 0, -sway, 0], duration: period, times: t, repeats: cycles), forKey: "step2")
    }

    /// Игра: руки на пульте подрагивают, пульт мигает кнопками.
    private func startPlayingMotion() {
        let t: [NSNumber] = [0, 0.5, 1]
        let jitter = radians(3)
        armLG.add(additive("transform.rotation.z", [0, jitter, 0], duration: 0.16, times: t), forKey: "walk")
        armRG.add(additive("transform.rotation.z", [0, -jitter, 0], duration: 0.2, times: t), forKey: "walk")
    }

    /// Пение: рот открывается и закрывается, корпус и голова покачиваются, левая рука отходит в сторону, над головой плывут ноты.
    func setSinging(_ on: Bool) {
        if on {
            guard pose == .idle, !singing else { return }
            singing = true
            let t: [NSNumber] = [0, 0.5, 1]
            let mouthAnim = CAKeyframeAnimation(keyPath: "opacity")
            mouthAnim.values = [0, 1, 0.15, 1, 0]
            mouthAnim.keyTimes = [0, 0.2, 0.45, 0.7, 1]
            mouthAnim.duration = 0.9
            mouthAnim.repeatCount = .infinity
            mouthG.add(mouthAnim, forKey: "sing")
            upperG.add(additive("transform.rotation.z", [0, radians(2.2), 0, radians(-2.2), 0], duration: 1.8, times: [0, 0.25, 0.5, 0.75, 1]), forKey: "sing")
            headG.add(additive("transform.rotation.z", [0, radians(-4), 0, radians(4), 0], duration: 1.8, times: [0, 0.25, 0.5, 0.75, 1]), forKey: "sing")
            armLG.add(additive("transform.rotation.z", [0, radians(-16), radians(-6), radians(-16), 0], duration: 1.8, times: [0, 0.25, 0.5, 0.75, 1]), forKey: "sing")
            _ = t
            addNotes()
        } else if singing {
            stopSingingEffects()
        }
    }

    private func stopSingingEffects() {
        singing = false
        mouthG.removeAnimation(forKey: "sing")
        upperG.removeAnimation(forKey: "sing")
        headG.removeAnimation(forKey: "sing")
        armLG.removeAnimation(forKey: "sing")
        notesG?.removeFromSuperlayer()
        notesG = nil
    }

    /// Ноты поднимаются над головой и тают.
    private func addNotes() {
        let group = CALayer()
        group.frame = root.bounds
        let glyphs = ["♪", "♫", "♪", "♫"]
        let spots: [(CGFloat, CGFloat)] = [(120, 26), (82, 20), (140, 40), (62, 36)]
        for (index, glyph) in glyphs.enumerated() {
            let note = CATextLayer()
            note.string = glyph
            note.fontSize = max(9, 16 * kx * 3)
            note.foregroundColor = Self.rgb(0xf9db7c).cgColor
            note.contentsScale = NSScreen.main?.backingScaleFactor ?? 2
            note.alignmentMode = .center
            note.bounds = CGRect(x: 0, y: 0, width: 18 * kx * 3, height: 20 * kx * 3)
            note.position = CGPoint(x: spots[index].0 * kx, y: size.height - spots[index].1 * ky)
            note.opacity = 0
            let rise = CABasicAnimation(keyPath: "transform.translation.y")
            rise.fromValue = 0
            rise.toValue = 26 * ky
            let sway = CAKeyframeAnimation(keyPath: "transform.translation.x")
            sway.values = [0, 5 * kx, -5 * kx, 0]
            sway.keyTimes = [0, 0.33, 0.66, 1]
            let fade = CAKeyframeAnimation(keyPath: "opacity")
            fade.values = [0, 1, 1, 0]
            fade.keyTimes = [0, 0.2, 0.7, 1]
            let both = CAAnimationGroup()
            both.animations = [rise, sway, fade]
            both.duration = 2.4
            both.beginTime = CACurrentMediaTime() + Double(index) * 0.6
            both.repeatCount = .infinity
            note.add(both, forKey: "note")
            group.addSublayer(note)
        }
        root.addSublayer(group)
        notesG = group
    }

    /// Клич «В бой!»: правая рука вверх, рот открыт, рука подрагивает; затем всё возвращается.
    func cheer() {
        guard !cheering, pose != .play else { return }
        cheering = true
        let up: CGFloat = outfit == .pajamas ? 168 : -192
        turnArm(armRG, from: armRAngle, to: up, duration: 0.3)
        let shake = additive("transform.rotation.z", [0, radians(5), 0, radians(-5), 0], duration: 0.18, times: [0, 0.25, 0.5, 0.75, 1])
        armRG.add(shake, forKey: "shout")
        mouthG.opacity = 1
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.armRG.removeAnimation(forKey: "shout")
                self.mouthG.opacity = 0
                self.cheering = false
                let target = self.armAngles(for: self.pose).right
                self.turnArm(self.armRG, from: up, to: target, duration: 0.4)
                self.armRAngle = target
            }
        }
    }

    /// Поклон: корпус сжимается по вертикали, голова опускается, затем распрямляется.
    func bow() {
        let squash = CAKeyframeAnimation(keyPath: "transform.scale.y")
        squash.values = [1, 0.83, 0.83, 1]
        squash.keyTimes = [0, 0.3, 0.7, 1]
        squash.duration = 1.2
        upperG.add(squash, forKey: "bow")
        let lower = CAKeyframeAnimation(keyPath: "transform.translation.y")
        lower.values = [0, -14 * ky, -14 * ky, 0]
        lower.keyTimes = [0, 0.3, 0.7, 1]
        lower.duration = 1.2
        headG.add(lower, forKey: "bow")
    }
}
