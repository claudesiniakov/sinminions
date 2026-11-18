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
        glow.shadowColor = green.cgColor
        glow.shadowOpacity = 0.8
        glow.shadowRadius = 7
        glow.shadowOffset = .zero
        let dark = Palette.rgb(0x0b1a08)
        let mid = Palette.rgb(0x2f6a20)
        let water = Palette.rgb(0x4fc3ff)
        switch find {
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
        }
        root.addSublayer(glow)
        return root
    }
}
