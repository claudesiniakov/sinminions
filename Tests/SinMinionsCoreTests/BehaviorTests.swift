import XCTest
import CryptoKit
@testable import SinMinionsCore

final class BehaviorEngineTests: XCTestCase {
    /// Случайность заменена нижней границей интервала: перелёт через 60 с, реплика через 120 с.
    private func makeEngine(_ change: (inout BehaviorConfig) -> Void = { _ in }) -> BehaviorEngine {
        var config = BehaviorConfig()
        change(&config)
        return BehaviorEngine(config: config, now: 0, random: { $0.lowerBound })
    }

    func testStartsIdleAndStaysQuietBeforeTimers() {
        var engine = makeEngine()
        XCTAssertEqual(engine.mode, .idle)
        XCTAssertEqual(engine.tick(now: 30, idleSeconds: 1), [])
        XCTAssertEqual(engine.mode, .idle)
    }

    func testWandersThenReturnsToIdle() {
        var engine = makeEngine()
        XCTAssertEqual(engine.tick(now: 60, idleSeconds: 1), [.startWander])
        XCTAssertEqual(engine.mode, .wandering)
        XCTAssertEqual(engine.tick(now: 61, idleSeconds: 1), [])
        XCTAssertEqual(engine.handle(.arrived, now: 70), [])
        XCTAssertEqual(engine.mode, .idle)
        XCTAssertEqual(engine.nextWanderAt, 130)
    }

    func testTalksForFourSecondsAndWanderDoesNotStarveTalk() {
        var engine = makeEngine()
        _ = engine.tick(now: 60, idleSeconds: 1)
        _ = engine.handle(.arrived, now: 70)
        // Таймер реплик не сбрасывается перелётом: в 120 с — реплика, хотя перелёт был в 60 с.
        XCTAssertEqual(engine.tick(now: 120, idleSeconds: 1), [.say(.ambient)])
        XCTAssertEqual(engine.mode, .talking)
        XCTAssertEqual(engine.tick(now: 123, idleSeconds: 1), [])
        XCTAssertEqual(engine.tick(now: 124, idleSeconds: 1), [.hideBubble])
        XCTAssertEqual(engine.mode, .idle)
        XCTAssertEqual(engine.nextTalkAt, 244)
    }

    func testFallsAsleepWhenIdleAndWakesOnInput() {
        var engine = makeEngine()
        XCTAssertEqual(engine.tick(now: 10, idleSeconds: 300), [.fallAsleep])
        XCTAssertEqual(engine.mode, .sleeping)
        // Во сне таймеры перелёта и реплик не срабатывают.
        XCTAssertEqual(engine.tick(now: 500, idleSeconds: 790), [])
        XCTAssertEqual(engine.tick(now: 501, idleSeconds: 0.5), [.wakeUp])
        XCTAssertEqual(engine.mode, .idle)
        // Сразу после пробуждения ничего не начинается само.
        XCTAssertEqual(engine.tick(now: 502, idleSeconds: 1), [])
    }

    func testNeverSleepsWhenDisabled() {
        var engine = makeEngine { $0.sleepAfter = nil; $0.wanderEnabled = false; $0.talkEnabled = false }
        XCTAssertEqual(engine.tick(now: 5000, idleSeconds: 5000), [])
        XCTAssertEqual(engine.mode, .idle)
    }

    func testDoubleClickOpensSpotlightFromAnyState() {
        var engine = makeEngine()
        XCTAssertEqual(engine.handle(.doubleClick, now: 1), [.openSpotlight])

        _ = engine.tick(now: 60, idleSeconds: 1)
        XCTAssertEqual(engine.mode, .wandering)
        XCTAssertEqual(engine.handle(.doubleClick, now: 61), [.stopWander, .openSpotlight])
        XCTAssertEqual(engine.mode, .idle)

        _ = engine.tick(now: 62, idleSeconds: 400)
        XCTAssertEqual(engine.mode, .sleeping)
        XCTAssertEqual(engine.handle(.doubleClick, now: 63), [.wakeUp, .openSpotlight])
    }

    func testDoubleClickDoesNothingWhenSpotlightDisabled() {
        var engine = makeEngine { $0.spotlightEnabled = false }
        XCTAssertEqual(engine.handle(.doubleClick, now: 1), [])
    }

    func testClickHopsAndSpeaks() {
        var engine = makeEngine()
        XCTAssertEqual(engine.handle(.click, now: 1), [.hop, .say(.click)])
        XCTAssertEqual(engine.mode, .reacting)
        XCTAssertEqual(engine.tick(now: 5, idleSeconds: 0), [.hideBubble])
        XCTAssertEqual(engine.mode, .idle)
    }

    func testDragInterruptsAndHoldsPosition() {
        var engine = makeEngine()
        _ = engine.tick(now: 60, idleSeconds: 1)
        XCTAssertEqual(engine.handle(.dragBegan, now: 61), [.stopWander])
        XCTAssertEqual(engine.mode, .dragged)
        // Пока тащат — ни щелчков, ни таймеров.
        XCTAssertEqual(engine.handle(.click, now: 62), [])
        XCTAssertEqual(engine.tick(now: 400, idleSeconds: 0), [])
        XCTAssertEqual(engine.handle(.dragEnded, now: 401), [])
        XCTAssertEqual(engine.mode, .idle)
        XCTAssertGreaterThanOrEqual(engine.nextWanderAt, 461)
    }

    func testNapIgnoresInputUntilItEnds() {
        var engine = makeEngine()
        XCTAssertEqual(engine.handle(.nap(3600), now: 10), [.fallAsleep])
        XCTAssertTrue(engine.isNapping)
        XCTAssertEqual(engine.tick(now: 100, idleSeconds: 0), [])
        XCTAssertEqual(engine.tick(now: 3610, idleSeconds: 0), [.wakeUp])
        XCTAssertFalse(engine.isNapping)
    }

    func testClickWakesFromNap() {
        var engine = makeEngine()
        _ = engine.handle(.nap(3600), now: 10)
        XCTAssertEqual(engine.handle(.click, now: 20), [.wakeUp, .hop, .say(.click)])
        XCTAssertFalse(engine.isNapping)
    }

    func testAnnounceInterruptsWander() {
        var engine = makeEngine()
        _ = engine.tick(now: 60, idleSeconds: 1)
        XCTAssertEqual(engine.handle(.announce(.charging), now: 61), [.stopWander, .say(.charging)])
        XCTAssertEqual(engine.mode, .talking)
    }

    func testSuspendKeepsSleepAndStopsEverythingElse() {
        var engine = makeEngine()
        _ = engine.tick(now: 60, idleSeconds: 1)
        XCTAssertEqual(engine.handle(.suspended, now: 61), [.stopWander])
        XCTAssertEqual(engine.mode, .idle)
        _ = engine.handle(.nap(100), now: 62)
        XCTAssertEqual(engine.handle(.suspended, now: 63), [])
        XCTAssertEqual(engine.mode, .sleeping)
    }

    func testReconfigureRestartsTimers() {
        var engine = makeEngine()
        var config = BehaviorConfig()
        config.wanderInterval = 20...60
        engine.reconfigure(config, now: 100)
        XCTAssertEqual(engine.nextWanderAt, 120)
    }
}

final class ConsoleModeTests: XCTestCase {
    private func makeEngine() -> BehaviorEngine {
        var config = BehaviorConfig()
        config.consoleEnabled = true
        return BehaviorEngine(config: config, now: 0, random: { $0.lowerBound })
    }

    func testDoubleClickOpensConsoleInsteadOfSpotlight() {
        var engine = makeEngine()
        XCTAssertEqual(engine.handle(.doubleClick, now: 1), [.openConsole])
        XCTAssertEqual(engine.mode, .console)
    }

    func testConsoleFreezesTimersAndIgnoresClicks() {
        var engine = makeEngine()
        _ = engine.handle(.doubleClick, now: 1)
        XCTAssertEqual(engine.tick(now: 1000, idleSeconds: 999), [])
        XCTAssertEqual(engine.handle(.click, now: 1001), [])
        XCTAssertEqual(engine.handle(.announce(.charging), now: 1002), [])
        XCTAssertEqual(engine.mode, .console)
    }

