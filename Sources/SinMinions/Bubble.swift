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
    var character: CompanionCharacter = .f
    var below = false
    var tailX: CGFloat = 0

    private static func colors(for character: CompanionCharacter) -> (
        text: NSColor, glow: NSColor, panel: NSColor, border: NSColor
    ) {
        switch character {
        case .f:
            return (Palette.greenDim, Palette.green, Palette.panel, Palette.greenDark)
        case .ab:
            let gold = Palette.rgb(0xf0d58c)
            return (gold, gold, Palette.rgb(0x0e0808), Palette.rgb(0x7a2222))
        case .v:
            return (Palette.vikchaText, Palette.vikchaText, Palette.vikchaPanel, Palette.vikchaBorder)
        }
    }

    private static func attributed(_ text: String, character: CompanionCharacter = .f) -> NSAttributedString {
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        style.lineBreakMode = .byWordWrapping
        style.lineHeightMultiple = 1.15
        let colors = colors(for: character)
        let glow = NSShadow()
        glow.shadowColor = colors.glow.withAlphaComponent(0.55)
        glow.shadowBlurRadius = 6
        glow.shadowOffset = .zero
        return NSAttributedString(string: text, attributes: [
            .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular),
            .foregroundColor: colors.text,
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

    /// Высота текста по правилам отрисовки: тот же TextKit, что и в `draw`.
    /// `boundingRect` для многострочного текста с `lineHeightMultiple` занижает высоту,
    /// и последняя строка уезжала под нижнюю границу пузыря.
    static func layoutHeight(_ text: String, width: CGFloat) -> CGFloat {
        let storage = NSTextStorage(attributedString: attributed(text))
        let manager = NSLayoutManager()
        let container = NSTextContainer(size: CGSize(width: width, height: .greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        manager.addTextContainer(container)
        storage.addLayoutManager(manager)
        manager.ensureLayout(for: container)
        return ceil(manager.usedRect(for: container).height)
    }

    /// Ширина текста, на которой он будет нарисован при данном размере окна.
    static func textWidth(forPanelWidth width: CGFloat) -> CGFloat {
        max(width - 2 - padH * 2, 1)
    }

    /// Размер окна пузыря вместе с хвостиком. Высота считается раскладкой на той же ширине,
    /// на которой текст рисуется, плюс небольшой запас — тогда последняя строка не режется.
    static func size(for text: String) -> CGSize {
        let widest = maxWidth - padH * 2
        var textWidth = min(max(textSize(text).width, 44), widest)
        var height = layoutHeight(text, width: textWidth)
        // На узкой ширине текст может занять больше строк, чем на максимальной: берём лучший вариант.
        if textWidth < widest {
            let atWidest = layoutHeight(text, width: widest)
            if atWidest <= height {
                textWidth = widest
                height = atWidest
            }
        }
        return CGSize(width: textWidth + padH * 2 + 2, height: height + padV * 2 + tail + 2 + 6)
    }

    override func draw(_ dirtyRect: NSRect) {
        let inset = bounds.insetBy(dx: 1, dy: 1)
        // Координаты AppKit: хвостик снизу, когда пузырь над персонажем.
        let box = below
            ? CGRect(x: inset.minX, y: inset.minY, width: inset.width, height: inset.height - Self.tail)
            : CGRect(x: inset.minX, y: inset.minY + Self.tail, width: inset.width, height: inset.height - Self.tail)

        let frame = NSBezierPath(rect: box)
        let colors = Self.colors(for: character)
        colors.panel.setFill()
        frame.fill()
        colors.border.setStroke()
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
        colors.panel.setFill()
        triangle.fill()
        let edges = NSBezierPath()
        edges.move(to: CGPoint(x: x - Self.tail, y: baseY))
        edges.line(to: CGPoint(x: x, y: tipY))
        edges.line(to: CGPoint(x: x + Self.tail, y: baseY))
        edges.lineWidth = 1
        colors.border.setStroke()
        edges.stroke()

        let width = Self.textWidth(forPanelWidth: bounds.width)
        let height = Self.layoutHeight(text, width: width)
        let textRect = CGRect(x: box.minX + Self.padH, y: box.midY - height / 2, width: width, height: height)
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

    /// Реплика уже на экране. Во время затухания пузырь не двигаем.
    var isVisible: Bool { panel.isVisible && panel.alphaValue > 0.02 }

    /// Двигает видимую реплику за персонажем: он шагает, а текст остаётся у его головы.
    /// Размер не пересчитываем — текст не менялся.
    func follow(over moth: CGRect, in area: CGRect) {
        guard isVisible else { return }
        let size = panel.frame.size
        let placement = Layout.bubble(size: size, over: moth, in: area)
        guard placement.origin != panel.frame.origin
                || placement.below != view.below
                || placement.tailX != view.tailX else { return }
        view.below = placement.below
        view.tailX = placement.tailX
        panel.setFrame(CGRect(origin: placement.origin, size: size), display: false)
        view.needsDisplay = true
    }
}
