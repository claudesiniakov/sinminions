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

    func testConsoleLayout() {
        let area = CGRect(x: 0, y: 80, width: 1440, height: 800)
        let place = Layout.console(
            moth: CGSize(width: 72, height: 84), terminal: CGSize(width: 400, height: 250),
            monitor: CGSize(width: 300, height: 350), in: area
        )
        // Призрак по центру, терминал под ним по центру, монитор справа, верх — на уровне призрака.
        XCTAssertEqual(place.moth, CGPoint(x: 684, y: 571))
        XCTAssertEqual(place.terminal, CGPoint(x: 520, y: 305))
        XCTAssertEqual(place.monitor, CGPoint(x: 936, y: 305))
    }

    func testMonitorGoesLeftWhenNoRoomOnTheRight() {
        let area = CGRect(x: 0, y: 0, width: 900, height: 700)
        let place = Layout.console(
            moth: CGSize(width: 72, height: 84), terminal: CGSize(width: 400, height: 250),
            monitor: CGSize(width: 300, height: 350), in: area
        )
        XCTAssertLessThan(place.monitor.x, place.terminal.x)
        XCTAssertGreaterThanOrEqual(place.monitor.x, 0)
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
