import AppKit
import QuartzCore

/// Портал: светящийся овал-«пятно» на экране. Открывается и закрывается плавно, не принимает мышь.
@MainActor
final class PortalWindow {
    static let blue = NSColor(srgbRed: 0.18, green: 0.61, blue: 1, alpha: 1)
    static let orange = NSColor(srgbRed: 1, green: 0.6, blue: 0.12, alpha: 1)
    /// Поля вокруг овала под свечение.
    private static let margin: CGFloat = 22

    private let panel: NSPanel
    private let holder = CALayer()
    private let fill = CAShapeLayer()
    private let ring = CAShapeLayer()
    private var generation = 0

    init(color: NSColor) {
        panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false

        let content = NSView()
        content.wantsLayer = true
        content.layer?.addSublayer(holder)
        holder.addSublayer(fill)
        holder.addSublayer(ring)
        holder.opacity = 0
        fill.fillColor = color.withAlphaComponent(0.16).cgColor
        ring.fillColor = nil
        ring.strokeColor = color.cgColor
        ring.lineWidth = 3
        ring.shadowColor = color.cgColor
        ring.shadowOffset = .zero
        ring.shadowRadius = 9
        ring.shadowOpacity = 0.95
        panel.contentView = content
    }

    func setCollectionBehavior(_ behavior: NSWindow.CollectionBehavior) {
        panel.collectionBehavior = behavior
    }

    /// Открывает портал с центром в точке экрана `center`.
    func open(center: CGPoint, size: CGSize, duration: Double) {
        generation += 1
        let m = Self.margin
        let frameSize = CGSize(width: size.width + m * 2, height: size.height + m * 2)
        panel.setFrame(CGRect(x: center.x - frameSize.width / 2, y: center.y - frameSize.height / 2,
                              width: frameSize.width, height: frameSize.height), display: false)
        holder.frame = CGRect(origin: .zero, size: frameSize)
        let path = CGPath(ellipseIn: CGRect(x: m, y: m, width: size.width, height: size.height), transform: nil)
        for layer in [fill, ring] {
            layer.frame = holder.bounds
            layer.path = path
        }
        panel.orderFrontRegardless()

        holder.removeAllAnimations()
        holder.opacity = 1
        let grow = CABasicAnimation(keyPath: "transform.scale")
        grow.fromValue = 0.05
        grow.toValue = 1
        grow.duration = duration
        grow.timingFunction = CAMediaTimingFunction(name: .easeOut)
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0
        fade.toValue = 1
        fade.duration = duration
        holder.add(grow, forKey: "open")
        holder.add(fade, forKey: "openFade")

        // Мерцание края, пока портал открыт.
        let shimmer = CABasicAnimation(keyPath: "shadowRadius")
        shimmer.fromValue = 7
        shimmer.toValue = 14
        shimmer.duration = 0.6
        shimmer.autoreverses = true
        shimmer.repeatCount = .infinity
        ring.add(shimmer, forKey: "shimmer")
    }

    func close(duration: Double) {
        generation += 1
        let expected = generation
        let shrink = CABasicAnimation(keyPath: "transform.scale")
        shrink.fromValue = 1
        shrink.toValue = 0.05
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 1
        fade.toValue = 0
        for animation in [shrink, fade] {
            animation.duration = duration
            animation.timingFunction = CAMediaTimingFunction(name: .easeIn)
            animation.fillMode = .forwards
            animation.isRemovedOnCompletion = false
        }
        holder.add(shrink, forKey: "open")
        holder.add(fade, forKey: "openFade")
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(duration))
            guard let self, self.generation == expected else { return }
            self.panel.orderOut(nil)
        }
    }

    /// Мгновенно убирает портал (прерванный телепорт, скрытие компаньона).
    func hide() {
        generation += 1
        holder.removeAllAnimations()
        ring.removeAllAnimations()
        holder.opacity = 0
        panel.orderOut(nil)
    }
}
