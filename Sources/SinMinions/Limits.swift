import Foundation
import Observation
import SinMinionsCore

/// Лимиты по подключениям к нейросетям для блока на мониторе: остаток токенов или средств.
/// Запросы идут при открытии терминала, не чаще раза в минуту; последовательно, по одному.
@MainActor
@Observable
final class LimitsStore {
    enum State: Equatable {
        case loading
        case value(String)
        case failed(String)
        case noKey
        /// У провайдера нет способа узнать остаток по обычному ключу.
        case unsupported
    }

    struct Entry: Equatable {
        var signature: String
        var state: State
    }

    private(set) var entries: [UUID: Entry] = [:]

    /// Как получить лимит подключения по его ключу; задаётся приложением.
    @ObservationIgnored var fetch: @MainActor (LLMConnection, String) async throws -> String? = { _, _ in nil }
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var running = false
    @ObservationIgnored private var lastFull: Date?
    @ObservationIgnored private let demo = ProcessInfo.processInfo.environment["SINMINIONS_DEMO"] != nil

    /// Подпись настроек, от которых зависит значение: после смены модели или ключа лимит запрашивается заново.
    static func signature(_ connection: LLMConnection) -> String {
        "\(connection.provider.rawValue)|\(connection.scope)|\(connection.model)|\(connection.keyAccount)"
    }

    func state(for connection: LLMConnection) -> State? {
        guard let entry = entries[connection.id], entry.signature == Self.signature(connection) else { return nil }
        return entry.state
    }

    func refresh(_ connections: [LLMConnection]) {
        entries = entries.filter { entry in connections.contains { $0.id == entry.key } }
        if demo {
            loadDemo(connections)
            return
        }
        let stale = lastFull.map { Date().timeIntervalSince($0) >= 60 } ?? true
        let targets = connections.filter { connection in
            let current = state(for: connection)
            // Запрос уже идёт — его не прерываем ради тех, у кого пока «загрузка».
            return stale || current == nil || (current == .loading && !running)
        }
        guard !targets.isEmpty else { return }
        if stale { lastFull = Date() }
        task?.cancel()
        for connection in targets where state(for: connection) == nil {
            entries[connection.id] = Entry(signature: Self.signature(connection), state: .loading)
        }
        running = true
        task = Task { [weak self] in
            for connection in targets {
                guard let self, !Task.isCancelled else { break }
                await self.load(connection)
            }
            self?.running = false
        }
    }

    private func load(_ connection: LLMConnection) async {
        let signature = Self.signature(connection)
        guard connection.provider.supportsLimits else {
            set(connection, signature, .unsupported)
            return
        }
        guard Keychain.exists(connection.keyAccount), let key = Keychain.read(connection.keyAccount) else {
            set(connection, signature, .noKey)
            return
        }
        do {
            let text = try await fetch(connection, key)
            set(connection, signature, text.map { State.value($0) } ?? .failed("нет данных"))
        } catch is CancellationError {
            return
        } catch {
            set(connection, signature, .failed((error as? LLMError)?.shortDescription ?? "ошибка"))
        }
    }

    private func set(_ connection: LLMConnection, _ signature: String, _ state: State) {
        entries[connection.id] = Entry(signature: signature, state: state)
    }

    /// Для снимков в CI: готовые значения без обращения к сети.
    private func loadDemo(_ connections: [LLMConnection]) {
        let values = ["100,5 ТЫС", "3 МЛН", "110.00 CNY"]
        for (index, connection) in connections.enumerated() {
            set(connection, Self.signature(connection), .value(values[index % values.count]))
        }
    }
}
