import AppKit
import SwiftUI
import Observation
import IOKit.ps
import SinMinionsCore

/// Призрак Moth для монитора: тот же контур, что и у персонажа на экране.
struct GhostFigure: NSViewRepresentable {
    let style: GhostStyle
    let coffee: Bool
    let character: CompanionCharacter
    let outfit: Outfit

    func makeNSView(context: Context) -> GhostFigureHost { GhostFigureHost(style: style, coffee: coffee, character: character, outfit: outfit) }

    func updateNSView(_ view: GhostFigureHost, context: Context) { view.show(style, coffee: coffee, character: character, outfit: outfit) }
}

/// Призрак для монитора: те же слои, что у призрака на экране, размером 72×84.
final class GhostFigureHost: NSView {
    private var style: GhostStyle
    private var coffee: Bool
    private var character: CompanionCharacter
    private var outfit: Outfit

    init(style: GhostStyle, coffee: Bool, character: CompanionCharacter, outfit: Outfit) {
        self.style = style
        self.coffee = coffee
        self.character = character
        self.outfit = outfit
        super.init(frame: NSRect(x: 0, y: 0, width: 72, height: 84))
        wantsLayer = true
        layer?.masksToBounds = false
        rebuild()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) не используется") }

    override var intrinsicContentSize: NSSize { NSSize(width: 72, height: 84) }

    func show(_ style: GhostStyle, coffee: Bool, character: CompanionCharacter, outfit: Outfit) {
        guard style != self.style || coffee != self.coffee || character != self.character || outfit != self.outfit else { return }
        self.style = style
        self.coffee = coffee
        self.character = character
        self.outfit = outfit
        rebuild()
    }

    private func rebuild() {
        layer?.sublayers?.forEach { $0.removeFromSuperlayer() }
        let art: any CompanionArt = character.makeArt(style: style, scale: 1.5, coffee: coffee, outfit: outfit)
        art.root.frame = CGRect(x: 0, y: 0, width: 72, height: 84)
        art.body.shadowRadius = 6 * art.glowScale
        art.body.shadowOpacity = 0.6
        layer?.addSublayer(art.root)
    }
}

struct MonitorView: View {
    var model: ConsoleModel

    private func fraction(_ part: UInt64, _ whole: UInt64) -> Double {
        whole > 0 ? Double(part) / Double(whole) : 0
    }

    private var thermal: String {
        switch model.snapshot.thermal {
        case .nominal: return tr("НОРМА")
        case .fair: return tr("ПОВЫШЕН")
        case .serious: return tr("ВЫСОКИЙ")
        case .critical: return tr("КРИТИЧЕСКИЙ")
        @unknown default: return "—"
        }
    }

    /// Значение, уровень и число уровней по буквам; nil — характеристика пока без назначения.
    private func specialInfo(_ stat: SpecialStat) -> (value: String, level: Int, levels: Int, label: String)? {
        let state = model.special
        switch stat {
        case .strength: return ("\(state.scaleLevel)", state.scaleLevel, Prefs.scales.count, state.scaleLabel)
        case .perception: return ("\(state.perceptionLevel)", state.perceptionLevel, GhostStyle.levels, state.perceptionLabel)
        case .endurance: return ("\(state.enduranceLevel)", state.enduranceLevel, Endurance.levels, state.enduranceLabel)
        case .charisma: return ("\(state.charismaLevel)", state.charismaLevel, Charisma.levels, state.charismaLabel)
        case .agility: return ("\(state.agilityLevel)", state.agilityLevel, Agility.levels, state.agilityLabel)
        case .intelligence:
            return (model.llmPosition.split(separator: "/").first.map(String.init) ?? "–", 0, 0, "")
        default: return nil
        }
    }

