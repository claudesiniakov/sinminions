import Foundation
import CoreGraphics

/// Геометрия на экране: координаты AppKit (начало — левый нижний угол, y вверх).
public enum Layout {
    /// Сдвигает прямоугольник так, чтобы он целиком лежал в области.
    public static func clamp(origin: CGPoint, size: CGSize, in area: CGRect) -> CGPoint {
        let maxX = max(area.minX, area.maxX - size.width)
        let maxY = max(area.minY, area.maxY - size.height)
        return CGPoint(
            x: min(max(origin.x, area.minX), maxX),
            y: min(max(origin.y, area.minY), maxY)
        )
    }

    /// Правый нижний угол области — место компаньона по умолчанию.
    public static func corner(size: CGSize, in area: CGRect, margin: CGFloat = 28) -> CGPoint {
        clamp(
            origin: CGPoint(x: area.maxX - size.width - margin, y: area.minY + margin),
            size: size, in: area
        )
    }

    /// Случайная точка перелёта: внутри области и не ближе `minDistance` от текущей (если получается).
    public static func randomTarget(
        size: CGSize, in area: CGRect, from current: CGPoint,
        minDistance: CGFloat = 160,
        random: (ClosedRange<Double>) -> Double = { Double.random(in: $0) }
    ) -> CGPoint {
        let spanX = max(0, area.width - size.width)
        let spanY = max(0, area.height - size.height)
        var best = current
        var bestDistance: CGFloat = -1
        for _ in 0..<8 {
            let candidate = CGPoint(
                x: area.minX + CGFloat(random(0...1)) * spanX,
                y: area.minY + CGFloat(random(0...1)) * spanY
            )
            let distance = hypot(candidate.x - current.x, candidate.y - current.y)
            if distance >= minDistance { return candidate }
            if distance > bestDistance {
                best = candidate
                bestDistance = distance
            }
        }
        return best
    }

    public struct BubblePlacement: Equatable, Sendable {
        public let origin: CGPoint
        /// Пузырь под персонажем (над ним не хватило места).
        public let below: Bool
        /// Горизонтальное положение хвостика относительно левого края пузыря.
        public let tailX: CGFloat
    }

    /// Пузырь над персонажем по центру; у верхнего края — под ним; по горизонтали не выходит за область.
    public static func bubble(size: CGSize, over moth: CGRect, in area: CGRect, gap: CGFloat = 4) -> BubblePlacement {
        let below = moth.maxY + gap + size.height > area.maxY
        let y = below ? moth.minY - gap - size.height : moth.maxY + gap
        let wanted = CGPoint(x: moth.midX - size.width / 2, y: y)
        let origin = clamp(origin: wanted, size: size, in: area)
        let tail = min(max(moth.midX - origin.x, 14), size.width - 14)
        return BubblePlacement(origin: origin, below: below, tailX: tail)
    }

    public struct ConsolePlacement: Equatable, Sendable {
        /// Левый нижний угол самого персонажа (не его окна).
        public let moth: CGPoint
        /// Видимые прямоугольники окон терминала и монитора.
        public let terminal: CGRect
        public let monitor: CGRect
    }

    /// Средний режим: персонаж по центру области, под ним в один ряд терминал и монитор одной высоты,
    /// с общими верхним и нижним краями; пара стоит по центру под персонажем.
    public static func console(
        moth: CGSize, terminal: CGSize, monitor: CGSize, in area: CGRect,
        gap: CGFloat = 24, margin: CGFloat = 12
    ) -> ConsolePlacement {
        let availableWidth = max(area.width - 2 * margin, 0)
        let terminalWidth = min(terminal.width, max(availableWidth - gap - monitor.width, 240))
        let rowWidth = terminalWidth + gap + monitor.width
        let availableHeight = max(area.height - 2 * margin - moth.height - gap, 160)
        let rowHeight = min(max(terminal.height, monitor.height), availableHeight)
        let block = moth.height + gap + rowHeight
        let top = min(area.maxY - margin, area.midY + block / 2)
        let mothOrigin = CGPoint(x: area.midX - moth.width / 2, y: top - moth.height)
        let rowY = max(area.minY + margin, mothOrigin.y - gap - rowHeight)
        let left = max(area.minX + margin, area.midX - rowWidth / 2)
        return ConsolePlacement(
            moth: mothOrigin,
            terminal: CGRect(x: left, y: rowY, width: terminalWidth, height: rowHeight),
            monitor: CGRect(x: left + terminalWidth + gap, y: rowY, width: monitor.width, height: rowHeight)
        )
    }

