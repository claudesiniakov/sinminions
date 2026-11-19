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
    /// У золотого стража пузырь золотой с багряной рамкой, у призрака зелёный.
    var character: CompanionCharacter = .f
    var below = false
    var tailX: CGFloat = 0

    private static func attributed(_ text: String, character: CompanionCharacter = .f) -> NSAttributedString {
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        style.lineBreakMode = .byWordWrapping
        style.lineHeightMultiple = 1.15
        let glow = NSShadow()
        glow.shadowColor = (character == .ab ? Palette.rgb(0xf0d58c) : Palette.green).withAlphaComponent(0.55)
        glow.shadowBlurRadius = 6
        glow.shadowOffset = .zero
        return NSAttributedString(string: text, attributes: [
            .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular),
            .foregroundColor: character == .ab ? Palette.rgb(0xf0d58c) : Palette.greenDim,
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
        // Запас по высоте: при межстрочном множителе замер многострочного текста бывает короче отрисовки.
        let extra = ceil(box.height / 15) > 2 ? 4 : 0
        return CGSize(width: ceil(box.width), height: ceil(box.height) + CGFloat(extra))
    }

    /// Размер окна пузыря вместе с хвостиком.
    static func size(for text: String) -> CGSize {
        let t = textSize(text)
        // Запас по ширине, чтобы при рисовании строки переносились так же, как при замере.
        return CGSize(width: max(t.width + padH * 2, 44) + 6, height: t.height + padV * 2 + tail + 2)
    }

    override func draw(_ dirtyRect: NSRect) {
        let inset = bounds.insetBy(dx: 1, dy: 1)
        // Координаты AppKit: хвостик снизу, когда пузырь над персонажем.
        let box = below
            ? CGRect(x: inset.minX, y: inset.minY, width: inset.width, height: inset.height - Self.tail)
            : CGRect(x: inset.minX, y: inset.minY + Self.tail, width: inset.width, height: inset.height - Self.tail)

        let frame = NSBezierPath(rect: box)
        let panelColor = character == .ab ? Palette.rgb(0x0e0808) : Palette.panel
        let edgeColor = character == .ab ? Palette.rgb(0x7a2222) : Palette.greenDark
        panelColor.setFill()
        frame.fill()
        edgeColor.setStroke()
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
        panelColor.setFill()
        triangle.fill()
        let edges = NSBezierPath()
        edges.move(to: CGPoint(x: x - Self.tail, y: baseY))
        edges.line(to: CGPoint(x: x, y: tipY))
        edges.line(to: CGPoint(x: x + Self.tail, y: baseY))
        edges.lineWidth = 1
        edgeColor.setStroke()
        edges.stroke()

        let t = Self.textSize(text)
        let textRect = CGRect(
            x: box.minX + Self.padH, y: box.midY - t.height / 2,
            width: box.width - Self.padH * 2, height: t.height
        )
        Self.attributed(text, character: character).draw(with: textRect, options: [.usesLineFragmentOrigin, .usesFontLeading])
    }
}

/// Окно пузыря: не принимает мышь и не забирает фокус.
@MainActor
final class BubblePanel {
    private let panel: NSPanel
    private let view = BubbleView()

    var character: CompanionCharacter = .f {
        didSet {
            view.character = character
            view.needsDisplay = true
        }
    }
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