    /// S.P.E.C.I.A.L. над призраком, как в Fallout: буквы с точками в квадратиках. Выбранная буква
    /// светится ярче остальных (рамка и заливка у всех одинаковые). Щелчок выбирает характеристику, и большие
    /// «−» и «+» под призраком меняют её уровень (у I — подключение к нейросети).
    private var specialStrip: some View {
        HStack(spacing: 4) {
            ForEach(SpecialStat.all(for: model.character)) { stat in
                let selected = model.selectedStat == stat
                let strength: Double = selected ? 1 : (model.isActive(stat) ? 0.5 : 0.28)
                // Буква и точка внутри одного квадрата: «S.», «P.», …
                Text(stat.letter(for: model.character) + ".")
                    .font(.system(size: 15, weight: .bold, design: .monospaced))
                    .frame(maxWidth: 34)
                    .frame(height: 30)
                    .overlay(Rectangle().strokeBorder(Term.green, lineWidth: 1))
                    .foregroundStyle(Term.green)
                    .opacity(strength)
                    .shadow(color: Term.green.opacity(selected ? 0.9 : 0), radius: selected ? 5 : 0)
                    .contentShape(Rectangle())
                    .onTapGesture { if model.isActive(stat) { model.selectedStat = stat } }
                    .accessibilityElement(children: .ignore)
                    .accessibilityAddTraits(.isButton)
                    .accessibilityLabel(Text(stat.title(for: model.character)))
                    .accessibilityValue(Text(accessibilityValue(stat)))
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// Для VoiceOver: «3 из 4» у обычной характеристики, название подключения у «интеллекта».
    private func accessibilityValue(_ stat: SpecialStat) -> String {
        guard let info = specialInfo(stat) else { return "" }
        if stat == .intelligence { return info.label }
        return trf("%@ из %@", "\(info.level + 1)", "\(info.levels)")
    }

    /// Подпись и «−» с «+» под призраком: для I — подключение, для остальных букв — уровень выбранной характеристики.
    private var intelligence: some View {
        let stat = model.selectedStat
        let info = specialInfo(stat)
        let isIntelligence = stat == .intelligence
        let level = info?.level ?? 0
        let levels = info?.levels ?? 0
        return VStack(spacing: 6) {
            specialStrip
            GhostFigure(style: model.ghostStyle, coffee: model.coffee, character: model.character, outfit: model.outfit)
                .frame(width: 72, height: 84)
            Text(stat.title(for: model.character))
                .foregroundStyle(Term.dim)
            HStack(spacing: 10) {
                stepButton("−", enabled: isIntelligence ? model.llmCount > 1 : level > 0) {
                    if isIntelligence { model.switchConnection(-1) } else { model.adjustSpecial(stat, -1) }
                }
                VStack(spacing: 1) {
                    if isIntelligence {
                        Text((model.llmName ?? tr("НЕТ ПОДКЛЮЧЕНИЙ")).uppercased())
                            .lineLimit(1)
                            .truncationMode(.tail)
                        if let modelName = model.llmModelName {
                            Text(modelName.uppercased())
                                .foregroundStyle(Term.dim)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                        if !model.llmPosition.isEmpty {
                            Text(model.llmPosition).foregroundStyle(Term.dim)
                        }
                    } else {
                        Text(info?.label ?? "")
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .minimumScaleFactor(0.8)
                        Text(trf("УРОВЕНЬ %@ ИЗ %@", "\(level)", "\(max(levels - 1, 0))")).foregroundStyle(Term.dim)
                    }
                }
                .frame(maxWidth: .infinity)
                stepButton("+", enabled: isIntelligence ? model.llmCount > 1 : level < levels - 1) {
                    if isIntelligence { model.switchConnection(1) } else { model.adjustSpecial(stat, 1) }
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func stepButton(_ symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Text(symbol)
            .frame(width: 26, height: 26)
            .overlay(Rectangle().strokeBorder(enabled ? Term.green : Term.dark, lineWidth: 1))
            .opacity(enabled ? 1 : 0.45)
            .contentShape(Rectangle())
            .onTapGesture { if enabled { action() } }
            .accessibilityElement(children: .ignore)
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(Text(symbol == "−" ? tr("Меньше") : tr("Больше")))
            .accessibilityValue(Text(enabled ? "" : tr("недоступно")))
    }

    /// Остаток токенов или средств по каждому подключению: название и остаток, под ними модель.
    /// Выбранное подключение подсвечено; длинный список прокручивается.
    private var limitsBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(tr("ЛИМИТЫ")).foregroundStyle(Term.green).bold()
            if model.llmConnections.isEmpty {
                Text(tr("ПОДКЛЮЧЕНИЙ НЕТ")).foregroundStyle(Term.dim)
            } else {
                // Все подключения видны сразу: раньше список обрезался на трёх строках без индикатора прокрутки,
                // и четвёртое подключение (например, DeepSeek) выглядело как отсутствующее.
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(model.llmConnections) { item in limitRow(item) }
                }
            }
        }
    }

    private func limitRow(_ item: LLMConnectionRow) -> some View {
        let state = model.limits.state(for: item.connection) ?? .loading
        let text: String
        var warning = false
        switch state {
        case .loading: text = "…"
        case let .value(value): text = value
        case let .failed(reason): text = reason; warning = true
        case .noKey: text = tr("нет ключа"); warning = true
        case .unsupported: text = "—"
        }
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                // Название имеет приоритет: сжимается значение справа, а не оно.
                Text((item.isActive ? "▸ " : "  ") + item.connection.name.uppercased())
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .layoutPriority(1)
                Spacer(minLength: 4)
                Text(text.uppercased())
                    .foregroundStyle(warning ? Term.amber : (item.isActive ? Term.green : Term.dim))
                    .lineLimit(1)
                    .fixedSize()
            }
            Text("  " + item.connection.model.uppercased())
                .font(.system(size: 9.5, design: .monospaced))
                .foregroundStyle(Term.dim)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .foregroundStyle(item.isActive ? Term.green : Term.dim)
    }

    private func gauge(_ label: String, _ value: String, _ fraction: Double) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(label)
                Spacer(minLength: 4)
                Text(value)
            }
            Text(Gauge.bar(fraction, width: 30))
                .foregroundStyle(Term.dim)
                .lineLimit(1)
                .fixedSize()
        }
    }

    private func line(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
            Spacer(minLength: 4)
            Text(value)
        }
    }

