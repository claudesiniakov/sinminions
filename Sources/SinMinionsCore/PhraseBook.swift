import Foundation

/// Набор реплик компаньона и перебор без повторов.
public struct PhraseBook {
    public static let general: [String] = [
        "всё под контролем",
        "тихо тут сегодня",
        "я слежу",
        "хороший рабочий стол",
        "а я тут летаю",
        "не обращай внимания",
        "окон многовато",
        "курсор опять убежал",
        "мне отсюда всё видно",
        "просто пролетал мимо",
        "тут уютно",
        "интересно, что там в корзине",
        "я ничего не трогал",
        "вкладок меньше не стало",
        "пыль на экране — не моя",
        "люблю этот угол",
        "что-то давно не сохраняли",
        "тишина — тоже работа",
        "я на посту",
        "красивые обои",
        "буквы, буквы, буквы",
        "а вот тут я ещё не был",
        "делаю вид, что занят",
        "проверил: всё на месте",
        "строка меню сегодня в порядке",
        "мне нравится, как ты печатаешь",
        "кажется, я что-то слышал",
        "парю потихоньку",
        "тут был я",
        "вентиляторов не слышно, хорошо",
        "место на диске ещё есть",
        "никуда не тороплюсь",
    ]

    public static let morning = ["доброе утро", "утро, а я уже тут", "кофе не забудь", "новый день, те же окна"]
    public static let day = ["день идёт", "обед не пропусти", "середина дня, держимся", "работаем потихоньку"]
    public static let evening = ["уже вечер", "пора бы закругляться", "вечером тут спокойнее", "день почти кончился"]
    public static let night = ["поздно уже", "ночью экран ярче кажется", "я не сплю, а ты", "спать не пора"]

    public static let byKind: [PhraseKind: [String]] = [
        .click: [
            "ой", "щекотно", "я тут", "что", "да-да", "привет", "не тыкай",
            "два щелчка — и будет поиск",
        ],
        .charging: ["о, зарядка", "питание пошло", "так-то лучше"],
        .lowBattery: ["заряда маловато", "пора искать розетку", "батарея просит есть"],
        .wake: ["с возвращением", "о, проснулись", "я тут всё сторожил"],
        .updateAvailable: ["вышла новая версия", "есть обновление — загляни в меню", "меня можно обновить"],
        .needAccess: ["для поиска нужен «Универсальный доступ»", "разреши мне нажимать клавиши — открою поиск"],
        .spotlightOff: ["сочетание Spotlight выключено в настройках системы"],
    ]

    public static func timeOfDay(hour: Int) -> [String] {
        switch hour {
        case 6..<12: return morning
        case 12..<18: return day
        case 18..<23: return evening
        default: return night
        }
    }

    public static func pool(_ kind: PhraseKind, hour: Int) -> [String] {
        kind == .ambient ? general + timeOfDay(hour: hour) : (byKind[kind] ?? general)
    }

    private var decks: [String: [String]] = [:]
    private var last: String?
    private let shuffle: ([String]) -> [String]

    public init(shuffle: @escaping ([String]) -> [String] = { $0.shuffled() }) {
        self.shuffle = shuffle
    }

    /// Следующая реплика: внутри одного повода фразы не повторяются, пока не пройден весь набор.
    public mutating func next(_ kind: PhraseKind, hour: Int) -> String {
        let key = kind == .ambient ? "ambient-\(Self.timeOfDay(hour: hour).first ?? "")" : kind.rawValue
        var deck = decks[key] ?? []
        if deck.isEmpty {
            deck = shuffle(Self.pool(kind, hour: hour))
            // Новая колода не должна начинаться с только что сказанного.
            if deck.count > 1, deck.last == last { deck.swapAt(0, deck.count - 1) }
        }
        let phrase = deck.removeLast()
        decks[key] = deck
        last = phrase
        return phrase
    }
}
