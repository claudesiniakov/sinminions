import AppKit
import Charts
import Observation
import SwiftUI
import SinMinionsCore

/// Расход токенов по моделям: копится из поля `usage` каждого ответа API и хранится в Application Support.
@MainActor
@Observable
final class UsageStore {
    private(set) var ledger = UsageLedger()
    @ObservationIgnored private let file: URL?

    init() {
        let demo = ProcessInfo.processInfo.environment["SINMINIONS_DEMO"] != nil
        let folder = try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("SinMinions", isDirectory: true)
        // В демонстрации CI настоящий журнал не трогаем.
        file = demo ? nil : folder?.appendingPathComponent("usage.json")
        if let folder, !demo { try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true) }
        if let file, let data = try? Data(contentsOf: file), let saved = try? JSONDecoder().decode(UsageLedger.self, from: data) {
            ledger = saved
        }
        if demo { loadDemo() }
    }

    func record(provider: LLMProvider, model: String, usage: TokenUsage?) {
        ledger.record(provider: provider, model: model, usage: usage, at: Date())
        save()
    }

    private func save() {
        guard let file, let data = try? JSONEncoder().encode(ledger) else { return }
        try? data.write(to: file, options: .atomic)
        // Журнал расхода — не секрет, но и не для всех: как у ключа, только владельцу.
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    }

    /// Для снимков в CI: три модели с расходом за две недели.
    private func loadDemo() {
        let now = Date()
        let samples: [(LLMProvider, String, Int)] = [(.gigachat, "GigaChat-2-Pro", 3), (.deepseek, "deepseek-flash", 2), (.claude, "claude-sonnet-5-5", 1)]
        for (provider, model, weight) in samples {
            for back in 0..<14 {
                guard let date = Calendar.current.date(byAdding: .day, value: -back, to: now) else { continue }
                let requests = (back * 7 + weight * 3) % 6
                for index in 0..<requests {
                    let input = 600 * weight + (back * 131 + index * 97) % 900
                    ledger.record(provider: provider, model: model, usage: TokenUsage(input: input, output: input / 3 + 120), at: date)
                }
            }
        }
    }
}

/// Дашборд аналитики: вкладка на каждую модель, плитки за периоды, график по дням и остаток из API.
struct AnalyticsView: View {
    var store: UsageStore
    var limits: LimitsStore
    var connections: [LLMConnection]
    var character: CompanionCharacter
    var onClose: () -> Void

    @State private var selected: String?

