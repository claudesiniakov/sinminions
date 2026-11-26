import AppKit
import SinMinionsCore

/// Пузырь с репликой в стиле терминала из claudesiniakov/summary: тёмная плашка без скруглений,
/// моноширинный текст со свечением, ширина до 170.
///
/// Раскладка и отрисовка идут одним движком (TextKit): размер панели считается по той же
/// `NSTextContainer`, которой потом рисуются глифы, поэтому последняя строка не может
/// оказаться под нижней границей. Раньше замер (`boundingRect`) и отрисовка расходились,
/// и на длинных репликах текст уезжал вниз и обрезался.
@MainActor
final class BubbleView: NSView {
    static let maxWidth: CGFloat = 170
    static let padH: CGFloat = 12
    static let padV: CGFloat = 7
    static let tail: CGFloat = 7
    static let fontSize: CGFloat = 11
    static let minFontSize: CGFloat = 9

    private typealias Palette = CompanionView.Palette

    /// Готовая раскладка реплики: возможно укороченный текст, кегль и посчитанные размеры.
    struct Fit {
        let text: String
        let fontSize: CGFloat
        let textWidth: CGFloat
        let textHeight: CGFloat

        var panelSize: CGSize {
            CGSize(
                width: textWidth + BubbleView.padH * 2 + 2,
                height: textHeight + BubbleView.padV * 2 + BubbleView.tail + 2
            )
        }
    }

    var character: CompanionCharacter = .f
    var below = false
    var tailX: CGFloat = 0
    private(set) var fit = Fit(text: "", fontSize: fontSize, textWidth: 1, textHeight: 1)

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

    private static func attributed(
        _ text: String, character: CompanionCharacter, fontSize: CGFloat
    ) -> NSAttributedString {
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
            .font: NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular),
            .foregroundColor: colors.text,
            .kern: 0.5,
            .shadow: glow,
            .paragraphStyle: style,
        ])
    }

    /// Раскладка ровно на той ширине, на которой текст будет нарисован.
    private static func layout(
        _ text: String, width: CGFloat, character: CompanionCharacter, fontSize: CGFloat
    ) -> (storage: NSTextStorage, manager: NSLayoutManager, height: CGFloat) {
        let storage = NSTextStorage(attributedString: attributed(text, character: character, fontSize: fontSize))
        let manager = NSLayoutManager()
        let container = NSTextContainer(size: CGSize(width: width, height: .greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        manager.addTextContainer(container)
        storage.addLayoutManager(manager)
        manager.ensureLayout(for: container)
        return (storage, manager, ceil(manager.usedRect(for: container).height))
    }

    /// Ширина самой длинной строки при данном кегле: от неё зависит ширина плашки.
    private static func inkWidth(_ text: String, character: CompanionCharacter, fontSize: CGFloat) -> CGFloat {
        let widest = maxWidth - padH * 2
        let box = attributed(text, character: character, fontSize: fontSize).boundingRect(
            with: CGSize(width: widest, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        )
        return min(ceil(box.width), widest)
    }

    /// Подбор размера: сначала обычный кегль, при нехватке места — мельче, затем текст укорачивается.
    static func fit(_ text: String, character: CompanionCharacter, maxHeight: CGFloat) -> Fit {
        let widest = maxWidth - padH * 2
        var fontSize = Self.fontSize
        var body = text
        // Узкая плашка — для короткой реплики. Если на узкой ширине текст занимает больше строк,
        // берём максимальную: так длинные реплики не становятся выше без нужды.
        var width = max(inkWidth(text, character: character, fontSize: fontSize), 44)
        func height() -> CGFloat {
            layout(body, width: width, character: character, fontSize: fontSize).height
        }
        func chrome() -> CGFloat { padV * 2 + tail + 2 }
        var h = height()
        if width < widest {
            let atWidest = layout(body, width: widest, character: character, fontSize: fontSize).height
            // Шире берём только если это уменьшает высоту: короткой реплике узкая плашка лучше.
            if atWidest < h {
                width = widest
                h = atWidest
            }
        }
        while h + chrome() > maxHeight, fontSize > Self.minFontSize {
            fontSize -= 1
            h = height()
        }
        if h + chrome() > maxHeight {
            var words = body.split(separator: " ")
            while words.count > 1, h + chrome() > maxHeight {
                words.removeLast()
                body = words.joined(separator: " ") + "…"
                h = height()
            }
        }
        return Fit(text: body, fontSize: fontSize, textWidth: width, textHeight: h)
    }

    func apply(_ fit: Fit) {
        self.fit = fit
        needsDisplay = true
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

        guard !fit.text.isEmpty else { return }
        let laid = Self.layout(fit.text, width: fit.textWidth, character: character, fontSize: fit.fontSize)
        // TextKit рисует сверху вниз в перевёрнутой системе координат: переворачиваем сами,
        // тогда верх текста ровно там, где мы его посчитали.
        let top = box.midY + laid.height / 2
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.saveGState()
        ctx.textMatrix = .identity
        ctx.translateBy(x: box.minX + Self.padH, y: top)
        ctx.scaleBy(x: 1, y: -1)
        laid.manager.drawGlyphs(
            forGlyphRange: NSRange(location: 0, length: laid.storage.length), at: .zero
        )
        ctx.restoreGState()
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
        // Запас по высоте экрана: длинная реплика сначала уменьшается в кегле, потом укорачивается.
        let fit = BubbleView.fit(text, character: character, maxHeight: max(area.height - 48, 120))
        let placement = Layout.bubble(size: fit.panelSize, over: moth, in: area)
        view.character = character
        view.apply(fit)
        view.below = placement.below
        view.tailX = placement.tailX
        panel.setFrame(CGRect(origin: placement.origin, size: fit.panelSize), display: true)
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