    var body: some View {
        let s = model.snapshot
        TerminalFrame(title: model.character == .ab ? model.character.monitorName : trf("%@ // МОНИТОР", "\(model.character.monitorName)"), window: .monitor, model: model) {
            // Если окно сделали ниже содержимого, оно прокручивается.
            ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 9) {
                intelligence
                Rectangle().fill(Term.dark).frame(height: 1)
                gauge(tr("ЦП"), s.cpu.map { Gauge.percent($0) } ?? "…", s.cpu ?? 0)
                gauge(tr("ПАМЯТЬ"), "\(MetricFormat.bytes(s.memoryUsed)) / \(MetricFormat.bytes(s.memoryTotal))",
                      fraction(s.memoryUsed, s.memoryTotal))
                gauge(tr("ДИСК"), "\(MetricFormat.bytes(s.diskUsed)) / \(MetricFormat.bytes(s.diskTotal))",
                      fraction(s.diskUsed, s.diskTotal))
                if let battery = s.battery {
                    gauge(s.onAC ? tr("БАТАРЕЯ ⚡") : tr("БАТАРЕЯ"), "\(battery)%", Double(battery) / 100)
                }
                Rectangle().fill(Term.dark).frame(height: 1)
                line(tr("СЕТЬ ↓"), MetricFormat.rate(s.netDown))
                line(tr("СЕТЬ ↑"), MetricFormat.rate(s.netUp))
                line(tr("НАГРЕВ"), thermal)
                line(tr("В РАБОТЕ"), MetricFormat.uptime(s.uptime))
                if model.coffee {
                    // Режим «кофе»: система и экран не засыпают, пока он включён.
                    line(tr("КОФЕ"), tr("ВКЛ · ЭКРАН НЕ ГАСНЕТ"))
                        .foregroundStyle(Term.green)
                        .bold()
                }
                if model.showLimits {
                    Rectangle().fill(Term.dark).frame(height: 1)
                    limitsBlock
                }
            }
            .font(Term.small)
            .foregroundStyle(Term.green)
            .shadow(color: Term.green.opacity(0.45), radius: 3)
            }
        }
    }
}