    private var keys: [String] { store.ledger.orderedKeys }
    private var current: String? { selected.flatMap { keys.contains($0) ? $0 : nil } ?? keys.first }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            if keys.isEmpty {
                Spacer()
                Text(tr("ДАННЫХ ПОКА НЕТ.\nЗАДАЙТЕ ВОПРОС В ЧАТЕ — РАСХОД ТОКЕНОВ ПРИДЁТ В ОТВЕТЕ API."))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Term.dim)
                    .frame(maxWidth: .infinity)
                Spacer()
            } else {
                tabs
                if let key = current, let entry = store.ledger.models[key] { dashboard(key, entry) }
            }
        }
        .font(Term.font)
        .foregroundStyle(Term.green)
        .padding(EdgeInsets(top: 30, leading: 14, bottom: 14, trailing: 14))
        .frame(minWidth: 480, minHeight: 420, alignment: .topLeading)
        .background(Term.background)
        .overlay(Rectangle().strokeBorder(Term.dark, lineWidth: 1).padding(6).allowsHitTesting(false))
    }

    private var header: some View {
        HStack(spacing: 8) {
            if character == .ab { Text("✠").font(Term.title) }
            Text(character == .ab ? tr("ЛЕТОПИСЬ ТОКЕНОВ") : tr("АНАЛИТИКА ТОКЕНОВ"))
                .font(Term.title).tracking(1).foregroundStyle(Term.dim)
            Spacer()
            Button(tr("[ЗАКРЫТЬ]"), action: onClose)
                .buttonStyle(.plain)
                .font(Term.small)
                .foregroundStyle(Term.dim)
        }
    }

    private var tabs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(keys, id: \.self) { key in
                    let active = key == current
                    Button {
                        selected = key
                    } label: {
                        Text((store.ledger.models[key]?.model ?? key).uppercased())
                            .font(Term.small)
                            .lineLimit(1)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .foregroundStyle(active ? Term.background : Term.dim)
                            .background(active ? Term.green : Color.clear)
                            .overlay(Rectangle().strokeBorder(active ? Term.green : Term.dark, lineWidth: 1))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func dashboard(_ key: String, _ entry: UsageLedger.Model) -> some View {
        let now = Date()
        let ledger = store.ledger
        let all = ledger.totals(key, lastDays: nil, now: now)
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(entry.provider.title.uppercased() + " · " + entry.model.uppercased())
                    .bold()
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text(tr("ПОСЛЕДНИЙ: ") + entry.lastUsed.formatted(.dateTime.day().month(.twoDigits).hour().minute()))
                    .font(Term.small)
                    .foregroundStyle(Term.dim)
            }
            HStack(spacing: 8) {
                tile(tr("СЕГОДНЯ"), ledger.totals(key, lastDays: 1, now: now))
                tile(tr("7 ДНЕЙ"), ledger.totals(key, lastDays: 7, now: now))
                tile(tr("30 ДНЕЙ"), ledger.totals(key, lastDays: 30, now: now))
                tile(tr("ВСЕГО"), all)
            }
            chart(ledger.series(key, days: 14, now: now))
            VStack(alignment: .leading, spacing: 3) {
                row(tr("СРЕДНЕЕ НА ЗАПРОС"), UsageLedger.short(all.perRequest) + tr(" ТОК."))
                row(tr("ДОЛЯ ОТВЕТА"), all.total == 0 ? "—" : "\(all.output * 100 / all.total)%")
                balance(entry)
            }
            .font(Term.small)
        }
    }

    private func tile(_ title: String, _ totals: UsageTotals) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(Term.small).foregroundStyle(Term.dim)
            Text(UsageLedger.short(totals.total)).font(.system(size: 17, weight: .bold, design: .monospaced))
            Text("↑" + UsageLedger.short(totals.input) + " ↓" + UsageLedger.short(totals.output))
                .font(.system(size: 9.5, design: .monospaced))
                .foregroundStyle(Term.dim)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(trf("ЗАПРОСОВ: %@", "\(totals.requests)"))
                .font(.system(size: 9.5, design: .monospaced))
                .foregroundStyle(Term.dim)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(Rectangle().strokeBorder(Term.dark, lineWidth: 1))
    }

    private struct Bar: Identifiable {
        let id: String
        let day: String
        let part: String
        let value: Int
    }

    private func chart(_ series: [(day: String, totals: UsageTotals)]) -> some View {
        let bars = series.flatMap { item -> [Bar] in
            let label = String(item.day.suffix(5).split(separator: "-").reversed().joined(separator: "."))
            return [
                Bar(id: item.day + "in", day: label, part: tr("ВХОД"), value: item.totals.input),
                Bar(id: item.day + "out", day: label, part: tr("ОТВЕТ"), value: item.totals.output),
            ]
        }
        return VStack(alignment: .leading, spacing: 4) {
            Text(tr("ТОКЕНЫ ПО ДНЯМ · 14 ДНЕЙ")).font(Term.small).foregroundStyle(Term.dim)
            Chart(bars) { bar in
                BarMark(x: .value(tr("День"), bar.day), y: .value(tr("Токены"), bar.value))
                    .foregroundStyle(by: .value(tr("Часть"), bar.part))
            }
            .chartForegroundStyleScale([tr("ВХОД"): Term.dim, tr("ОТВЕТ"): Term.green])
            .chartLegend(position: .top, alignment: .trailing)
            .chartXAxis {
                AxisMarks { _ in
                    AxisValueLabel().font(.system(size: 8, design: .monospaced)).foregroundStyle(Term.dim)
                }
            }
            .chartYAxis {
                AxisMarks { value in
                    AxisGridLine().foregroundStyle(Term.dark.opacity(0.6))
                    AxisValueLabel {
                        if let number = value.as(Int.self) {
                            Text(UsageLedger.short(number)).font(.system(size: 8, design: .monospaced)).foregroundStyle(Term.dim)
                        }
                    }
                }
            }
            .frame(minHeight: 140)
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(Term.dim)
            Spacer(minLength: 4)
            Text(value)
        }
    }

    /// Остаток из API провайдера (GigaChat — токены модели, DeepSeek — деньги на счёте).
    @ViewBuilder
    private func balance(_ entry: UsageLedger.Model) -> some View {
        let connection = connections.first { $0.provider == entry.provider && $0.model == entry.model }
            ?? connections.first { $0.provider == entry.provider }
        if !entry.provider.supportsLimits {
            row(tr("ОСТАТОК (API)"), tr("СЕРВИС НЕ ОТДАЁТ ПО КЛЮЧУ"))
        } else if let connection {
            if connection.showLimits {
                switch limits.state(for: connection) ?? .loading {
                case .loading: row(tr("ОСТАТОК (API)"), "…")
                case let .value(value): row(tr("ОСТАТОК (API)"), value.uppercased())
                case let .failed(reason): row(tr("ОСТАТОК (API)"), reason.uppercased()).foregroundStyle(Term.amber)
                case .noKey: row(tr("ОСТАТОК (API)"), tr("НЕТ КЛЮЧА")).foregroundStyle(Term.amber)
                case .denied: row(tr("ОСТАТОК (API)"), tr("НЕТ ДОСТУПА")).foregroundStyle(Term.amber)
                case .unsupported: row(tr("ОСТАТОК (API)"), "—")
                }
            } else {
                row(tr("ОСТАТОК (API)"), tr("СКРЫТО В НАСТРОЙКАХ"))
            }
        } else {
            row(tr("ОСТАТОК (API)"), tr("ПОДКЛЮЧЕНИЕ УДАЛЕНО"))
        }
    }
}

