import Foundation

/// Находки призрака после поиска. Каждая рисуется отдельной картинкой рядом с ним.
public enum SearchFind: CaseIterable, Sendable {
    case waterChip, holotape, bottleCap, stimpak
    /// Реликвии Империума: их ищет золотой страж.
    case aquila, purityScroll, goldenSkull, chalice

    /// Реликвия ли это (находка стража, а не призрака).
    public var isRelic: Bool {
        switch self {
        case .aquila, .purityScroll, .goldenSkull, .chalice: return true
        default: return false
        }
    }

    public var title: String {
        switch self {
        case .waterChip: return "ВОДЯНОЙ ЧИП"
        case .holotape: return "ГОЛОЗАПИСЬ"
        case .bottleCap: return "КРЫШКА"
        case .stimpak: return "СТИМПАК"
        case .aquila: return "АКВИЛА"
        case .purityScroll: return "СВИТОК С ПЕЧАТЬЮ ЧИСТОТЫ"
        case .goldenSkull: return "ЗОЛОЧЁНЫЙ ЧЕРЕП"
        case .chalice: return "СВЯТАЯ ЧАША"
        }
    }

    /// Реплики при находке: спокойные, с радостью, что есть запас.
    public var phrases: [String] {
        switch self {
        case .waterChip: return ["водяной чип! выдохни: вода в запасе", "нашёл водяной чип. запас есть, можно не волноваться", "водяной чип на месте. теперь спокойно"]
        case .holotape: return ["голозапись! потом послушаем", "нашёл голозапись. пусть полежит про запас"]
        case .bottleCap: return ["крышка! копится на чёрный день", "нашёл крышку. запас — это хорошо"]
        case .stimpak: return ["стимпак! теперь есть чем подлататься", "нашёл стимпак. на всякий случай пусть будет"]
        case .aquila: return ["аквила! реликвия Империума найдена", "золотой орёл. слава Императору", "нашёл аквилу. пост стал святее"]
        case .purityScroll: return ["свиток с печатью чистоты. хранить свято", "печать чистоты найдена. молитва в запасе", "древний свиток. пусть хранится у меня"]
        case .goldenSkull: return ["золочёный череп. реликвия павшего героя", "священный череп. храню как святыню", "нашёл череп героя. покойся с честью"]
        case .chalice: return ["чаша из давних времён. реликвия", "священный кубок найден", "святая чаша. пусть будет в запасе"]
        }
    }

    /// Случайная находка. У призрака водяной чип выпадает чаще остальных; золотой страж ищет только реликвии Империума,
    /// чаще всего аквилу.
    public static func pick(for character: CompanionCharacter = .f, _ random: (ClosedRange<Double>) -> Double = { Double.random(in: $0) }) -> SearchFind {
        let roll = random(0...1)
        if character == .ab {
            if roll < 0.4 { return .aquila }
            let others: [SearchFind] = [.purityScroll, .goldenSkull, .chalice]
            let index = min(Int((roll - 0.4) / 0.6 * Double(others.count)), others.count - 1)
            return others[index]
        }
        if roll < 0.5 { return .waterChip }
        let others: [SearchFind] = [.holotape, .bottleCap, .stimpak]
        let index = min(Int((roll - 0.5) / 0.5 * Double(others.count)), others.count - 1)
        return others[index]
    }
}
