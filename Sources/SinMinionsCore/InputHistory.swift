import Foundation

/// История отправленных реплик для стрелок ↑/↓ в строке ввода.
///
/// Хранит последние `limit` строк. Указатель живёт между вызовами: пока пользователь
/// листает историю, `older`/`newer` возвращают предыдущую и следующую реплику; когда
/// листание доходит до конца, возвращается `nil` — значит, строку можно очистить.
public struct InputHistory: Equatable, Sendable {
    public static let limit = 50

    public private(set) var entries: [String] = []
    /// Позиция в истории; nil — пользователь ещё не листал (поле содержит свой текст).
    public private(set) var index: Int?

    public init() {}

    /// Добавляет отправленную строку и сбрасывает листание.
    public mutating func remember(_ text: String) {
        let line = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !line.isEmpty else { return }
        // Повтор той же строки не дублируем: ↑ после одинаковых вопросов бесполезен.
        if entries.last == line {
            index = nil
            return
        }
        entries.append(line)
        if entries.count > Self.limit { entries.removeFirst(entries.count - Self.limit) }
        index = nil
    }

    /// Предыдущая (более старая) реплика; nil — листать нечего.
    public mutating func older() -> String? {
        guard !entries.isEmpty else { return nil }
        let next = (index ?? entries.count) - 1
        index = max(next, 0)
        return entries[index ?? 0]
    }

    /// Следующая (более новая) реплика; nil — дошли до конца, поле можно очистить.
    public mutating func newer() -> String? {
        guard let current = index else { return nil }
        if current + 1 >= entries.count {
            index = nil
            return nil
        }
        index = current + 1
        return entries[current + 1]
    }

    /// Черновик, который был в поле до листания: возвращаем его, когда дошли до конца.
    public mutating func reset() {
        index = nil
    }
}