    func testConsoleClosesOnSecondDoubleClickEscAndDrag() {
        var engine = makeEngine()
        _ = engine.handle(.doubleClick, now: 1)
        XCTAssertEqual(engine.handle(.doubleClick, now: 2), [.closeConsole])
        XCTAssertEqual(engine.mode, .idle)
        // После закрытия призрак остаётся на месте не меньше минуты.
        XCTAssertGreaterThanOrEqual(engine.nextWanderAt, 62)

        _ = engine.handle(.doubleClick, now: 3)
        XCTAssertEqual(engine.handle(.closeConsole, now: 4), [.closeConsole])
        XCTAssertEqual(engine.handle(.closeConsole, now: 5), [])

        _ = engine.handle(.doubleClick, now: 6)
        XCTAssertEqual(engine.handle(.dragBegan, now: 7), [.closeConsole])
        XCTAssertEqual(engine.mode, .dragged)
    }

    func testNapAndSuspendCloseConsole() {
        var engine = makeEngine()
        _ = engine.handle(.doubleClick, now: 1)
        XCTAssertEqual(engine.handle(.nap(3600), now: 2), [.closeConsole, .fallAsleep])

        var other = makeEngine()
        _ = other.handle(.doubleClick, now: 1)
        XCTAssertEqual(other.handle(.suspended, now: 2), [.closeConsole])
        XCTAssertEqual(other.mode, .idle)
    }

    func testConsoleLayoutAlignsTheWindowsInOneRow() {
        let area = CGRect(x: 0, y: 80, width: 1440, height: 800)
        let place = Layout.console(
            moth: CGSize(width: 72, height: 84), terminal: CGSize(width: 440, height: 580),
            monitor: CGSize(width: 280, height: 580), in: area
        )
        XCTAssertEqual(place.moth, CGPoint(x: 684, y: 740))
        XCTAssertEqual(place.terminal, CGRect(x: 348, y: 136, width: 440, height: 580))
        XCTAssertEqual(place.monitor, CGRect(x: 812, y: 136, width: 280, height: 580))
        // Одна высота, общие верхний и нижний края, зазор между окнами, пара по центру под персонажем.
        XCTAssertEqual(place.terminal.minY, place.monitor.minY)
        XCTAssertEqual(place.terminal.maxY, place.monitor.maxY)
        XCTAssertEqual(place.monitor.minX - place.terminal.maxX, 24)
        XCTAssertEqual((place.terminal.minX + place.monitor.maxX) / 2, area.midX)
        XCTAssertEqual(place.moth.x + 36, area.midX)
    }

    func testConsoleLayoutOnASmallScreen() {
        let area = CGRect(x: 0, y: 24, width: 1024, height: 680)
        let place = Layout.console(
            moth: CGSize(width: 72, height: 84), terminal: CGSize(width: 440, height: 580),
            monitor: CGSize(width: 280, height: 580), in: area
        )
        XCTAssertTrue(area.contains(place.terminal))
        XCTAssertTrue(area.contains(place.monitor))
        XCTAssertEqual(place.terminal.height, place.monitor.height)
        XCTAssertLessThan(place.terminal.height, 580, "на невысоком экране окна ниже желаемого")
        XCTAssertFalse(Layout.overlaps(place.terminal, place.monitor))
        XCTAssertLessThanOrEqual(place.moth.y + 84, area.maxY)
        // Персонаж над рядом, не на нём.
        XCTAssertGreaterThanOrEqual(place.moth.y, place.terminal.maxY)
    }
}

final class MoreProvidersTests: XCTestCase {
    func testCatalogs() {
        XCTAssertEqual(LLMProvider.claude.models.first, "claude-haiku-5-5")
        XCTAssertEqual(LLMProvider.claude.models.last, "claude-fable-5-2")
        XCTAssertEqual(LLMProvider.gpt.defaultModel, "gpt-6-luna")
        XCTAssertEqual(LLMProvider.grok.models.last, "grok-4.7")
        XCTAssertEqual(LLMProvider.gemini.models.last, "gemini-4-carbon")
        for provider in LLMProvider.allCases {
            XCTAssertFalse(provider.models.isEmpty, provider.title)
            XCTAssertEqual(Set(provider.models).count, provider.models.count, provider.title)
            XCTAssertEqual(LLMConnection(name: "x", provider: provider).model, provider.models[0])
            XCTAssertEqual(provider.normalizedKey("  Bearer k-1\n"), provider == .gigachat ? "Bearerk-1" : "k-1")
        }
        XCTAssertFalse(LLMProvider.claude.usesScope)
        XCTAssertEqual(LLMProvider.allCases.filter(\.supportsLimits), [.gigachat, .deepseek])
    }

    func testClaudeRequestShape() throws {
        let messages = [ChatMessage(.system, "кратко"), ChatMessage(.user, "привет"), ChatMessage(.assistant, "здравствуй"), ChatMessage(.user, "как дела")]
        let request = AnthropicAPI.chatRequest(key: "sk-ant-1", model: "claude-opus-5-5", messages: messages)
        XCTAssertEqual(request.url?.absoluteString, "https://api.anthropic.com/v1/messages")
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-api-key"), "sk-ant-1")
        XCTAssertEqual(request.value(forHTTPHeaderField: "anthropic-version"), "2023-06-01")
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
        XCTAssertEqual(body["model"] as? String, "claude-opus-5-5")
        XCTAssertEqual(body["system"] as? String, "кратко")
        XCTAssertNotNil(body["max_tokens"])
        XCTAssertNil(body["temperature"], "новые модели Claude не принимают параметры выборки")
        let sent = try XCTUnwrap(body["messages"] as? [[String: String]])
        XCTAssertEqual(sent.map { $0["role"] }, ["user", "assistant", "user"], "системного сообщения среди messages нет")
        let models = AnthropicAPI.modelsRequest(key: "k")
        XCTAssertEqual(models.url?.absoluteString, "https://api.anthropic.com/v1/models")
        XCTAssertEqual(models.value(forHTTPHeaderField: "x-api-key"), "k")
    }