    /// Центр портала рядом с призраком: сбоку (со стороны `side`: +1 справа, −1 слева), а если не помещается —
    /// с другой стороны, под призраком или над ним. Портал никогда не накрывает призрака.
    public static func portalCenter(
        beside ghost: CGRect, portal: CGSize, preferring side: CGFloat, in area: CGRect,
        gap: CGFloat = 14, margin: CGFloat = 8
    ) -> CGPoint {
        let inner = area.insetBy(dx: margin, dy: margin)
        func rect(_ center: CGPoint) -> CGRect {
            CGRect(x: center.x - portal.width / 2, y: center.y - portal.height / 2, width: portal.width, height: portal.height)
        }
        let preferred: CGFloat = side >= 0 ? 1 : -1
        let dx = ghost.width / 2 + gap + portal.width / 2
        let candidates = [
            CGPoint(x: ghost.midX + preferred * dx, y: ghost.midY),
            CGPoint(x: ghost.midX - preferred * dx, y: ghost.midY),
            CGPoint(x: ghost.midX, y: ghost.minY - gap - portal.height / 2),
            CGPoint(x: ghost.midX, y: ghost.maxY + gap + portal.height / 2),
        ]
        for center in candidates where inner.contains(rect(center)) && !overlaps(rect(center), ghost) {
            return center
        }
        return candidates[0]
    }

    /// Ближе ли два прямоугольника друг к другу, чем на `gap`. Расстояние ровно `gap` допустимо.
    public static func overlaps(_ a: CGRect, _ b: CGRect, gap: CGFloat = 0) -> Bool {
        a.minX < b.maxX + gap && a.maxX > b.minX - gap && a.minY < b.maxY + gap && a.maxY > b.minY - gap
    }

    /// Перемещение окна: остаётся в области и не наезжает на препятствия (соседнее окно, персонаж).
    /// Если нужное место занято, окно встаёт в ближайшее свободное (слева, справа, выше или ниже препятствия);
    /// nil — свободного места нет, и окно должно остаться там, где было.
    public static func placeWindow(
        _ proposed: CGRect, avoiding obstacles: [CGRect], in area: CGRect, gap: CGFloat = 8
    ) -> CGRect? {
        let size = proposed.size
        func clamped(_ origin: CGPoint) -> CGRect {
            CGRect(origin: clamp(origin: origin, size: size, in: area), size: size)
        }
        func free(_ rect: CGRect) -> Bool { !obstacles.contains { overlaps(rect, $0, gap: gap) } }
        let wanted = clamped(proposed.origin)
        if free(wanted) { return wanted }
        var best: CGRect?
        var bestDistance = CGFloat.infinity
        for o in obstacles {
            let candidates = [
                CGPoint(x: o.minX - gap - size.width, y: wanted.minY),
                CGPoint(x: o.maxX + gap, y: wanted.minY),
                CGPoint(x: wanted.minX, y: o.maxY + gap),
                CGPoint(x: wanted.minX, y: o.minY - gap - size.height),
            ]
            for origin in candidates {
                let rect = clamped(origin)
                guard free(rect) else { continue }
                let distance = hypot(rect.minX - wanted.minX, rect.minY - wanted.minY)
                if distance < bestDistance {
                    best = rect
                    bestDistance = distance
                }
            }
        }
        return best
    }

    /// Изменение размера за правый нижний угол (левый верхний неподвижен). Размер не меньше `minSize`,
    /// не выходит за область и не наезжает на препятствия: упирается в них. nil — подходящего размера нет.
    public static func resizedWindow(
        from start: CGRect, to size: CGSize, avoiding obstacles: [CGRect], in area: CGRect,
        minSize: CGSize, gap: CGFloat = 8
    ) -> CGRect? {
        let maxWidth = area.maxX - start.minX
        let maxHeight = start.maxY - area.minY
        guard maxWidth >= minSize.width, maxHeight >= minSize.height else { return nil }
        let width = min(max(size.width, minSize.width), maxWidth)
        let height = min(max(size.height, minSize.height), maxHeight)
        func rect(_ w: CGFloat, _ h: CGFloat) -> CGRect {
            CGRect(x: start.minX, y: start.maxY - h, width: w, height: h)
        }
        func free(_ r: CGRect) -> Bool { !obstacles.contains { overlaps(r, $0, gap: gap) } }
        let wanted = rect(width, height)
        if free(wanted) { return wanted }
        var widthLimit = width
        var heightLimit = height
        for o in obstacles where overlaps(wanted, o, gap: gap) {
            // Препятствие справа ограничивает ширину, снизу — высоту.
            if o.minX >= start.minX { widthLimit = min(widthLimit, o.minX - gap - start.minX) }
            if o.maxY <= start.maxY { heightLimit = min(heightLimit, start.maxY - (o.maxY + gap)) }
        }
        let candidates = [rect(widthLimit, height), rect(width, heightLimit), rect(widthLimit, heightLimit)]
        return candidates
            .filter { $0.width >= minSize.width && $0.height >= minSize.height && free($0) }
            .max { $0.width * $0.height < $1.width * $1.height }
    }

    /// Сохранённая раскладка годится, только если окна в области и не наезжают друг на друга и на персонажа.
    public static func isValidConsoleLayout(
        terminal: CGRect, monitor: CGRect, ghost: CGRect, in area: CGRect, gap: CGFloat = 8
    ) -> Bool {
        area.contains(terminal) && area.contains(monitor)
            && !overlaps(terminal, monitor, gap: gap)
            && !overlaps(terminal, ghost, gap: gap)
            && !overlaps(monitor, ghost, gap: gap)
    }

    /// Плавный разгон и торможение: доля пути по доле времени.
    public static func ease(_ t: Double) -> Double {
        let x = min(max(t, 0), 1)
        return x * x * (3 - 2 * x)
    }
}
