import Foundation

/// Признак того, что активное приложение занимает экран целиком.
///
/// Проверяем окна WindowServer: у активного приложения должно быть видимое окно обычного слоя,
/// покрывающее экран от края до края. Окно, развёрнутое кнопкой zoom, оставляет полосу строки меню
/// и строку заголовка, поэтому под правило не попадает — как и панели, диалоги и обои.
/// Так же распознаётся видео во весь экран в браузере: у него настоящее полноэкранное окно.
public enum FullScreenCover {
    /// Окно в координатах AppKit (начало в левом нижнем углу основного экрана).
    public struct Window: Equatable, Sendable {
        public let ownerPID: Int32
        public let layer: Int
        public let bounds: CGRect
        public let isOnScreen: Bool

        public init(ownerPID: Int32, layer: Int, bounds: CGRect, isOnScreen: Bool = true) {
            self.ownerPID = ownerPID
            self.layer = layer
            self.bounds = bounds
            self.isOnScreen = isOnScreen
        }
    }

    /// `tolerance` — допуск в точках: границы окон приходят из WindowServer уже округлёнными.
    public static func covers(
        screen: CGRect, windows: [Window], frontmostPID: Int32, ownPID: Int32, tolerance: CGFloat = 2
    ) -> Bool {
        guard frontmostPID != ownPID else { return false }
        return windows.contains { window in
            guard window.isOnScreen, window.layer == 0,
                  window.ownerPID == frontmostPID, window.ownerPID != ownPID,
                  window.bounds.width > 0, window.bounds.height > 0 else { return false }
            return window.bounds.minX <= screen.minX + tolerance
                && window.bounds.minY <= screen.minY + tolerance
                && window.bounds.maxX >= screen.maxX - tolerance
                && window.bounds.maxY >= screen.maxY - tolerance
        }
    }
}