    func testClaudeResponseParsing() throws {
        let ok = #"{"content":[{"type":"thinking","thinking":""},{"type":"text","text":" первый "},{"type":"text","text":"второй"}],"stop_reason":"end_turn"}"#
        XCTAssertEqual(try AnthropicAPI.parseMessage(Data(ok.utf8)), "первый \nвторой")
        XCTAssertThrowsError(try AnthropicAPI.parseMessage(Data(#"{"content":[],"stop_reason":"refusal"}"#.utf8))) {
            XCTAssertEqual($0 as? LLMError, .refused)
        }
        XCTAssertThrowsError(try AnthropicAPI.parseMessage(Data(#"{"content":[{"type":"thinking","thinking":"x"}],"stop_reason":"max_tokens"}"#.utf8))) {
            XCTAssertEqual($0 as? LLMError, .emptyAnswer)
        }
        XCTAssertThrowsError(try AnthropicAPI.parseMessage(Data("не json".utf8)))
        // Ошибка Anthropic: {"type":"error","error":{"message":...}}.
        XCTAssertEqual(LLMResponse.errorDetail(Data(#"{"type":"error","error":{"type":"authentication_error","message":"invalid x-api-key"}}"#.utf8)), "invalid x-api-key")
        XCTAssertEqual(LLMError.refused.shortDescription, "отказ")
    }

    func testOpenAICompatibleEndpointsAndRequests() throws {
        XCTAssertEqual(OpenAICompatibleAPI.endpoints(for: .gpt)?.chat.absoluteString, "https://api.openai.com/v1/chat/completions")
        XCTAssertEqual(OpenAICompatibleAPI.endpoints(for: .grok)?.models.absoluteString, "https://api.x.ai/v1/models")
        XCTAssertEqual(OpenAICompatibleAPI.endpoints(for: .gemini)?.chat.absoluteString, "https://generativelanguage.googleapis.com/v1beta/openai/chat/completions")
        XCTAssertNil(OpenAICompatibleAPI.endpoints(for: .claude))
        XCTAssertNil(OpenAICompatibleAPI.chatRequest(provider: .deepseek, key: "k", model: "m", messages: []))
        let messages = [ChatMessage(.system, "кратко"), ChatMessage(.user, "привет")]
        for provider in [LLMProvider.gpt, .grok, .gemini] {
            let request = try XCTUnwrap(OpenAICompatibleAPI.chatRequest(provider: provider, key: "k-1", model: provider.defaultModel, messages: messages))
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer k-1")
            let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
            XCTAssertEqual(body["model"] as? String, provider.defaultModel)
            XCTAssertEqual(body["stream"] as? Bool, false)
            let sent = try XCTUnwrap(body["messages"] as? [[String: String]])
            // У OpenAI системное сообщение называется developer, у остальных — system.
            XCTAssertEqual(sent[0]["role"], provider == .gpt ? "developer" : "system")
            XCTAssertEqual(sent[1]["role"], "user")
            XCTAssertNil(body["temperature"])
            let models = try XCTUnwrap(OpenAICompatibleAPI.modelsRequest(provider: provider, key: "k-1"))
            XCTAssertEqual(models.httpMethod, "GET")
        }
    }
}

final class SlashCommandTests: XCTestCase {
    func testParsesLatinAndRussianNames() {
        XCTAssertEqual(SlashParser.parse("/help"), .command(.help))
        XCTAssertEqual(SlashParser.parse("/помощь"), .command(.help))
        XCTAssertEqual(SlashParser.parse("  /SLEEP  "), .command(.nap))
        XCTAssertEqual(SlashParser.parse("/Сон"), .command(.nap))
        XCTAssertEqual(SlashParser.parse("/unlock"), .command(.unlock))
        XCTAssertEqual(SlashParser.parse("/заблокировать"), .command(.lock))
        XCTAssertEqual(SlashParser.parse("/reset"), .command(.resetLayout))
        XCTAssertEqual(SlashParser.parse("/настройки"), .command(.settings))
        XCTAssertEqual(SlashParser.parse("/clear"), .command(.clear))
        XCTAssertEqual(SlashParser.parse("/next"), .command(.next))
        XCTAssertEqual(SlashParser.parse("/пред"), .command(.previous))
        XCTAssertEqual(SlashParser.parse("/?"), .command(.help))
    }

    func testIgnoresArgumentsAndNonCommands() {
        XCTAssertEqual(SlashParser.parse("/help me please"), .command(.help))
        XCTAssertEqual(SlashParser.parse("привет"), .notACommand)
        XCTAssertEqual(SlashParser.parse(""), .notACommand)
        XCTAssertEqual(SlashParser.parse("а это /help не в начале"), .notACommand)
    }

    func testUnknownCommand() {
        XCTAssertEqual(SlashParser.parse("/xyz"), .unknown("/xyz"))
        XCTAssertEqual(SlashParser.parse("/"), .unknown("/"))
        XCTAssertEqual(SlashParser.parse("/Foo bar"), .unknown("/Foo"))
    }

    func testEveryCommandHasNamesAndIsDocumentedInHelp() {
        let help = SlashParser.helpLines.joined(separator: "\n")
        for command in SlashCommand.allCases {
            let variants = SlashParser.names[command] ?? []
            XCTAssertFalse(variants.isEmpty, "\(command)")
            // Первое (латинское) название команды есть в справке.
            XCTAssertTrue(help.contains(variants[0]), "\(command): \(variants[0])")
            for variant in variants { XCTAssertEqual(SlashParser.parse(variant), .command(command)) }
        }
        // Названия не пересекаются между командами.
        let all = SlashParser.names.values.flatMap { $0 }
        XCTAssertEqual(Set(all).count, all.count)
    }
}

final class WindowPlacementTests: XCTestCase {
    private let area = CGRect(x: 0, y: 0, width: 1000, height: 800)

    func testOverlapsHonoursTheGap() {
        let a = CGRect(x: 0, y: 0, width: 100, height: 100)
        XCTAssertTrue(Layout.overlaps(a, CGRect(x: 50, y: 50, width: 100, height: 100)))
        XCTAssertFalse(Layout.overlaps(a, CGRect(x: 108, y: 0, width: 100, height: 100), gap: 8), "расстояние ровно в зазор допустимо")
        XCTAssertTrue(Layout.overlaps(a, CGRect(x: 107, y: 0, width: 100, height: 100), gap: 8))
        XCTAssertFalse(Layout.overlaps(a, CGRect(x: 300, y: 300, width: 10, height: 10), gap: 8))
    }

    func testMoveInFreeSpaceIsJustClamped() {
        let rect = CGRect(x: 900, y: 700, width: 150, height: 150)
        XCTAssertEqual(Layout.placeWindow(rect, avoiding: [], in: area), CGRect(x: 850, y: 650, width: 150, height: 150))
    }

    func testMoveOntoANeighbourSlidesToTheNearestFreeSpot() throws {
        let neighbour = CGRect(x: 400, y: 100, width: 200, height: 300)
        let moved = try XCTUnwrap(Layout.placeWindow(CGRect(x: 450, y: 150, width: 150, height: 150), avoiding: [neighbour], in: area))
        XCTAssertEqual(moved.origin, CGPoint(x: 608, y: 150), "ближайшее свободное место — справа от соседа с зазором 8")
        XCTAssertFalse(Layout.overlaps(moved, neighbour, gap: 8))
    }

    func testMoveAvoidsSeveralObstacles() throws {
        let obstacles = [CGRect(x: 400, y: 100, width: 200, height: 300), CGRect(x: 620, y: 100, width: 100, height: 300)]
        let moved = try XCTUnwrap(Layout.placeWindow(CGRect(x: 450, y: 150, width: 150, height: 150), avoiding: obstacles, in: area))
        for obstacle in obstacles { XCTAssertFalse(Layout.overlaps(moved, obstacle, gap: 8)) }
        XCTAssertTrue(area.contains(moved))
    }

    func testMoveHasNoSpot() {
        let tiny = CGRect(x: 0, y: 0, width: 300, height: 300)
        XCTAssertNil(Layout.placeWindow(CGRect(x: 10, y: 10, width: 200, height: 200), avoiding: [tiny], in: tiny))
    }

    func testResizeStopsAtTheRightNeighbour() throws {
        let start = CGRect(x: 100, y: 100, width: 200, height: 200)
        let neighbour = CGRect(x: 400, y: 0, width: 200, height: 600)
        let resized = try XCTUnwrap(Layout.resizedWindow(from: start, to: CGSize(width: 500, height: 200), avoiding: [neighbour], in: area, minSize: CGSize(width: 100, height: 100)))
        XCTAssertEqual(resized.width, 292)
        XCTAssertEqual(resized.height, 200)
        XCTAssertEqual(resized.minX, 100)
        XCTAssertEqual(resized.maxY, 300, "верхний край неподвижен")
    }

    func testResizeStopsAtTheNeighbourBelow() throws {
        let start = CGRect(x: 100, y: 300, width: 200, height: 200)
        let below = CGRect(x: 0, y: 0, width: 600, height: 200)
        let resized = try XCTUnwrap(Layout.resizedWindow(from: start, to: CGSize(width: 200, height: 400), avoiding: [below], in: area, minSize: CGSize(width: 100, height: 100)))
        XCTAssertEqual(resized.height, 292)
        XCTAssertEqual(resized.minY, 208)
        XCTAssertEqual(resized.maxY, 500)
    }

    func testResizeRespectsMinimumAndArea() throws {
        let start = CGRect(x: 100, y: 100, width: 200, height: 200)
        // Меньше минимума не станет.
        let small = try XCTUnwrap(Layout.resizedWindow(from: start, to: CGSize(width: 10, height: 10), avoiding: [], in: area, minSize: CGSize(width: 150, height: 120)))
        XCTAssertEqual(small.size, CGSize(width: 150, height: 120))
        // За край области не выйдет.
        let huge = try XCTUnwrap(Layout.resizedWindow(from: start, to: CGSize(width: 5000, height: 5000), avoiding: [], in: area, minSize: CGSize(width: 150, height: 120)))
        XCTAssertEqual(huge.maxX, area.maxX)
        XCTAssertEqual(huge.minY, area.minY)
        // Соседа так близко, что минимальный размер не помещается, — nil.
        let close = CGRect(x: 250, y: 0, width: 200, height: 600)
        XCTAssertNil(Layout.resizedWindow(from: start, to: CGSize(width: 300, height: 200), avoiding: [close], in: area, minSize: CGSize(width: 160, height: 100)))
    }

    func testSavedLayoutValidation() {
        let terminal = CGRect(x: 100, y: 100, width: 400, height: 500)
        let monitor = CGRect(x: 600, y: 100, width: 250, height: 500)
        let ghost = CGRect(x: 450, y: 650, width: 80, height: 100)
        XCTAssertTrue(Layout.isValidConsoleLayout(terminal: terminal, monitor: monitor, ghost: ghost, in: area))
        // Наезжают друг на друга, на персонажа, выходят за область.
        XCTAssertFalse(Layout.isValidConsoleLayout(terminal: terminal, monitor: CGRect(x: 450, y: 100, width: 250, height: 500), ghost: ghost, in: area))
        XCTAssertFalse(Layout.isValidConsoleLayout(terminal: terminal, monitor: monitor, ghost: CGRect(x: 300, y: 300, width: 50, height: 50), in: area))
        XCTAssertFalse(Layout.isValidConsoleLayout(terminal: terminal, monitor: CGRect(x: 900, y: 100, width: 250, height: 500), ghost: ghost, in: area))
        XCTAssertFalse(Layout.isValidConsoleLayout(terminal: CGRect(x: 100, y: 100, width: 400, height: 500), monitor: CGRect(x: 505, y: 100, width: 250, height: 500), ghost: ghost, in: area), "ближе зазора")
    }
}

final class MetricsTests: XCTestCase {
    func testCPUUsage() {
        let old = CPUTicks(user: 100, system: 50, idle: 850, nice: 0)
        let new = CPUTicks(user: 130, system: 60, idle: 910, nice: 0)
        XCTAssertEqual(CPUTicks.usage(from: old, to: new), 0.4)
        XCTAssertNil(CPUTicks.usage(from: old, to: old))
        XCTAssertNil(CPUTicks.usage(from: new, to: old))
    }

    func testGauge() {
        XCTAssertEqual(Gauge.bar(0.62, width: 10), "██████░░░░")
        XCTAssertEqual(Gauge.bar(0, width: 4), "░░░░")
        XCTAssertEqual(Gauge.bar(7, width: 4), "████")
        XCTAssertEqual(Gauge.bar(.nan, width: 4), "░░░░")
        XCTAssertEqual(Gauge.percent(0.618), "62%")
    }

    func testFormats() {
        XCTAssertEqual(MetricFormat.bytes(12_400_000_000), "12,4 ГБ")
        XCTAssertEqual(MetricFormat.bytes(810_000_000), "810 МБ")
        XCTAssertEqual(MetricFormat.rate(1_200_000), "1,2 МБ/с")
        XCTAssertEqual(MetricFormat.rate(340_000), "340 КБ/с")
        XCTAssertEqual(MetricFormat.rate(-5), "0 КБ/с")
        XCTAssertEqual(MetricFormat.uptime(3 * 86400 + 4 * 3600 + 60), "3д 04ч")
        XCTAssertEqual(MetricFormat.uptime(4 * 3600 + 12 * 60), "4ч 12м")
        XCTAssertEqual(MetricFormat.uptime(12 * 60 + 5), "12м")
    }

    func testNetworkTotalsAndRates() {
        let counters = [
            "en0": InterfaceCounters(rx: 1000, tx: 200),
            "en1": InterfaceCounters(rx: 500, tx: 100),
            "utun3": InterfaceCounters(rx: 9999, tx: 9999),
            "lo0": InterfaceCounters(rx: 7, tx: 7),
        ]
        let total = NetworkCounters.physicalTotal(counters)
        XCTAssertEqual(total, InterfaceCounters(rx: 1500, tx: 300))
        let rate = NetworkCounters.rate(from: InterfaceCounters(rx: 500, tx: 100), to: total, seconds: 2)
        XCTAssertEqual(rate.rx, 500)
        XCTAssertEqual(rate.tx, 100)
        // Счётчик сбросился — скорость 0, а не отрицательная.
        XCTAssertEqual(NetworkCounters.rate(from: total, to: InterfaceCounters(), seconds: 1).rx, 0)
    }

    func testReadsRealCounters() {
        // На любой машине есть хотя бы петлевой интерфейс.
        XCTAssertFalse(NetworkCounters.counters().isEmpty)
    }
}

final class TeleportTests: XCTestCase {
    private func makeEngine(enabled: Bool = true) -> BehaviorEngine {
        var config = BehaviorConfig()
        config.teleportEnabled = enabled
        config.wanderEnabled = false
        config.talkEnabled = false
        config.sleepAfter = nil
        return BehaviorEngine(config: config, now: 0, random: { $0.lowerBound })
    }

    func testTeleportsWhenTimerFires() {
        var engine = makeEngine()
        XCTAssertEqual(engine.tick(now: 89, idleSeconds: 1), [])
        XCTAssertEqual(engine.tick(now: 90, idleSeconds: 1), [.startTeleport])
        XCTAssertEqual(engine.mode, .teleporting)
        // Пока идёт телепорт, таймеры молчат.
        XCTAssertEqual(engine.tick(now: 500, idleSeconds: 1), [])
    }

    func testDisabledByDefaultAndByConfig() {
        var engine = makeEngine(enabled: false)
        XCTAssertEqual(engine.tick(now: 1000, idleSeconds: 1), [])
        XCTAssertFalse(BehaviorConfig().teleportEnabled)
    }

    func testDoneReturnsToIdleAndSchedulesNext() {
        var engine = makeEngine()
        _ = engine.tick(now: 90, idleSeconds: 1)
        XCTAssertEqual(engine.handle(.teleportDone, now: 92), [])
        XCTAssertEqual(engine.mode, .idle)
        XCTAssertEqual(engine.nextTeleportAt, 182)
        XCTAssertEqual(engine.handle(.teleportDone, now: 93), [], "повторное завершение ничего не делает")
    }

    func testTeleportNowOnlyFromIdle() {
        var engine = makeEngine(enabled: false)
        XCTAssertEqual(engine.handle(.teleportNow, now: 1), [.startTeleport])
        XCTAssertEqual(engine.handle(.teleportNow, now: 2), [])
    }

    func testInterruptionsStopTheTeleport() {
        var drag = makeEngine()
        _ = drag.tick(now: 90, idleSeconds: 1)
        XCTAssertEqual(drag.handle(.dragBegan, now: 91), [.stopTeleport])
        XCTAssertEqual(drag.mode, .dragged)

        var click = makeEngine()
        _ = click.tick(now: 90, idleSeconds: 1)
        XCTAssertEqual(click.handle(.click, now: 91), [.stopTeleport, .hop, .say(.click)])

        var hidden = makeEngine()
        _ = hidden.tick(now: 90, idleSeconds: 1)
        XCTAssertEqual(hidden.handle(.suspended, now: 91), [.stopTeleport])
        XCTAssertEqual(hidden.mode, .idle)

        var nap = makeEngine()
        _ = nap.tick(now: 90, idleSeconds: 1)
        XCTAssertEqual(nap.handle(.nap(3600), now: 91), [.stopTeleport, .fallAsleep])
    }

    func testTeleportHasPhrases() {
        XCTAssertFalse(PhraseBook.pool(.teleport, hour: 10).isEmpty)
    }
}

final class GigaChatAPITests: XCTestCase {
    func testTokenRequestShape() throws {
        let request = GigaChatAPI.tokenRequest(authorizationKey: "abc123==", scope: "GIGACHAT_API_PERS")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.absoluteString, "https://ngw.devices.sberbank.ru:9443/api/v2/oauth")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Basic abc123==")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/x-www-form-urlencoded")
        XCTAssertEqual(String(data: try XCTUnwrap(request.httpBody), encoding: .utf8), "scope=GIGACHAT_API_PERS")
        // RqUID — UUID четвёртой версии.
        let rqUID = try XCTUnwrap(request.value(forHTTPHeaderField: "RqUID"))
        XCTAssertNotNil(UUID(uuidString: rqUID))
        XCTAssertEqual(Array(rqUID)[14], "4")
    }

    func testChatRequestShape() throws {
        let messages = [ChatMessage(.system, "будь краток"), ChatMessage(.user, "привет")]
        let request = GigaChatAPI.chatRequest(token: "tok", model: "GigaChat", messages: messages)
        XCTAssertEqual(request.url?.absoluteString, "https://api.giga.chat/v1/chat/completions")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer tok")
        XCTAssertEqual(request.value(forHTTPHeaderField: "User-Agent"), "SinMinions")
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
        XCTAssertEqual(body["model"] as? String, "GigaChat")
        XCTAssertEqual(body["stream"] as? Bool, false)
        let sent = try XCTUnwrap(body["messages"] as? [[String: String]])
        XCTAssertEqual(sent, [["role": "system", "content": "будь краток"], ["role": "user", "content": "привет"]])
    }

    func testNormalizedKey() {
        XCTAssertEqual(GigaChatAPI.normalizedKey("  Basic abc def\n"), "abcdef")
        XCTAssertEqual(GigaChatAPI.normalizedKey("abc=="), "abc==")
        XCTAssertNil(GigaChatAPI.normalizedKey("  \n "))
        XCTAssertNil(GigaChatAPI.normalizedKey("Basic "))
    }

    func testParseTokenSecondsAndMilliseconds() throws {
        let seconds = try GigaChatAPI.parseToken(Data(#"{"access_token":"t","expires_at":1679471442}"#.utf8))
        XCTAssertEqual(seconds.expiresAt, Date(timeIntervalSince1970: 1679471442))
        let millis = try GigaChatAPI.parseToken(Data(#"{"access_token":"t","expires_at":1679471442000}"#.utf8))
        XCTAssertEqual(millis.expiresAt, Date(timeIntervalSince1970: 1679471442))
        XCTAssertThrowsError(try GigaChatAPI.parseToken(Data(#"{"expires_at":1}"#.utf8)))
        XCTAssertThrowsError(try GigaChatAPI.parseToken(Data("не json".utf8)))
    }

    func testTokenUsability() {
        let now = Date(timeIntervalSince1970: 1000)
        XCTAssertTrue(AccessToken(value: "t", expiresAt: now.addingTimeInterval(120)).isUsable(at: now))
        XCTAssertFalse(AccessToken(value: "t", expiresAt: now.addingTimeInterval(30)).isUsable(at: now))
    }

    func testParseChat() throws {
        let ok = #"{"choices":[{"message":{"role":"assistant","content":"  всё под контролем \n"},"index":0,"finish_reason":"stop"}],"usage":{}}"#
        XCTAssertEqual(try GigaChatAPI.parseChat(Data(ok.utf8)), "всё под контролем")
        XCTAssertThrowsError(try GigaChatAPI.parseChat(Data(#"{"choices":[{"message":{"content":" "}}]}"#.utf8))) {
            XCTAssertEqual($0 as? LLMError, .emptyAnswer)
        }
        XCTAssertThrowsError(try GigaChatAPI.parseChat(Data(#"{"choices":[]}"#.utf8))) {
            XCTAssertEqual($0 as? LLMError, .invalidResponse)
        }
    }

    func testErrorTexts() {
        XCTAssertEqual(LLMError.http(401, nil, .token).errorDescription, "Ключ авторизации не подходит: проверьте ключ и область доступа")
        XCTAssertEqual(LLMError.http(401, "Unauthorized", .chat).errorDescription, "Токен не принят — Unauthorized")
        XCTAssertTrue(LLMError.http(429, nil, .chat).errorDescription?.contains("один запрос за раз") == true)
        XCTAssertEqual(LLMError.http(503, nil, .chat).errorDescription, "Сервис GigaChat недоступен (503)")
        XCTAssertEqual(LLMError.http(418, nil, .chat).errorDescription, "Ошибка 418")
    }

    func testErrorDetail() {
        XCTAssertEqual(GigaChatAPI.errorDetail(Data(#"{"status":401,"message":"Unauthorized"}"#.utf8)), "Unauthorized")
        XCTAssertNil(GigaChatAPI.errorDetail(Data("<html>".utf8)))
        let long = String(repeating: "я", count: 300)
        let detail = GigaChatAPI.errorDetail(Data(#"{"message":"\#(long)"}"#.utf8))
        XCTAssertEqual(detail?.count, 121)
    }

    func testHistoryTrimming() {
        let system = ChatMessage(.system, "s")
        let messages = [system, ChatMessage(.user, String(repeating: "а", count: 100)), ChatMessage(.assistant, String(repeating: "б", count: 100)),
                        ChatMessage(.user, String(repeating: "в", count: 100))]
        XCTAssertEqual(ChatHistory.trimmed(messages, maxCharacters: 10_000), messages)
        // Старое отбрасывается, система и последнее остаются, диалог начинается с пользователя.
        let trimmed = ChatHistory.trimmed(messages, maxCharacters: 250)
        XCTAssertEqual(trimmed.first, system)
        XCTAssertEqual(trimmed.last, messages.last)
        XCTAssertEqual(trimmed.count, 2)
        // Единственное сообщение не отбрасывается, даже если оно длиннее лимита.
        XCTAssertEqual(ChatHistory.trimmed([system, messages[3]], maxCharacters: 5).count, 2)
    }

    func testTrustedHostsAndCatalog() {
        XCTAssertTrue(GigaChatAPI.trustedHosts.contains(GigaChatAPI.tokenURL.host ?? ""))
        XCTAssertTrue(GigaChatAPI.trustedHosts.contains(GigaChatAPI.chatURL.host ?? ""))
        XCTAssertEqual(GigaChatAPI.scopes.first, "GIGACHAT_API_PERS")
        XCTAssertEqual(GigaChatAPI.models.first, "GigaChat")
    }

    /// Встроенный корневой сертификат не должен меняться незаметно: сверяем отпечаток с опубликованным.
    func testRussianRootFingerprint() throws {
        let der = try XCTUnwrap(RussianTrustedRoot.der)
        let digest = SHA256.hash(data: der).map { String(format: "%02x", $0) }.joined()
        XCTAssertEqual(digest, "d26d2d0231b7c39f92cc738512ba54103519e4405d68b5bd703e9788ca8ecf31")
    }
}

final class CurlTransportTests: XCTestCase {
    func testEscape() {
        XCTAssertEqual(CurlTransport.escape("a\"b\\c\nd\te"), "a\\\"b\\\\c\\nd\\te")
        XCTAssertEqual(CurlTransport.escape("привет"), "привет")
    }

    func testConfigForChatRequest() {
        var request = GigaChatAPI.chatRequest(token: "tok", model: "GigaChat", messages: [ChatMessage(.user, "привет")])
        request.timeoutInterval = 90
        let config = CurlTransport.config(for: request, caFile: "/tmp/ca.pem")
        let lines = config.split(separator: "\n").map(String.init)
        XCTAssertTrue(lines.contains("cacert = \"/tmp/ca.pem\""))
        XCTAssertTrue(lines.contains("url = \"https://api.giga.chat/v1/chat/completions\""))
        XCTAssertTrue(lines.contains("request = \"POST\""))
        XCTAssertTrue(lines.contains("header = \"Authorization: Bearer tok\""))
        XCTAssertTrue(lines.contains("max-time = 90"))
        XCTAssertTrue(lines.contains("proto = \"=https\""))
        XCTAssertTrue(lines.contains { $0.hasPrefix("data-raw = \"{") && $0.contains("\\\"model\\\"") })
        XCTAssertEqual(lines.last, "write-out = \"\\n%{http_code}\"")
        // Секреты идут только в конфигурации, а не в аргументах процесса.
        XCTAssertFalse(config.contains("--"))
    }

    func testParseOutput() throws {
        let ok = try XCTUnwrap(CurlTransport.parse(Data("{\"a\":1}\n401".utf8)))
        XCTAssertEqual(ok.status, 401)
        XCTAssertEqual(String(data: ok.body, encoding: .utf8), "{\"a\":1}")
        // Многострочное тело: код берётся из последней строки.
        let multi = try XCTUnwrap(CurlTransport.parse(Data("a\nb\n200".utf8)))
        XCTAssertEqual(multi.status, 200)
        XCTAssertEqual(String(data: multi.body, encoding: .utf8), "a\nb")
        XCTAssertNil(CurlTransport.parse(Data("без кода".utf8)))
        XCTAssertNil(CurlTransport.parse(Data()))
    }
}

final class LLMConnectionsTests: XCTestCase {
    private func make(_ count: Int) -> LLMConnections {
        var list = LLMConnections()
        for index in 1...max(count, 1) where count > 0 { list.add(LLMConnection(name: "Подключение \(index)")) }
        return list
    }

    func testLimitIsTen() {
        var list = make(10)
        XCTAssertEqual(list.items.count, 10)
        XCTAssertTrue(list.isFull)
        XCTAssertFalse(list.add(LLMConnection(name: "лишнее")))
        XCTAssertEqual(list.items.count, 10)
    }

    func testFirstAddedBecomesActive() {
        let list = make(3)
        XCTAssertEqual(list.active?.name, "Подключение 1")
        XCTAssertEqual(list.activePosition, 1)
        XCTAssertNil(LLMConnections().active)
        XCTAssertNil(LLMConnections().activePosition)
    }

    func testCycleWrapsBothWays() {
        var list = make(3)
        XCTAssertEqual(list.cycle(by: 1)?.name, "Подключение 2")
        XCTAssertEqual(list.cycle(by: 1)?.name, "Подключение 3")
        XCTAssertEqual(list.cycle(by: 1)?.name, "Подключение 1")
        XCTAssertEqual(list.cycle(by: -1)?.name, "Подключение 3")
        XCTAssertEqual(list.activePosition, 3)
        var empty = LLMConnections()
        XCTAssertNil(empty.cycle(by: 1))
        var single = make(1)
        XCTAssertEqual(single.cycle(by: 1)?.name, "Подключение 1")
        XCTAssertEqual(single.cycle(by: -1)?.name, "Подключение 1")
    }

    func testRemoveMovesActive() {
        var list = make(3)
        let second = list.items[1]
        list.setActive(second.id)
        XCTAssertEqual(list.remove(id: second.id)?.id, second.id)
        XCTAssertEqual(list.items.count, 2)
        XCTAssertEqual(list.active?.name, "Подключение 1")
        // Удаление невыбранного выбор не трогает.
        let third = list.items[1]
        list.remove(id: list.items[0].id)
        XCTAssertEqual(list.active?.id, third.id)
        XCTAssertNil(list.remove(id: UUID()))
    }

    func testUpdateReplacesByID() {
        var list = make(2)
        var changed = list.items[1]
        changed.model = "GigaChat-2-Max"
        list.update(changed)
        XCTAssertEqual(list.items[1].model, "GigaChat-2-Max")
        XCTAssertEqual(list.items.count, 2)
        list.update(LLMConnection(name: "чужое"))
        XCTAssertEqual(list.items.count, 2)
    }

    func testMoveChangesOrderNotSelection() {
        var list = make(3)
        let first = list.items[0], third = list.items[2]
        list.move(id: first.id, by: 1)
        XCTAssertEqual(list.items.map(\.name), ["Подключение 2", "Подключение 1", "Подключение 3"])
        XCTAssertEqual(list.active?.id, first.id, "выбранное подключение остаётся прежним")
        list.move(id: third.id, by: -1)
        XCTAssertEqual(list.items.map(\.name), ["Подключение 2", "Подключение 3", "Подключение 1"])
        // На краях и для чужого id — без изменений.
        list.move(id: list.items[0].id, by: -1)
        list.move(id: list.items[2].id, by: 1)
        list.move(id: UUID(), by: 1)
        XCTAssertEqual(list.items.map(\.name), ["Подключение 2", "Подключение 3", "Подключение 1"])
        // «+» переключает по новому порядку.
        var cycling = list
        cycling.setActive(cycling.items[0].id)
        XCTAssertEqual(cycling.cycle(by: 1)?.name, "Подключение 3")
    }

    func testSetActiveIgnoresUnknown() {
        var list = make(2)
        list.setActive(UUID())
        XCTAssertEqual(list.active?.name, "Подключение 1")
    }

    func testKeyAccountDefaultsToIDAndLegacyIsKept() {
        let connection = LLMConnection(name: "a")
        XCTAssertEqual(connection.keyAccount, "llm-" + connection.id.uuidString.lowercased())
        XCTAssertEqual(LLMConnection(name: "b", keyAccount: "gigachat-authorization-key").keyAccount, "gigachat-authorization-key")
    }

    func testJSONRoundTripAndBrokenData() throws {
        var list = make(3)
        list.setActive(list.items[2].id)
        let data = try XCTUnwrap(list.json())
        XCTAssertEqual(LLMConnections.decode(data), list)
        XCTAssertNil(LLMConnections.decode(nil))
        XCTAssertNil(LLMConnections.decode(Data("не json".utf8)))
    }

    func testDecodeTruncatesAndFixesActive() throws {
        let many = (1...12).map { LLMConnection(name: "n\($0)") }
        let raw = LLMConnections(items: many, activeID: UUID())
        XCTAssertEqual(raw.items.count, 10)
        XCTAssertEqual(raw.active?.name, "n1")
        let encoded = try JSONEncoder().encode(["items": many.map { ["id": $0.id.uuidString, "name": $0.name, "provider": "gigachat", "scope": "GIGACHAT_API_PERS", "model": "GigaChat", "keyAccount": $0.keyAccount] }])
        let decoded = try XCTUnwrap(LLMConnections.decode(encoded))
        XCTAssertEqual(decoded.items.count, 10)
        XCTAssertEqual(decoded.active?.name, "n1")
    }
}

final class NewBehaviorsTests: XCTestCase {
    private func makeEngine(scare: Bool = true, chase: Bool = false) -> BehaviorEngine {
        var config = BehaviorConfig()
        config.scareEnabled = scare
        config.chaseEnabled = chase
        config.sleepAfter = nil
        config.talkEnabled = false
        return BehaviorEngine(config: config, now: 0, random: { $0.lowerBound })
    }

    func testScareShakesAndSpeaks() {
        var engine = makeEngine()
        XCTAssertEqual(engine.handle(.scare, now: 1), [.shake, .say(.scared)])
        XCTAssertEqual(engine.mode, .reacting)
        XCTAssertEqual(engine.tick(now: 5, idleSeconds: 0), [.hideBubble])
    }

    func testScareInterruptsWanderAndHasCooldown() {
        var engine = makeEngine()
        _ = engine.tick(now: 60, idleSeconds: 1)
        XCTAssertEqual(engine.mode, .wandering)
        XCTAssertEqual(engine.handle(.scare, now: 61), [.stopWander, .shake, .say(.scared)])
        _ = engine.tick(now: 66, idleSeconds: 0)
        // Повторно пугается не раньше чем через 20 с.
        XCTAssertEqual(engine.handle(.scare, now: 70), [])
        XCTAssertEqual(engine.handle(.scare, now: 82), [.shake, .say(.scared)])
    }

    func testScareIgnoredWhenDisabledOrBusy() {
        var disabled = makeEngine(scare: false)
        XCTAssertEqual(disabled.handle(.scare, now: 1), [])

        var sleeping = makeEngine()
        _ = sleeping.handle(.nap(3600), now: 1)
        XCTAssertEqual(sleeping.handle(.scare, now: 2), [])

        var dragged = makeEngine()
        _ = dragged.handle(.dragBegan, now: 1)
        XCTAssertEqual(dragged.handle(.scare, now: 2), [])

        var console = makeEngine()
        console = {
            var config = BehaviorConfig()
            config.scareEnabled = true
            config.consoleEnabled = true
            return BehaviorEngine(config: config, now: 0, random: { $0.lowerBound })
        }()
        _ = console.handle(.doubleClick, now: 1)
        XCTAssertEqual(console.handle(.scare, now: 2), [])
    }

    func testChaseReplacesSomeWanders() {
        // Случайность подменена нижней границей (0): доля 0,3 выбирает подлёт к курсору.
        var chase = makeEngine(scare: false, chase: true)
        XCTAssertEqual(chase.tick(now: 60, idleSeconds: 1), [.startChase])
        XCTAssertEqual(chase.mode, .wandering)
        XCTAssertEqual(chase.handle(.arrived, now: 65), [])
        XCTAssertEqual(chase.mode, .idle)

        var plain = makeEngine(scare: false, chase: false)
        XCTAssertEqual(plain.tick(now: 60, idleSeconds: 1), [.startWander])

        // Случайность выше доли — обычный перелёт.
        var config = BehaviorConfig()
        config.chaseEnabled = true
        config.sleepAfter = nil
        config.talkEnabled = false
        var high = BehaviorEngine(config: config, now: 0, random: { $0.upperBound })
        XCTAssertEqual(high.tick(now: 180, idleSeconds: 1), [.startWander])
    }

    func testNewPhrases() {
        XCTAssertFalse(PhraseBook.pool(.scared, hour: 10).isEmpty)
        XCTAssertFalse(PhraseBook.pool(.curious, hour: 10).isEmpty)
        XCTAssertFalse(BehaviorConfig().scareEnabled)
        XCTAssertFalse(BehaviorConfig().chaseEnabled)
    }
}

final class LimitsTests: XCTestCase {
    func testTokenFormat() {
        XCTAssertEqual(TokenFormat.short(999), "999")
        XCTAssertEqual(TokenFormat.short(1_000), "1 ТЫС")
        XCTAssertEqual(TokenFormat.short(100_500), "100,5 ТЫС")
        XCTAssertEqual(TokenFormat.short(1_000_000), "1 МЛН")
        XCTAssertEqual(TokenFormat.short(12_345_678), "12,3 МЛН")
        XCTAssertEqual(TokenFormat.short(250_000_000), "250 МЛН")
        XCTAssertEqual(TokenFormat.short(0), "0")
    }

    func testGigaChatBalanceRequest() {
        let request = GigaChatAPI.balanceRequest(token: "tok")
        XCTAssertEqual(request.url?.absoluteString, "https://api.giga.chat/v1/balance")
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer tok")
        XCTAssertEqual(request.value(forHTTPHeaderField: "User-Agent"), "SinMinions")
    }

    func testGigaChatBalanceParsing() {
        // Как в настоящем аккаунте: остатки названы без номера поколения.
        let real = Data(#"{"balance":[{"usage":"GigaChat-Ultra","value":50000000},{"usage":"GigaChat-Pro","value":100500},{"usage":"GigaChat-Max","value":3000000},{"usage":"embeddings","value":7}]}"#.utf8)
        XCTAssertEqual(GigaChatAPI.parseBalance(real, model: "GigaChat-3-Ultra"), "50 МЛН")
        XCTAssertEqual(GigaChatAPI.parseBalance(real, model: "GigaChat-2-Pro"), "100,5 ТЫС")
        XCTAssertEqual(GigaChatAPI.parseBalance(real, model: "GigaChat-2-Max"), "3 МЛН")
        XCTAssertEqual(GigaChatAPI.parseBalance(real, model: "gigachat-max"), "3 МЛН")
        // Записи для модели нет, а записей несколько — чужие числа не показываем.
        XCTAssertNil(GigaChatAPI.parseBalance(real, model: "GigaChat"))
        let lite = Data(#"{"balance":[{"usage":"GigaChat","value":250000000},{"usage":"embeddings","value":3000000}]}"#.utf8)
        XCTAssertEqual(GigaChatAPI.parseBalance(lite, model: "GigaChat-2"), "250 МЛН")
        XCTAssertEqual(GigaChatAPI.parseBalance(lite, model: "GigaChat"), "250 МЛН")
        let one = Data(#"{"balance":[{"usage":"GigaChat-Pro","value":2500000}]}"#.utf8)
        XCTAssertEqual(GigaChatAPI.parseBalance(one, model: "GigaChat-2-Max"), "2,5 МЛН")
        XCTAssertNil(GigaChatAPI.parseBalance(Data(#"{"balance":[]}"#.utf8), model: "GigaChat"))
        XCTAssertNil(GigaChatAPI.parseBalance(Data("не json".utf8), model: "GigaChat"))
        XCTAssertNil(GigaChatAPI.parseBalance(Data(#"{"balance":[{"usage":"x"}]}"#.utf8), model: "GigaChat"))
    }

    func testCanonicalModelNames() {
        XCTAssertEqual(GigaChatAPI.canonicalModel("GigaChat-2-Pro"), "gigachat-pro")
        XCTAssertEqual(GigaChatAPI.canonicalModel("GigaChat-2-Max"), "gigachat-max")
        XCTAssertEqual(GigaChatAPI.canonicalModel("GigaChat-3-Ultra"), "gigachat-ultra")
        XCTAssertEqual(GigaChatAPI.canonicalModel("GigaChat-2"), "gigachat")
        XCTAssertEqual(GigaChatAPI.canonicalModel("GigaChat"), "gigachat")
        XCTAssertEqual(GigaChatAPI.canonicalModel("deepseek-v4-pro"), "deepseek-v4-pro")
    }

    func testDeepSeekSummary() {
        let two = Data(#"{"is_available":true,"balance_infos":[{"currency":"CNY","total_balance":"110.00"},{"currency":"USD","total_balance":"5.00"}]}"#.utf8)
        XCTAssertEqual(DeepSeekAPI.balanceSummary(two), "110.00 CNY, 5.00 USD")
        XCTAssertNil(DeepSeekAPI.balanceSummary(Data(#"{"balance_infos":[]}"#.utf8)))
    }

    func testShortErrorDescriptions() {
        XCTAssertEqual(LLMError.http(403, nil, .chat).shortDescription, "недоступно")
        XCTAssertEqual(LLMError.http(401, nil, .direct).shortDescription, "ключ не принят")
        XCTAssertEqual(LLMError.http(402, nil, .direct).shortDescription, "нет средств")
        XCTAssertEqual(LLMError.http(503, nil, .direct).shortDescription, "сбой сервиса")
        XCTAssertEqual(LLMError.network("x").shortDescription, "нет связи")
        XCTAssertEqual(LLMError.noCredentials.shortDescription, "нет ключа")
        // Строка лимита на мониторе узкая: пояснение не длиннее 14 знаков.
        let all: [LLMError] = [.noCredentials, .http(401, nil, .chat), .http(402, nil, .chat), .http(403, nil, .chat), .http(429, nil, .chat),
                               .http(503, nil, .chat), .http(418, nil, .chat), .network("n"), .invalidResponse, .emptyAnswer]
        for error in all {
            XCTAssertLessThanOrEqual(error.shortDescription.count, 14, error.shortDescription)
        }
    }
}

final class DeepSeekAPITests: XCTestCase {
    func testChatRequestShape() throws {
        let request = DeepSeekAPI.chatRequest(key: "sk-abc", model: "deepseek-flash", messages: [ChatMessage(.system, "кратко"), ChatMessage(.user, "привет")])
        XCTAssertEqual(request.url?.absoluteString, "https://api.deepseek.com/chat/completions")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer sk-abc")
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
        XCTAssertEqual(body["model"] as? String, "deepseek-flash")
        XCTAssertEqual(body["stream"] as? Bool, false)
        XCTAssertEqual((body["thinking"] as? [String: String])?["type"], "disabled")
        XCTAssertEqual((body["messages"] as? [[String: String]])?.count, 2)
    }

    func testBalanceRequestAndParsing() throws {
        let request = DeepSeekAPI.balanceRequest(key: "sk-abc")
        XCTAssertEqual(request.url?.absoluteString, "https://api.deepseek.com/user/balance")
        XCTAssertEqual(request.httpMethod, "GET")
        let ok = #"{"is_available":true,"balance_infos":[{"currency":"CNY","total_balance":"110.00","granted_balance":"10.00","topped_up_balance":"100.00"}]}"#
        XCTAssertEqual(DeepSeekAPI.parseBalance(Data(ok.utf8)), "баланс 110.00 CNY")
        let empty = #"{"is_available":false,"balance_infos":[{"currency":"USD","total_balance":"0.00"}]}"#
        XCTAssertEqual(DeepSeekAPI.parseBalance(Data(empty.utf8)), "баланс 0.00 USD (недостаточно для запросов)")
        XCTAssertNil(DeepSeekAPI.parseBalance(Data("не json".utf8)))
        XCTAssertNil(DeepSeekAPI.parseBalance(Data(#"{"balance_infos":[]}"#.utf8)))
    }

    func testNormalizedKey() {
        XCTAssertEqual(DeepSeekAPI.normalizedKey("  Bearer sk-abc\n"), "sk-abc")
        XCTAssertEqual(DeepSeekAPI.normalizedKey("sk-abc"), "sk-abc")
        XCTAssertNil(DeepSeekAPI.normalizedKey("Bearer "))
        XCTAssertNil(DeepSeekAPI.normalizedKey("  "))
    }

    func testReasoningContentIsIgnored() throws {
        let json = #"{"choices":[{"message":{"role":"assistant","content":" ответ ","reasoning_content":"рассуждение"},"finish_reason":"stop"}]}"#
        XCTAssertEqual(try LLMResponse.parseChat(Data(json.utf8)), "ответ")
        // Пустые строки перед JSON (сервер шлёт их, пока модель думает) разбору не мешают.
        XCTAssertEqual(try LLMResponse.parseChat(Data(("\n\n\n" + json).utf8)), "ответ")
    }

    func testErrorDetailShapes() {
        XCTAssertEqual(LLMResponse.errorDetail(Data(#"{"error":{"message":"Authentication Fails","type":"authentication_error"}}"#.utf8)), "Authentication Fails")
        XCTAssertEqual(LLMResponse.errorDetail(Data(#"{"error":"bad"}"#.utf8)), "bad")
        XCTAssertEqual(LLMResponse.errorDetail(Data(#"{"message":"x"}"#.utf8)), "x")
        XCTAssertNil(LLMResponse.errorDetail(Data("<html>".utf8)))
    }

    func testDirectErrorTexts() {
        XCTAssertEqual(LLMError.http(401, nil, .direct).errorDescription, "Ключ API не подходит")
        XCTAssertEqual(LLMError.http(402, "Insufficient Balance", .direct).errorDescription, "Недостаточно средств на балансе — Insufficient Balance")
        XCTAssertEqual(LLMError.http(503, nil, .direct).errorDescription, "Сервис перегружен, попробуйте позже")
    }

    func testProviderCatalog() {
        XCTAssertEqual(LLMProvider.allCases, [.gigachat, .deepseek, .claude, .gpt, .grok, .gemini])
        XCTAssertEqual(LLMProvider.deepseek.defaultModel, "deepseek-flash")
        XCTAssertFalse(LLMProvider.deepseek.usesScope)
        XCTAssertTrue(LLMProvider.gigachat.usesScope)
        XCTAssertEqual(LLMConnection(name: "d", provider: .deepseek).model, "deepseek-flash")
        XCTAssertEqual(LLMConnection(name: "g").model, "GigaChat")
        XCTAssertTrue(GigaChatAPI.models.contains("GigaChat-3-Ultra"))
        XCTAssertEqual(LLMProvider.deepseek.normalizedKey("Bearer k"), "k")
        XCTAssertEqual(LLMProvider.gigachat.normalizedKey("Basic k"), "k")
    }
}

final class PhraseBookTests: XCTestCase {
    func testHasAtLeastFortyPhrases() {
        let ambient = PhraseBook.general + PhraseBook.morning + PhraseBook.day + PhraseBook.evening + PhraseBook.night
        XCTAssertGreaterThanOrEqual(ambient.count, 40)
        XCTAssertEqual(Set(ambient).count, ambient.count, "реплики не должны дублироваться")
    }

    func testPhrasesFitTheBubble() {
        let all = PhraseBook.general + PhraseBook.morning + PhraseBook.day + PhraseBook.evening + PhraseBook.night
            + PhraseBook.byKind.values.flatMap { $0 }
        for phrase in all {
            XCTAssertLessThanOrEqual(phrase.count, 60, phrase)
        }
    }

    func testEveryKindHasPhrases() {
        for kind in PhraseKind.allCases {
            XCTAssertFalse(PhraseBook.pool(kind, hour: 10).isEmpty, kind.rawValue)
        }
    }

    func testNoRepeatsUntilDeckIsExhausted() {
        var book = PhraseBook()
        let size = PhraseBook.pool(.ambient, hour: 10).count
        var seen = Set<String>()
        for _ in 0..<size { seen.insert(book.next(.ambient, hour: 10)) }
        XCTAssertEqual(seen.count, size)
    }

    func testNoImmediateRepeatAcrossDecks() {
        var book = PhraseBook(shuffle: { $0 })
        let size = PhraseBook.pool(.charging, hour: 10).count
        var previous = ""
        for _ in 0..<(size * 3) {
            let phrase = book.next(.charging, hour: 10)
            XCTAssertNotEqual(phrase, previous)
            previous = phrase
        }
    }

    func testTimeOfDay() {
        XCTAssertEqual(PhraseBook.timeOfDay(hour: 8), PhraseBook.morning)
        XCTAssertEqual(PhraseBook.timeOfDay(hour: 14), PhraseBook.day)
        XCTAssertEqual(PhraseBook.timeOfDay(hour: 20), PhraseBook.evening)
        XCTAssertEqual(PhraseBook.timeOfDay(hour: 2), PhraseBook.night)
    }
}

final class SpotlightHotkeyTests: XCTestCase {
    private func table(enabled: Bool, parameters: [Int]) -> [String: Any] {
        ["64": ["enabled": enabled, "value": ["parameters": parameters, "type": "standard"]]]
    }

    func testDefaultsToCommandSpaceWhenNothingStored() {
        XCTAssertEqual(SpotlightHotkey.resolve(symbolicHotKeys: nil), .hotkey(Hotkey(keyCode: 49, flags: 0x100000)))
        XCTAssertEqual(SpotlightHotkey.resolve(symbolicHotKeys: [:]), .hotkey(SpotlightHotkey.standard))
    }

    func testReadsCustomHotkey() {
        // ⌃⌥Пробел
        let custom = table(enabled: true, parameters: [32, 49, 786432])
        XCTAssertEqual(
            SpotlightHotkey.resolve(symbolicHotKeys: custom),
            .hotkey(Hotkey(keyCode: 49, flags: SpotlightHotkey.control | SpotlightHotkey.option))
        )
    }

    func testDisabledHotkey() {
        XCTAssertEqual(SpotlightHotkey.resolve(symbolicHotKeys: table(enabled: false, parameters: [32, 49, 1048576])), .disabled)
    }

    func testBrokenEntryFallsBackToStandard() {
        XCTAssertEqual(SpotlightHotkey.resolve(symbolicHotKeys: table(enabled: true, parameters: [32])), .hotkey(SpotlightHotkey.standard))
        XCTAssertEqual(SpotlightHotkey.resolve(symbolicHotKeys: table(enabled: true, parameters: [65535, 65535, 0])), .hotkey(SpotlightHotkey.standard))
    }
}

final class LayoutTests: XCTestCase {
    private let area = CGRect(x: 0, y: 80, width: 1440, height: 795)
    private let size = CGSize(width: 76, height: 121)

    func testClampKeepsWindowInsideArea() {
        XCTAssertEqual(Layout.clamp(origin: CGPoint(x: -50, y: 0), size: size, in: area), CGPoint(x: 0, y: 80))
        XCTAssertEqual(Layout.clamp(origin: CGPoint(x: 5000, y: 5000), size: size, in: area), CGPoint(x: 1364, y: 754))
        XCTAssertEqual(Layout.clamp(origin: CGPoint(x: 300, y: 300), size: size, in: area), CGPoint(x: 300, y: 300))
    }

    func testCornerIsBottomRight() {
        XCTAssertEqual(Layout.corner(size: size, in: area), CGPoint(x: 1336, y: 108))
    }

    func testRandomTargetStaysInsideArea() {
        for _ in 0..<200 {
            let target = Layout.randomTarget(size: size, in: area, from: CGPoint(x: 700, y: 400))
            XCTAssertTrue(area.contains(CGRect(origin: target, size: size)))
        }
    }

    func testRandomTargetMovesAway() {
        var values = [0.5, 0.5, 0.9, 0.9].makeIterator()
        let from = CGPoint(x: 682, y: 417)
        let target = Layout.randomTarget(size: size, in: area, from: from, random: { _ in values.next() ?? 0 })
        XCTAssertGreaterThanOrEqual(hypot(target.x - from.x, target.y - from.y), 160)
    }

    func testBubbleAboveWhenThereIsRoom() {
        let moth = CGRect(x: 600, y: 300, width: 72, height: 84)
        let placement = Layout.bubble(size: CGSize(width: 160, height: 40), over: moth, in: area)
        XCTAssertFalse(placement.below)
        XCTAssertEqual(placement.origin, CGPoint(x: 556, y: 388))
        XCTAssertEqual(placement.tailX, 80)
    }

    func testBubbleBelowAtTopEdgeAndClampedAtSide() {
        let moth = CGRect(x: 1380, y: 780, width: 60, height: 90)
        let placement = Layout.bubble(size: CGSize(width: 160, height: 40), over: moth, in: area)
        XCTAssertTrue(placement.below)
        XCTAssertEqual(placement.origin, CGPoint(x: 1280, y: 736))
        XCTAssertEqual(placement.tailX, 130)
    }

    func testEase() {
        XCTAssertEqual(Layout.ease(0), 0)
        XCTAssertEqual(Layout.ease(1), 1)
        XCTAssertEqual(Layout.ease(0.5), 0.5)
        XCTAssertEqual(Layout.ease(2), 1)
    }
}

final class UpdatesTests: XCTestCase {
    func testVersionComparison() {
        XCTAssertTrue(AppVersion("v0.1.0")! < AppVersion("0.2")!)
        XCTAssertEqual(AppVersion("1.0.0"), AppVersion("v1"))
        XCTAssertNil(AppVersion("abc"))
    }

    func testFeedPointsAtSinMinionsRepository() {
        XCTAssertEqual(ReleaseFeed.latestURL.absoluteString, "https://api.github.com/repos/claudesiniakov/sinminions/releases/latest")
        XCTAssertEqual(ReleaseFeed.archiveName, "SinMinions.zip")
    }

    func testParsesReleaseAndRejectsForeignDownloads() throws {
        let json = """
        {"tag_name":"v0.2.0","name":"","body":"Заметки","html_url":"https://github.com/claudesiniakov/sinminions/releases/tag/v0.2.0",
         "assets":[
          {"name":"SinMinions.zip","browser_download_url":"https://github.com/claudesiniakov/sinminions/releases/download/v0.2.0/SinMinions.zip","size":123},
          {"name":"SinMinions.zip.sha256","browser_download_url":"https://github.com/claudesiniakov/sinminions/releases/download/v0.2.0/SinMinions.zip.sha256","size":80}]}
        """
        let release = try ReleaseFeed.parse(Data(json.utf8))
        XCTAssertEqual(release.version, AppVersion("0.2.0"))
        XCTAssertEqual(release.archiveSize, 123)
        XCTAssertNotNil(release.checksumURL)

        let foreign = json.replacingOccurrences(of: "github.com/claudesiniakov/sinminions/releases/download", with: "example.com/x")
        XCTAssertThrowsError(try ReleaseFeed.parse(Data(foreign.utf8)))
    }

    func testChecksumParsing() {
        let hex = String(repeating: "ab", count: 32)
        XCTAssertEqual(UpdateVerifier.parseChecksum("\(hex)  SinMinions.zip\n"), hex)
        XCTAssertNil(UpdateVerifier.parseChecksum("not a hash"))
    }
}
