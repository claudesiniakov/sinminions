import AppKit
import QuartzCore

/// Телевизор рядом с золотым стражем, пока тот играет на приставке: на экране бежит Moth и перепрыгивает препятствия.
@MainActor
final class TVPanel {
    private let panel: NSPanel
    private let host = NSView(frame: .zero)
    private let unit: CGFloat
    private let size: CGSize
    private var generation = 0

    private typealias Palette = CompanionView.Palette

    /// Размеры рисунка телевизора в условных единицах.
    private static let designWidth: CGFloat = 104
    private static let designHeight: CGFloat = 92

    init(scale: CGFloat) {
        unit = max(0.5, 0.55 * scale)
        size = CGSize(width: Self.designWidth * unit, height: Self.designHeight * unit)
        host.frame = CGRect(origin: .zero, size: size)
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
        build()
    }

    func setCollectionBehavior(_ behavior: NSWindow.CollectionBehavior) {
        panel.collectionBehavior = behavior
    }

    /// Показывает телевизор у ног персонажа, со стороны, где больше места; `moth` и `area` — в координатах экрана.
    func show(beside moth: CGRect, in area: CGRect) {
        generation += 1
        let right = moth.maxX + size.width + 8 <= area.maxX
        let x = right ? moth.maxX + 6 : moth.minX - size.width - 6
        let origin = CGPoint(x: min(max(x, area.minX + 2), area.maxX - size.width - 2),
                             y: min(max(moth.minY - 2, area.minY + 2), area.maxY - size.height - 2))
        panel.setFrameOrigin(origin)
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.35
            panel.animator().alphaValue = 1
        }
    }

    func hide() {
        generation += 1
        guard panel.isVisible else { return }
        let expected = generation
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.4
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.generation == expected else { return }
                self.panel.orderOut(nil)
            }
        })
    }

    // MARK: - Рисунок

    /// Точка рисунка (ось y вниз) в координаты слоя.
    private func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
        CGPoint(x: x * unit, y: size.height - y * unit)
    }

    private func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect {
        CGRect(x: x * unit, y: size.height - (y + h) * unit, width: w * unit, height: h * unit)
    }

    private func shape(_ path: CGPath, fill: NSColor?, stroke: NSColor? = nil, width: CGFloat = 0) -> CAShapeLayer {
        let layer = CAShapeLayer()
        layer.frame = host.bounds
        layer.path = path
        layer.fillColor = fill?.cgColor
        layer.strokeColor = stroke?.cgColor
        layer.lineWidth = width * unit
        layer.lineJoin = .round
        return layer
    }

    private func build() {
        guard let root = host.layer else { return }
        let outline = Palette.rgb(0x1c1206)
        let green = Palette.green

        // Свечение экрана.
        let glow = CAGradientLayer()
        glow.type = .radial
        glow.frame = host.bounds.insetBy(dx: -12 * unit, dy: -12 * unit)
        glow.colors = [green.withAlphaComponent(0.32).cgColor, green.withAlphaComponent(0).cgColor]
        glow.startPoint = CGPoint(x: 0.5, y: 0.5)
        glow.endPoint = CGPoint(x: 1, y: 1)
        let pulse = CABasicAnimation(keyPath: "opacity")
        pulse.fromValue = 0.65
        pulse.toValue = 1
        pulse.duration = 0.6
        pulse.autoreverses = true
        pulse.repeatCount = .infinity
        glow.add(pulse, forKey: "pulse")
        root.addSublayer(glow)

        // Подставка и корпус.
        let stand = CGMutablePath()
        stand.move(to: point(34, 76)); stand.addLine(to: point(26, 90)); stand.addLine(to: point(78, 90)); stand.addLine(to: point(70, 76))
        stand.closeSubpath()
        root.addSublayer(shape(stand, fill: Palette.rgb(0x2c271f), stroke: outline, width: 2.5))
        let bezel = CGPath(roundedRect: rect(0, 0, 104, 76), cornerWidth: 8 * unit, cornerHeight: 8 * unit, transform: nil)
        root.addSublayer(shape(bezel, fill: Palette.rgb(0x3a342a), stroke: outline, width: 3))

        // Экран с игрой: за границы экрана ничего не выходит.
        let screenRect = rect(8, 8, 88, 54)
        let screen = CALayer()
        screen.frame = screenRect
        screen.backgroundColor = Palette.rgb(0x07210d).cgColor
        screen.cornerRadius = 5 * unit
        screen.masksToBounds = true
        root.addSublayer(screen)

        let groundY = 12 * unit
        let ground = CALayer()
        ground.frame = CGRect(x: 0, y: groundY, width: screenRect.width, height: 1.4 * unit)
        ground.backgroundColor = Palette.rgb(0x2f7a22).cgColor
        screen.addSublayer(ground)

        // Препятствия едут справа налево по кругу.
        let obstacles = CALayer()
        obstacles.frame = CGRect(x: 0, y: 0, width: screenRect.width, height: screenRect.height)
        for (x, h) in [(92, 11), (140, 7), (188, 11), (236, 7), (284, 11), (332, 7)] as [(CGFloat, CGFloat)] {
            let block = CALayer()
            block.frame = CGRect(x: x * unit, y: groundY + 1.4 * unit, width: 5 * unit, height: h * unit)
            block.backgroundColor = Palette.rgb(0x3a9e28).cgColor
            obstacles.addSublayer(block)
        }
        let scroll = CABasicAnimation(keyPath: "transform.translation.x")
        scroll.fromValue = 0
        scroll.toValue = -96 * unit
        scroll.duration = 2.4
        scroll.repeatCount = .infinity
        obstacles.add(scroll, forKey: "scroll")
        screen.addSublayer(obstacles)

        // Moth на экране прыгает.
        let ghost = CAShapeLayer()
        let g = CGMutablePath()
        g.move(to: CGPoint(x: 0, y: 0))
        g.addLine(to: CGPoint(x: 0, y: 8 * unit))
        g.addQuadCurve(to: CGPoint(x: 6 * unit, y: 14 * unit), control: CGPoint(x: 0, y: 14 * unit))
        g.addQuadCurve(to: CGPoint(x: 12 * unit, y: 8 * unit), control: CGPoint(x: 12 * unit, y: 14 * unit))
        g.addLine(to: CGPoint(x: 12 * unit, y: 0))
        g.addLine(to: CGPoint(x: 9 * unit, y: 3 * unit))
        g.addLine(to: CGPoint(x: 6 * unit, y: 0))
        g.addLine(to: CGPoint(x: 3 * unit, y: 3 * unit))
        g.closeSubpath()
        ghost.path = g
        ghost.fillColor = Palette.green.cgColor
        ghost.frame = CGRect(x: 22 * unit, y: groundY + 1.4 * unit, width: 12 * unit, height: 14 * unit)
        ghost.bounds = CGRect(x: 0, y: 0, width: 12 * unit, height: 14 * unit)
        ghost.position = CGPoint(x: 28 * unit, y: groundY + 1.4 * unit + 7 * unit)
        for dx in [4.0, 8.4] {
            let eye = CAShapeLayer()
            eye.path = CGPath(ellipseIn: CGRect(x: (dx - 1.2) * unit, y: 7 * unit, width: 2.4 * unit, height: 2.4 * unit), transform: nil)
            eye.fillColor = Palette.rgb(0x07210d).cgColor
            ghost.addSublayer(eye)
        }
        let jump = CAKeyframeAnimation(keyPath: "transform.translation.y")
        jump.values = [0, 24 * unit, 0, 0, 0]
        jump.keyTimes = [0, 0.14, 0.28, 0.6, 1]
        jump.duration = 1.2
        jump.repeatCount = .infinity
        ghost.add(jump, forKey: "jump")
        screen.addSublayer(ghost)

        // Счёт в углу.
        let score = CATextLayer()
        score.string = "0042"
        score.font = NSFont.monospacedSystemFont(ofSize: 10, weight: .regular)
        score.fontSize = max(6, 7 * unit)
        score.foregroundColor = Palette.green.cgColor
        score.contentsScale = NSScreen.main?.backingScaleFactor ?? 2
        score.frame = CGRect(x: 4 * unit, y: screenRect.height - 12 * unit, width: 40 * unit, height: 10 * unit)
        screen.addSublayer(score)

        // Блик на стекле и светодиод.
        let shine = CAGradientLayer()
        shine.frame = screenRect
        shine.cornerRadius = 5 * unit
        shine.colors = [NSColor.white.withAlphaComponent(0.28).cgColor, NSColor.white.withAlphaComponent(0).cgColor]
        shine.startPoint = CGPoint(x: 0, y: 1)
        shine.endPoint = CGPoint(x: 0.6, y: 0.4)
        root.addSublayer(shine)
        root.addSublayer(shape(CGPath(ellipseIn: CGRect(x: 90.4 * unit, y: size.height - 70.6 * unit, width: 3.2 * unit, height: 3.2 * unit), transform: nil),
                               fill: Palette.green))
    }
}
