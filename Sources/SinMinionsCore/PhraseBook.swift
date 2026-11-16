import Foundation

/// Набор реплик компаньона и перебор без повторов.
public struct PhraseBook {
    /// Тон — терминал из claudesiniakov/summary: первые десять фраз взяты оттуда как есть.
    public static let general: [String] = [
        "всё под контролем",
        "радиация в норме",
        "слежу за периметром",
        "war never changes",
        "тихо как в Vault 13",
        "сканирую угрозы...",
        "периметр чист",
        "где-то есть Nuka-Cola",
        "не смотри на меня",
        "хороший рабочий стол",
        "окон многовато, смотритель",
        "курсор покинул убежище",
        "счётчик Гейгера молчит",
        "крышек хватит на всё",
        "терминал отвечает",
        "я ничего не трогал",
        "вкладок меньше не стало",
        "в корзине что-то шевелится",
        "давно не сохраняли",
        "тишина — тоже работа",
        "я на посту",
        "пип-бой бы не помешал",
        "буквы, буквы, буквы",
        "этот сектор ещё не разведан",
        "делаю вид, что занят",
        "проверил: всё на месте",
        "строка меню под охраной",
        "слышал щелчок. показалось",
        "дрейфую потихоньку",
        "здесь был Moth",
        "реактор не шумит, хорошо",
        "место на диске ещё есть",
        "никуда не тороплюсь",
        "связь с убежищем стабильна",
    ]

    public static let morning = ["доброе утро, смотритель", "утро. пустошь ещё спит", "кофе не забудь", "новый день, те же окна"]
    public static let day = ["день идёт", "обед не пропусти", "середина дня, держимся", "работаем потихоньку"]
    public static let evening = ["уже вечер", "пора закругляться", "вечером тут спокойнее", "смена почти кончилась"]
    public static let night = ["поздно уже", "ночью экран светит как реактор", "я не сплю. а ты", "спать не пора"]

    public static let byKind: [PhraseKind: [String]] = [
        .click: [
            "ура!", "кликнул!", "я здесь!", "привет!", "♥", "ой", "что",
            "два щелчка — и будет поиск",
        ],
        .charging: ["о, питание", "энергия пошла", "ядерная батарея на месте"],
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
