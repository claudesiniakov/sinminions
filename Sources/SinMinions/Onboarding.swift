import AppKit
import SwiftUI
import SinMinionsCore

/// Мастер первого запуска: три шага, которые чаще всего спотыкают новичка —
/// куда положить приложение, где взять ключ модели и как открыть чат.
@MainActor
final class OnboardingWindow: NSObject, NSWindowDelegate {
    private var panel: NSPanel?
    private let openSettings: () -> Void
    private let openHelp: () -> Void
    private let summary: () -> (connections: Int, withKey: Int)
    private let finish: () -> Void

    init(
        openSettings: @escaping () -> Void,
        openHelp: @escaping () -> Void,
        summary: @escaping () -> (connections: Int, withKey: Int),
        finish: @escaping () -> Void
    ) {
        self.openSettings = openSettings
        self.openHelp = openHelp
        self.summary = summary
        self.finish = finish
        super.init()
    }

    func show() {
        if let panel {
            panel.makeKeyAndOrderFront(nil)
            return
        }
        let view = OnboardingView(
            openSettings: openSettings,
            openHelp: openHelp,
            summary: summary,
            finish: { [weak self] in self?.close() }
        )
        let hosting = NSHostingView(rootView: view)
        hosting.frame = CGRect(origin: .zero, size: CGSize(width: 500, height: 430))
        let panel = NSPanel(
            contentRect: hosting.frame,
            styleMask: [.titled, .closable, .nonactivatingPanel],
            backing: .buffered, defer: false
        )
        panel.title = tr("Знакомство")
        panel.titlebarAppearsTransparent = true
        panel.backgroundColor = NSColor(Term.background)
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.delegate = self
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        panel.contentView = hosting
        self.panel = panel
        panel.center()
        panel.makeKeyAndOrderFront(nil)
    }

    func close() {
        panel?.orderOut(nil)
        panel = nil
        finish()
    }

    func windowWillClose(_ notification: Notification) {
        panel = nil
        finish()
    }
}

/// Содержимое мастера: шаги, кнопки «назад/далее», проверки на месте.
struct OnboardingView: View {
    let openSettings: () -> Void
    let openHelp: () -> Void
    let summary: () -> (connections: Int, withKey: Int)
    let finish: () -> Void

    @State private var step = 0
    @State private var tick = 0

    private var bundlePath: String { Bundle.main.bundlePath }

    private var isInApplications: Bool { bundlePath.hasPrefix("/Applications/") }

    private var counts: (connections: Int, withKey: Int) { summary() }

    private var stepTitle: String {
        [tr("1. Установка"), tr("2. Модель и ключ"), tr("3. Как открыть чат")][step]
    }

    private func line(_ text: String, dim: Bool = false) -> some View {
        Text(text)
            .foregroundStyle(dim ? Term.dim : Term.green)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var firstStep: some View {
        VStack(alignment: .leading, spacing: 10) {
            line(tr("Приложению нужна папка «Программы»: из «Загрузок» обновление и запуск спотыкаются."), dim: true)
            if isInApplications {
                line(tr("Уже в «Программах» — этот шаг пройден."))
            } else {
                line(trf("Сейчас запущено из: %@", bundlePath), dim: true)
                Button(tr("Открыть «Программы»")) {
                    NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications"))
                }
                .buttonStyle(.bordered)
            }
            Button(tr("Проверить снова")) { tick += 1 }
                .buttonStyle(.link)
        }
    }

    private var secondStep: some View {
        VStack(alignment: .leading, spacing: 10) {
            line(tr("Без ключа модели чат не работает. Ключ хранится в Связке ключей, а не в настройках."), dim: true)
            let current = counts
            line(trf("Подключений: %@, с ключом: %@", "\(current.connections)", "\(current.withKey)"),
                 dim: current.withKey == 0)
            Button(tr("Открыть настройки нейросетей")) { openSettings() }
                .buttonStyle(.bordered)
            Button(tr("Проверить снова")) { tick += 1 }
                .buttonStyle(.link)
        }
    }

    private var thirdStep: some View {
        VStack(alignment: .leading, spacing: 10) {
            line(tr("Двойной щелчок по персонажу — чат. Одиночный — короткая реплика, перетаскивание — перенос."))
            line(tr("⌥⌘C открывает и закрывает чат из любого приложения."))
            line(tr("Всё остальное — в меню у значка в строке меню."))
            Button(tr("Что умеет")) { openHelp() }
                .buttonStyle(.link)
        }
    }

    private var stepBody: some View {
        Group {
            switch step {
            case 0: firstStep
            case 1: secondStep
            default: thirdStep
            }
        }
        .id(tick)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("// " + stepTitle)
                .font(Term.small.bold())
                .foregroundStyle(Term.green)
            stepBody
            Spacer(minLength: 8)
            HStack(spacing: 10) {
                Text(trf("Шаг %@ из 3", "\(step + 1)"))
                    .font(Term.small)
                    .foregroundStyle(Term.dim)
                Spacer()
                if step > 0 {
                    Button(tr("Назад")) { step -= 1 }
                        .buttonStyle(.link)
                }
                Button(tr("Пропустить")) { finish() }
                    .buttonStyle(.link)
                Button(step == 2 ? tr("Готово") : tr("Далее")) {
                    if step == 2 { finish() } else { step += 1; tick += 1 }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .font(Term.small)
        .background(Term.background)
        .tint(Term.green)
    }
}
