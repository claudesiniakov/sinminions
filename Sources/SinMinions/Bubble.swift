import AppKit
import SinMinionsCore

/// Пузырь с репликой: белый, скругление 12, шрифт 12, ширина до 160 — как в аналоге.
@MainActor
final class BubbleView: NSView {
    static let maxWidth: CGFloat = 160
    static let padH: CGFloat = 12
    static let padV: CGFloat = 8
    static let tail: CGFloat = 7
    static let radius: CGFloat = 12

    private static let fill = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(white: 0.17, alpha: 1) : .white
    }
    private static let stroke = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(white: 0.32, alpha: 1) : NSColor(white: 0.88, alpha: 1)
    }
    private static let ink = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(white: 0.86, alpha: 1) : NSColor(white: 0.33, alpha: 1)
    }

    var text = ""
    var below = false
    var tailX: CGFloat = 0

    private static func attributed(_ text: String) -> NSAttributedString {
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        style.lineBreakMode = .byWordWrapping
        return NSAttributedString(string: text, attributes: [
            .font: NSFont.systemFont(ofSize: 12),
            .foregroundColor: ink,
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

        let rounded = NSBezierPath(roundedRect: box, xRadius: Self.radius, yRadius: Self.radius)
        Self.fill.setFill()
        rounded.fill()
        Self.stroke.setStroke()
        rounded.lineWidth = 1
        rounded.stroke()

        let x = min(max(tailX, Self.radius + Self.tail), bounds.width - Self.radius - Self.tail)
        let baseY = below ? box.maxY : box.minY
        let tipY = below ? box.maxY + Self.tail : box.minY - Self.tail
        let overlap: CGFloat = below ? -1 : 1
        let triangle = NSBezierPath()
        triangle.move(to: CGPoint(x: x - Self.tail, y: baseY + overlap))
        triangle.line(to: CGPoint(x: x, y: tipY))
        triangle.line(to: CGPoint(x: x + Self.tail, y: baseY + overlap))
        triangle.close()
        Self.fill.setFill()
        triangle.fill()
        let edges = NSBezierPath()
        edges.move(to: CGPoint(x: x - Self.tail, y: baseY))
        edges.line(to: CGPoint(x: x, y: tipY))
        edges.line(to: CGPoint(x: x + Self.tail, y: baseY))
        edges.lineWidth = 1
        Self.stroke.setStroke()
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
