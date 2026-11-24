import AppKit
import QuartzCore
import SinMinionsCore

/// Находка призрака: маленькое окно с картинкой предмета рядом с призраком. Появляется с «хлопком» и тает.
@MainActor
final class FindPanel {
    static let side: CGFloat = 56

    private let panel: NSPanel
    private let host = NSView(frame: NSRect(x: 0, y: 0, width: side, height: side))
    private var generation = 0

    private typealias Palette = CompanionView.Palette

    init() {
        panel = NSPanel(contentRect: host.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        host.wantsLayer = true
        panel.contentView = host
        panel.alphaValue = 0
    }

    func setCollectionBehavior(_ behavior: NSWindow.CollectionBehavior) {
        panel.collectionBehavior = behavior
    }

    /// Показывает находку над призраком; `moth` и `area` — в координатах экрана.
    func show(_ find: SearchFind, beside moth: CGRect, in area: CGRect) {
        generation += 1
        host.layer?.sublayers?.forEach { $0.removeFromSuperlayer() }
        host.layer?.addSublayer(Self.art(for: find))
        // Предмет лежит у «ног» призрака, со стороны, где больше места.
        let side = Self.side
        let right = moth.maxX + side + 6 <= area.maxX
        let x = right ? moth.maxX + 4 : moth.minX - side - 4
        let origin = CGPoint(x: min(max(x, area.minX + 4), area.maxX - side - 4),
                             y: min(max(moth.minY, area.minY + 4), area.maxY - side - 4))
        panel.setFrameOrigin(origin)
        panel.orderFrontRegardless()
        panel.alphaValue = 1
        let pop = CAKeyframeAnimation(keyPath: "transform.scale")
        pop.values = [0.2, 1.25, 1]
        pop.keyTimes = [0, 0.6, 1]
        pop.duration = 0.4
        host.layer?.sublayers?.first?.add(pop, forKey: "pop")
    }

    func hide() {
        generation += 1
        guard panel.isVisible else { return }
        let expected = generation
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.5
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.generation == expected else { return }
                self.panel.orderOut(nil)
            }
        })
    }

    // MARK: - Картинки

    private static func shape(_ path: CGPath, fill: NSColor? = nil, stroke: NSColor? = nil, width: CGFloat = 1.5) -> CAShapeLayer {
        let layer = CAShapeLayer()
        layer.path = path
        layer.fillColor = fill?.cgColor
        layer.strokeColor = stroke?.cgColor
        layer.lineWidth = width
        layer.lineCap = .round
        layer.lineJoin = .round
        return layer
    }

    private static func art(for find: SearchFind) -> CALayer {
        let root = CALayer()
        root.frame = CGRect(x: 0, y: 0, width: side, height: side)
        let green = Palette.green
        let glow = CALayer()
        glow.frame = root.bounds
        if find.isMarketingFind {
            glow.shadowColor = Palette.vikchaText.cgColor
        } else {
            glow.shadowColor = (find.isRelic ? Palette.rgb(0xf0c24e) : green).cgColor
        }
        glow.shadowOpacity = 0.8
        glow.shadowRadius = 7
        glow.shadowOffset = .zero
        let dark = Palette.rgb(0x0b1a08)
        let mid = Palette.rgb(0x2f6a20)
        let water = Palette.rgb(0x4fc3ff)
        switch find {
        case .campaignBrief, .metricsChart, .megaphone, .hypothesisNote:
            drawMarketingFind(find, in: glow)
        case .waterChip:
            // Микросхема с выводами и каплей воды.
            let body = CGRect(x: 14, y: 14, width: 28, height: 28)
            for index in 0..<4 {
                let offset = 17 + CGFloat(index) * 6
                for edge in 0..<2 {
                    let p = CGMutablePath()
                    let x: CGFloat = edge == 0 ? 8 : 42
                    p.addRect(CGRect(x: x, y: offset, width: 6, height: 2.4))
                    glow.addSublayer(shape(p, fill: green))
                    let q = CGMutablePath()
                    let y: CGFloat = edge == 0 ? 8 : 42
                    q.addRect(CGRect(x: offset, y: y, width: 2.4, height: 6))
                    glow.addSublayer(shape(q, fill: green))
                }
            }
            glow.addSublayer(shape(CGPath(roundedRect: body, cornerWidth: 3, cornerHeight: 3, transform: nil),
                                   fill: dark, stroke: green, width: 1.6))
            let drop = CGMutablePath()
            drop.move(to: CGPoint(x: 28, y: 36))
            drop.addQuadCurve(to: CGPoint(x: 22, y: 25), control: CGPoint(x: 22.5, y: 31))
            drop.addArc(center: CGPoint(x: 28, y: 24.5), radius: 6, startAngle: .pi, endAngle: 0, clockwise: false)
            drop.addQuadCurve(to: CGPoint(x: 28, y: 36), control: CGPoint(x: 33.5, y: 31))
            glow.addSublayer(shape(drop, fill: water, stroke: Palette.rgb(0xeffff0), width: 1))
        case .holotape:
            let body = CGRect(x: 8, y: 16, width: 40, height: 26)
            glow.addSublayer(shape(CGPath(roundedRect: body, cornerWidth: 3, cornerHeight: 3, transform: nil),
                                   fill: dark, stroke: green, width: 1.6))
            for x in [19.0, 37.0] as [CGFloat] {
                glow.addSublayer(shape(CGPath(ellipseIn: CGRect(x: x - 5, y: 24, width: 10, height: 10), transform: nil),
                                       fill: mid, stroke: green, width: 1.2))
            }
            let label = CGMutablePath()
            label.addRect(CGRect(x: 14, y: 35, width: 28, height: 4))
            glow.addSublayer(shape(label, fill: green))
        case .bottleCap:
            let center = CGPoint(x: 28, y: 28)
            let crimp = CGMutablePath()
            for index in 0..<12 {
                let a0 = CGFloat(index) / 12 * 2 * .pi, a1 = (CGFloat(index) + 0.5) / 12 * 2 * .pi
                let p0 = CGPoint(x: center.x + 19 * cos(a0), y: center.y + 19 * sin(a0))
                let p1 = CGPoint(x: center.x + 16 * cos(a1), y: center.y + 16 * sin(a1))
                if index == 0 { crimp.move(to: p0) } else { crimp.addLine(to: p0) }
                crimp.addLine(to: p1)
            }
            crimp.closeSubpath()
            glow.addSublayer(shape(crimp, fill: Palette.rgb(0xe9b03a), stroke: dark, width: 1))
            glow.addSublayer(shape(CGPath(ellipseIn: CGRect(x: 18, y: 18, width: 20, height: 20), transform: nil),
                                   fill: Palette.rgb(0xf3c75c), stroke: dark, width: 1))
        case .stimpak:
            // Шприц под углом.
            let barrel = CGMutablePath()
            barrel.addRoundedRect(in: CGRect(x: 14, y: 22, width: 26, height: 10), cornerWidth: 2, cornerHeight: 2)
            var turn = CGAffineTransform(translationX: 28, y: 28).rotated(by: .pi / 5).translatedBy(x: -28, y: -28)
            let rotated = barrel.copy(using: &turn) ?? barrel
            glow.addSublayer(shape(rotated, fill: Palette.rgb(0xff6b6b), stroke: green, width: 1.4))
            let needle = CGMutablePath()
            needle.move(to: CGPoint(x: 40, y: 27))
            needle.addLine(to: CGPoint(x: 48, y: 33))
            var turn2 = CGAffineTransform(translationX: 28, y: 28).rotated(by: .pi / 5).translatedBy(x: -28, y: -28)
            glow.addSublayer(shape(needle.copy(using: &turn2) ?? needle, stroke: green, width: 1.6))

        case .aquila:
            // Золотой орёл с раскрытыми крыльями и багряным ромбом.
            let ink = Palette.rgb(0x241505), gold = Palette.rgb(0xe8b84a)
            let wing = CGMutablePath()
            wing.move(to: CGPoint(x: 28, y: 36))
            wing.addQuadCurve(to: CGPoint(x: 3, y: 38), control: CGPoint(x: 14, y: 50))
            wing.addQuadCurve(to: CGPoint(x: 13, y: 31), control: CGPoint(x: 9, y: 34))
            wing.addQuadCurve(to: CGPoint(x: 5, y: 24), control: CGPoint(x: 6, y: 29))
            wing.addQuadCurve(to: CGPoint(x: 21, y: 26), control: CGPoint(x: 12, y: 22))
            wing.addLine(to: CGPoint(x: 28, y: 22))
            wing.closeSubpath()
            var flipX = CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: 56, ty: 0)
            glow.addSublayer(shape(wing, fill: gold, stroke: ink, width: 1.6))
            glow.addSublayer(shape(wing.copy(using: &flipX) ?? wing, fill: gold, stroke: ink, width: 1.6))
            let diamond = CGMutablePath()
            diamond.move(to: CGPoint(x: 28, y: 42)); diamond.addLine(to: CGPoint(x: 34, y: 28))
            diamond.addLine(to: CGPoint(x: 28, y: 12)); diamond.addLine(to: CGPoint(x: 22, y: 28)); diamond.closeSubpath()
            glow.addSublayer(shape(diamond, fill: Palette.rgb(0xa62e22), stroke: ink, width: 1.6))
            glow.addSublayer(shape(CGPath(ellipseIn: CGRect(x: 25.5, y: 25.5, width: 5, height: 5), transform: nil),
                                   fill: Palette.rgb(0xffe7a0), stroke: ink, width: 1))
        case .purityScroll:
            // Пергамент с свёрнутыми краями, красной печатью и лентами.
            let ink = Palette.rgb(0x241505), parchment = Palette.rgb(0xefe3c8)
            glow.addSublayer(shape(CGPath(rect: CGRect(x: 14, y: 14, width: 28, height: 28), transform: nil),
                                   fill: parchment, stroke: ink, width: 1.4))
            for y in [42.0, 8.0] as [CGFloat] {
                glow.addSublayer(shape(CGPath(roundedRect: CGRect(x: 11, y: y - 3, width: 34, height: 6), cornerWidth: 3, cornerHeight: 3, transform: nil),
                                       fill: Palette.rgb(0xd9c9a3), stroke: ink, width: 1.2))
            }
            let lines = CGMutablePath()
            for y in [36.0, 31.0, 26.0] as [CGFloat] {
                lines.move(to: CGPoint(x: 18, y: y)); lines.addLine(to: CGPoint(x: 38, y: y))
            }
            glow.addSublayer(shape(lines, fill: nil, stroke: Palette.rgb(0x8a6b3a), width: 1))
            let ribbons = CGMutablePath()
            ribbons.move(to: CGPoint(x: 25, y: 18)); ribbons.addLine(to: CGPoint(x: 22, y: 9)); ribbons.addLine(to: CGPoint(x: 26, y: 11)); ribbons.closeSubpath()
            ribbons.move(to: CGPoint(x: 31, y: 18)); ribbons.addLine(to: CGPoint(x: 34, y: 9)); ribbons.addLine(to: CGPoint(x: 30, y: 11)); ribbons.closeSubpath()
            glow.addSublayer(shape(ribbons, fill: Palette.rgb(0xa62e22), stroke: ink, width: 1))
            glow.addSublayer(shape(CGPath(ellipseIn: CGRect(x: 23, y: 16, width: 10, height: 10), transform: nil),
                                   fill: Palette.rgb(0xa62e22), stroke: ink, width: 1.2))
            glow.addSublayer(shape(CGPath(ellipseIn: CGRect(x: 26, y: 19, width: 4, height: 4), transform: nil),
                                   fill: Palette.rgb(0xd4564a)))
        case .goldenSkull:
            // Золочёный череп с нимбом.
            let ink = Palette.rgb(0x241505), gold = Palette.rgb(0xf0c24e)
            let ring = CGPath(ellipseIn: CGRect(x: 16, y: 44, width: 24, height: 6), transform: nil)
            glow.addSublayer(shape(ring, fill: nil, stroke: Palette.rgb(0xffe7a0), width: 2))
            let skull = CGMutablePath()
            skull.addEllipse(in: CGRect(x: 14, y: 22, width: 28, height: 24))
            skull.addRoundedRect(in: CGRect(x: 20, y: 11, width: 16, height: 14), cornerWidth: 3, cornerHeight: 3)
            glow.addSublayer(shape(skull, fill: gold, stroke: ink, width: 1.6))
            for x in [22.0, 34.0] as [CGFloat] {
                glow.addSublayer(shape(CGPath(ellipseIn: CGRect(x: x - 4, y: 28, width: 8, height: 9), transform: nil), fill: ink))
            }
            let nose = CGMutablePath()
            nose.move(to: CGPoint(x: 28, y: 26)); nose.addLine(to: CGPoint(x: 25.5, y: 21)); nose.addLine(to: CGPoint(x: 30.5, y: 21)); nose.closeSubpath()
            glow.addSublayer(shape(nose, fill: ink))
            let teeth = CGMutablePath()
            for x in [23.0, 28.0, 33.0] as [CGFloat] { teeth.move(to: CGPoint(x: x, y: 11)); teeth.addLine(to: CGPoint(x: x, y: 18)) }
            glow.addSublayer(shape(teeth, fill: nil, stroke: ink, width: 1.2))
        case .chalice:
            // Золотая чаша с рубином.
            let ink = Palette.rgb(0x241505), gold = Palette.rgb(0xf0c24e)
            let cup = CGMutablePath()
            cup.move(to: CGPoint(x: 12, y: 44)); cup.addLine(to: CGPoint(x: 44, y: 44))
            cup.addQuadCurve(to: CGPoint(x: 28, y: 26), control: CGPoint(x: 44, y: 30))
            cup.addQuadCurve(to: CGPoint(x: 12, y: 44), control: CGPoint(x: 12, y: 30))
            cup.closeSubpath()
            glow.addSublayer(shape(cup, fill: gold, stroke: ink, width: 1.6))
            glow.addSublayer(shape(CGPath(rect: CGRect(x: 25, y: 14, width: 6, height: 13), transform: nil), fill: gold, stroke: ink, width: 1.4))
            glow.addSublayer(shape(CGPath(roundedRect: CGRect(x: 16, y: 8, width: 24, height: 7), cornerWidth: 3, cornerHeight: 3, transform: nil),
                                   fill: gold, stroke: ink, width: 1.4))
            glow.addSublayer(shape(CGPath(ellipseIn: CGRect(x: 24, y: 33, width: 8, height: 8), transform: nil),
                                   fill: Palette.rgb(0xc0262c), stroke: ink, width: 1.2))
            glow.addSublayer(shape(CGPath(ellipseIn: CGRect(x: 25.5, y: 37, width: 2.4, height: 2.4), transform: nil), fill: Palette.rgb(0xffd0d0)))
        }
        root.addSublayer(glow)
        return root
    }

    private static func drawMarketingFind(_ find: SearchFind, in layer: CALayer) {
        let ink = Palette.rgb(0x32204f)
        let paper = Palette.rgb(0xffeaf5)
        let pink = Palette.rgb(0xf788b9)
        let purple = Palette.rgb(0x9c66d0)
        let gold = Palette.rgb(0xffda83)

        func rectangle(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, color: NSColor, radius: CGFloat = 2) {
            let path = CGPath(roundedRect: CGRect(x: x, y: y, width: w, height: h),
                              cornerWidth: radius, cornerHeight: radius, transform: nil)
            layer.addSublayer(shape(path, fill: color, stroke: ink, width: 1.2))
        }

        func line(_ points: [CGPoint], stroke: NSColor, width: CGFloat = 1.6, fill: NSColor? = nil) {
            guard let first = points.first else { return }
            let path = CGMutablePath()
            path.move(to: first)
            for point in points.dropFirst() { path.addLine(to: point) }
            if fill != nil { path.closeSubpath() }
            layer.addSublayer(shape(path, fill: fill, stroke: stroke, width: width))
        }

        switch find {
        case .campaignBrief:
            rectangle(12, 7, 32, 40, color: purple, radius: 4)
            rectangle(16, 11, 24, 33, color: paper)
            rectangle(21, 41, 14, 8, color: gold)
            for y in [19, 27, 35] as [CGFloat] {
                line([CGPoint(x: 21, y: y), CGPoint(x: 23, y: y - 2), CGPoint(x: 26, y: y + 2)], stroke: purple)
                line([CGPoint(x: 29, y: y), CGPoint(x: 35, y: y)], stroke: ink, width: 1)
            }
        case .metricsChart:
            rectangle(8, 12, 40, 31, color: paper, radius: 4)
            line([CGPoint(x: 15, y: 36), CGPoint(x: 15, y: 18), CGPoint(x: 42, y: 18)], stroke: ink)
            rectangle(19, 18, 5, 7, color: pink, radius: 1)
            rectangle(27, 18, 5, 12, color: purple, radius: 1)
            rectangle(35, 18, 5, 17, color: gold, radius: 1)
        case .megaphone:
            rectangle(15, 13, 8, 14, color: purple)
            rectangle(9, 23, 13, 11, color: paper)
            line([CGPoint(x: 20, y: 24), CGPoint(x: 41, y: 14), CGPoint(x: 41, y: 43),
                  CGPoint(x: 20, y: 33)], stroke: ink, fill: pink)
            line([CGPoint(x: 39, y: 15), CGPoint(x: 39, y: 42)], stroke: purple, width: 2)
            line([CGPoint(x: 45, y: 30), CGPoint(x: 51, y: 32)], stroke: gold, width: 2)
            line([CGPoint(x: 44, y: 37), CGPoint(x: 48, y: 41)], stroke: gold, width: 2)
        case .hypothesisNote:
            line([CGPoint(x: 12, y: 12), CGPoint(x: 35, y: 12), CGPoint(x: 44, y: 21),
                  CGPoint(x: 44, y: 45), CGPoint(x: 12, y: 45)], stroke: ink, fill: gold)
            line([CGPoint(x: 35, y: 12), CGPoint(x: 35, y: 21), CGPoint(x: 44, y: 21)], stroke: ink, fill: paper)
            rectangle(21, 42, 14, 6, color: pink, radius: 1)
            let bulb = CGPath(ellipseIn: CGRect(x: 22, y: 25, width: 12, height: 12), transform: nil)
            layer.addSublayer(shape(bulb, fill: paper, stroke: ink, width: 1.3))
            line([CGPoint(x: 25, y: 22), CGPoint(x: 31, y: 22)], stroke: purple, width: 2)
            line([CGPoint(x: 26, y: 19), CGPoint(x: 30, y: 19)], stroke: purple)
        default:
            break
        }
    }
}
