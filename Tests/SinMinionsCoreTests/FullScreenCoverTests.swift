import XCTest
@testable import SinMinionsCore

/// Полноэкранный режим: компаньон скрывается, когда окно активного приложения занимает экран целиком.
final class FullScreenCoverTests: XCTestCase {
    private let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
    private let own: Int32 = 100

    private func window(_ pid: Int32, _ rect: CGRect, layer: Int = 0, onScreen: Bool = true) -> FullScreenCover.Window {
        FullScreenCover.Window(ownerPID: pid, layer: layer, bounds: rect, isOnScreen: onScreen)
    }

    func testFullScreenWindowOfFrontmostAppIsDetected() {
        XCTAssertTrue(FullScreenCover.covers(
            screen: screen, windows: [window(42, screen)], frontmostPID: 42, ownPID: own
        ))
    }

    func testZoomedWindowLeavesTheMenuBarAndDoesNotCount() {
        // Разворот кнопкой zoom оставляет полосу строки меню — это не полноэкранный режим.
        let zoomed = CGRect(x: 0, y: 0, width: 1512, height: 957)
        XCTAssertFalse(FullScreenCover.covers(
            screen: screen, windows: [window(42, zoomed)], frontmostPID: 42, ownPID: own
        ))
    }

    func testWindowOfAnotherAppDoesNotCount() {
        XCTAssertFalse(FullScreenCover.covers(
            screen: screen, windows: [window(7, screen)], frontmostPID: 42, ownPID: own
        ))
    }

    func testOwnWindowDoesNotCount() {
        // Свои окна (пузырь, терминал, настройки) полноэкранным режимом не считаем:
        // иначе приложение спрячет само себя, едва открыв настройки.
        XCTAssertFalse(FullScreenCover.covers(
            screen: screen, windows: [window(own, screen)], frontmostPID: own, ownPID: own
        ))
    }

    func testFloatingLayerDoesNotCount() {
        // Панели, диалоги и оверлеи (у них слой не 0) экран не занимают.
        XCTAssertFalse(FullScreenCover.covers(
            screen: screen, windows: [window(42, screen, layer: 3)], frontmostPID: 42, ownPID: own
        ))
    }

    func testHiddenWindowDoesNotCount() {
        XCTAssertFalse(FullScreenCover.covers(
            screen: screen, windows: [window(42, screen, onScreen: false)], frontmostPID: 42, ownPID: own
        ))
    }

    func testRoundedBoundsStillCount() {
        // WindowServer округляет координаты: расхождение в точке не должно ломать проверку.
        let rounded = CGRect(x: 0, y: 0, width: 1511, height: 981)
        XCTAssertTrue(FullScreenCover.covers(
            screen: screen, windows: [window(42, rounded)], frontmostPID: 42, ownPID: own
        ))
    }

    func testWindowOnSecondScreen() {
        // Второй экран может висеть левее основного: координаты отрицательные.
        let second = CGRect(x: -1920, y: 0, width: 1920, height: 1080)
        let cover = CGRect(x: -1920, y: 0, width: 1920, height: 1080)
        XCTAssertTrue(FullScreenCover.covers(
            screen: second, windows: [window(42, cover)], frontmostPID: 42, ownPID: own
        ))
        XCTAssertFalse(FullScreenCover.covers(
            screen: screen, windows: [window(42, cover)], frontmostPID: 42, ownPID: own
        ))
    }

    func testEmptyWindowList() {
        XCTAssertFalse(FullScreenCover.covers(
            screen: screen, windows: [], frontmostPID: 42, ownPID: own
        ))
    }
}
