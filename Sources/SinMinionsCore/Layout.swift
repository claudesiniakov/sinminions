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

    /// Плавный разгон и торможение: доля пути по доле времени.
    public static func ease(_ t: Double) -> Double {
        let x = min(max(t, 0), 1)
        return x * x * (3 - 2 * x)
    }
}