/// Отдельное окно аналитики: открывается командой «/аналитика», не забирает фокус у других приложений.
@MainActor
final class AnalyticsWindow {
    private var panel: NSPanel?
    private var host: NSHostingView<AnalyticsView>?

    func show(store: UsageStore, limits: LimitsStore, connections: [LLMConnection], character: CompanionCharacter, near anchor: CGRect?) {
        // Остаток по ключу берём у тех же подключений, что и блок «Лимиты» на мониторе, и ещё у используемых в чате.
        // Только те подключения, где остаток разрешён в настройках: иначе запрос уходит
        // с ключом за спиной у пользователя, а строка висит на «…».
        limits.refresh(connections.filter(\.showLimits))
        let view = AnalyticsView(store: store, limits: limits, connections: connections, character: character) { [weak self] in
            self?.panel?.orderOut(nil)
        }
        let panel = self.panel ?? Self.makePanel()
        // Окно и его SwiftUI-иерархия создаются один раз; при повторном открытии меняются только данные.
        if let host {
            host.rootView = view
        } else {
            let host = NSHostingView(rootView: view)
            panel.contentView = host
            self.host = host
        }
        panel.backgroundColor = NSColor(Term.background)
        if self.panel == nil || !panel.isVisible {
            let size = CGSize(width: 560, height: 470)
            panel.setContentSize(size)
            if let visible = NSScreen.main?.visibleFrame {
                var origin = CGPoint(x: visible.midX - size.width / 2, y: visible.midY - size.height / 2)
                // Рядом с терминалом, если он открыт и места хватает.
                if let anchor {
                    let left = anchor.minX - size.width - 12
                    origin.x = left >= visible.minX ? left : min(anchor.maxX + 12, visible.maxX - size.width)
                    origin.y = min(max(anchor.maxY - size.height, visible.minY), visible.maxY - size.height)
                }
                panel.setFrameOrigin(origin)
            }
        }
        self.panel = panel
        panel.orderFrontRegardless()
    }

    func hide() { panel?.orderOut(nil) }

    private static func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: CGRect(x: 0, y: 0, width: 560, height: 470),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered, defer: false
        )
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        panel.title = tr("Аналитика токенов")
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.level = .floating
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.contentMinSize = CGSize(width: 480, height: 420)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        return panel
    }
}
