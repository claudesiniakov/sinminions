import Foundation

/// Находки призрака после поиска. Каждая рисуется отдельной картинкой рядом с ним.
public enum SearchFind: CaseIterable, Sendable {
    case waterChip, holotape, bottleCap, stimpak

    public var title: String {
        switch self {
        case .waterChip: return "ВОДЯНОЙ ЧИП"
        case .holotape: return "ГОЛОЗАПИСЬ"
        case .bottleCap: return "КРЫШКА"
        case .stimpak: return "СТИМПАК"
        }
    }

    /// Реплики при находке: спокойные, с радостью, что есть запас.
    public var phrases: [String] {
        switch self {
        case .waterChip: return ["водяной чип! выдохни: вода в запасе", "нашёл водяной чип. запас есть, можно не волноваться", "водяной чип на месте. теперь спокойно"]
        case .holotape: return ["голозапись! потом послушаем", "нашёл голозапись. пусть полежит про запас"]
        case .bottleCap: return ["крышка! копится на чёрный день", "нашёл крышку. запас — это хорошо"]
        case .stimpak: return ["стимпак! теперь есть чем подлататься", "нашёл стимпак. на всякий случай пусть будет"]
        }
    }

    /// Случайная находка; водяной чип выпадает чаще остальных.
    public static func pick(_ random: (ClosedRange<Double>) -> Double = { Double.random(in: $0) }) -> SearchFind {
        let roll = random(0...1)
        if roll < 0.5 { return .waterChip }
        let others: [SearchFind] = [.holotape, .bottleCap, .stimpak]
        let index = min(Int((roll - 0.5) / 0.5 * Double(others.count)), others.count - 1)
        return others[index]
    }
}
