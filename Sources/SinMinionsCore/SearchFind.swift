import Foundation

/// Находки компаньонов. У каждого предмета есть рисунок и реплики.
public enum SearchFind: CaseIterable, Sendable {
    case waterChip, holotape, bottleCap, stimpak
    /// Реликвии Империума: их ищет золотой страж.
    case aquila, purityScroll, goldenSkull, chalice
    case campaignBrief, metricsChart, megaphone, hypothesisNote

    private static let marketingFinds: [SearchFind] = [.campaignBrief, .metricsChart, .megaphone, .hypothesisNote]

    public var isMarketingFind: Bool { Self.marketingFinds.contains(self) }

    /// Реликвия ли это (находка стража, а не призрака).
    public var isRelic: Bool {
        switch self {
        case .aquila, .purityScroll, .goldenSkull, .chalice: return true
        default: return false
        }
    }

    public var title: String {
        switch self {
        case .waterChip: return tr("ВОДЯНОЙ ЧИП")
        case .holotape: return tr("ГОЛОЗАПИСЬ")
        case .bottleCap: return tr("КРЫШКА")
        case .stimpak: return tr("СТИМПАК")
        case .aquila: return tr("АКВИЛА")
        case .purityScroll: return tr("СВИТОК С ПЕЧАТЬЮ ЧИСТОТЫ")
        case .goldenSkull: return tr("ЗОЛОЧЁНЫЙ ЧЕРЕП")
        case .chalice: return tr("СВЯТАЯ ЧАША")
        case .campaignBrief: return tr("БРИФ КАМПАНИИ")
        case .metricsChart: return tr("ГРАФИК МЕТРИК")
        case .megaphone: return tr("МЕГАФОН")
        case .hypothesisNote: return tr("СТИКЕР С ГИПОТЕЗОЙ")
        }
    }

    /// Реплики при находке: спокойные, с радостью, что есть запас.
    public var phrases: [String] {
        switch self {
        case .waterChip: return [tr("водяной чип! выдохни: вода в запасе"), tr("нашёл водяной чип. запас есть, можно не волноваться"), tr("водяной чип на месте. теперь спокойно")]
        case .holotape: return [tr("голозапись! потом послушаем"), tr("нашёл голозапись. пусть полежит про запас")]
        case .bottleCap: return [tr("крышка! копится на чёрный день"), tr("нашёл крышку. запас — это хорошо")]
        case .stimpak: return [tr("стимпак! теперь есть чем подлататься"), tr("нашёл стимпак. на всякий случай пусть будет")]
        case .aquila: return [tr("аквила! реликвия Империума найдена"), tr("золотой орёл. слава Императору"), tr("нашёл аквилу. пост стал святее")]
        case .purityScroll: return [tr("свиток с печатью чистоты. хранить свято"), tr("печать чистоты найдена. молитва в запасе"), tr("древний свиток. пусть хранится у меня")]
        case .goldenSkull: return [tr("золочёный череп. реликвия павшего героя"), tr("священный череп. храню как святыню"), tr("нашёл череп героя. покойся с честью")]
        case .chalice: return [tr("чаша из давних времён. реликвия"), tr("священный кубок найден"), tr("святая чаша. пусть будет в запасе")]
        case .campaignBrief: return [tr("бриф на месте! начнём с цели"), tr("нашла бриф. посмотрим, для кого кампания")]
        case .metricsChart: return [tr("нашла график! посмотрим, где выросла конверсия"), tr("график метрик! есть что обсудить")]
        case .megaphone: return [tr("мегафон! пора рассказать о запуске"), tr("нашла мегафон. какое сообщение передаём?")]
        case .hypothesisNote: return [tr("нашла стикер с гипотезой. проверим её?"), tr("о, идея для следующего A/B-теста!")]
        }
    }

    /// Случайная находка. У призрака водяной чип выпадает чаще остальных; золотой страж ищет только реликвии Империума,
    /// чаще всего аквилу.
    public static func pick(for character: CompanionCharacter = .f, _ random: (ClosedRange<Double>) -> Double = { Double.random(in: $0) }) -> SearchFind {
        let roll = random(0...1)
        if character == .v {
            let index = min(Int(roll * Double(marketingFinds.count)), marketingFinds.count - 1)
            return marketingFinds[index]
        }
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
