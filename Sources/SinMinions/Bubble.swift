import AppKit
import SinMinionsCore

/// Пузырь с репликой в стиле терминала из claudesiniakov/summary: тёмная плашка без скруглений,
/// зелёный моноширинный текст 11 pt со свечением, ширина до 170.
@MainActor
final class BubbleView: NSView {
    static let maxWidth: CGFloat = 170
    static let padH: CGFloat = 12
    static let padV: CGFloat = 7
    static let tail: CGFloat = 7

    private typealias Palette = CompanionView.Palette

    var text = ""
    var below = false
    var tailX: CGFloat = 0

    private static func attributed(_ text: String) -> NSAttributedString {
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        style.lineBreakMode = .byWordWrapping
        style.lineHeightMultiple = 1.15
        let glow = NSShadow()
        glow.shadowColor = Palette.green.withAlphaComponent(0.55)
        glow.shadowBlurRadius = 6
        glow.shadowOffset = .zero
        return NSAttributedString(string: text, attributes: [
            .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular),
            .foregroundColor: Palette.greenDim,
            .kern: 0.5,
            .shadow: glow,
            .paragraphStyle: style,
        ])
    }

    private static func textSize(_ text: String) -> CGSize {
        let box = attributed(text).boundingRect(
            with: CGSize(width: maxWidth - padH * 2, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        )
        return CGSize(width: ceil(box.width), height: ceil(box.height))
    }

    /// Размер окна пузыря вместе с хвостиком.
    static func size(for text: String) -> CGSize {
        let t = textSize(text)
        return CGSize(width: max(t.width + padH * 2, 44) + 2, height: t.height + padV * 2 + tail + 2)
    }

    override func draw(_ dirtyRect: NSRect) {
        let inset = bounds.insetBy(dx: 1, dy: 1)
        // Координаты AppKit: хвостик снизу, когда пузырь над персонажем.
        let box = below
            ? CGRect(x: inset.minX, y: inset.minY, width: inset.width, height: inset.height - Self.tail)
            : CGRect(x: inset.minX, y: inset.minY + Self.tail, width: inset.width, height: inset.height - Self.tail)

        let frame = NSBezierPath(rect: box)
        Palette.panel.setFill()
        frame.fill()
        Palette.greenDark.setStroke()
        frame.lineWidth = 1
        frame.stroke()

        let x = min(max(tailX, Self.tail + 2), bounds.width - Self.tail - 2)
        let baseY = below ? box.maxY : box.minY
        let tipY = below ? box.maxY + Self.tail : box.minY - Self.tail
        let overlap: CGFloat = below ? -1 : 1
        let triangle = NSBezierPath()
        triangle.move(to: CGPoint(x: x - Self.tail, y: baseY + overlap))
        triangle.line(to: CGPoint(x: x, y: tipY))
        triangle.line(to: CGPoint(x: x + Self.tail, y: baseY + overlap))
        triangle.close()
        Palette.panel.setFill()
        triangle.fill()
        let edges = NSBezierPath()
        edges.move(to: CGPoint(x: x - Self.tail, y: baseY))
        edges.line(to: CGPoint(x: x, y: tipY))
        edges.line(to: CGPoint(x: x + Self.tail, y: baseY))
        edges.lineWidth = 1
        Palette.greenDark.setStroke()
        edges.stroke()

        let t = Self.textSize(text)
        let textRect = CGRect(
            x: box.minX + Self.padH, y: box.midY - t.height / 2,
            width: box.width - Self.padH * 2, height: t.height
        )
        Self.attributed(text).draw(with: textRect, options: [.usesLineFragmentOrigin, .usesFontLeading])
    }
}

/// Окно пузыря: не принимает мышь и не забирает фокус.
@MainActor
final class BubblePanel {
    private let panel: NSPanel
    private let view = BubbleView()
    private var generation = 0

    init() {
        panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.contentView = view
        panel.alphaValue = 0
    }

    func setCollectionBehavior(_ behavior: NSWindow.CollectionBehavior) {
        panel.collectionBehavior = behavior
    }

    /// Показывает реплику рядом с персонажем; `moth` и `area` — в координатах экрана.
    func show(_ text: String, over moth: CGRect, in area: CGRect) {
        generation += 1
        let size = BubbleView.size(for: text)
        let placement = Layout.bubble(size: size, over: moth, in: area)
        view.text = text
        view.below = placement.below
        view.tailX = placement.tailX
        panel.setFrame(CGRect(origin: placement.origin, size: size), display: true)
        view.needsDisplay = true
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.4
            panel.animator().alphaValue = 1
        }
    }

    func hide(animated: Bool = true) {
        generation += 1
        guard panel.isVisible else { return }
        guard animated else {
            panel.alphaValue = 0
            panel.orderOut(nil)
            return
        }
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
}
