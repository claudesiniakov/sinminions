import AppKit
import SwiftUI
import SinMinionsCore

/// Окно «Что умеет»: короткая шпаргалка по управлению, чату, монитору и меню.
/// Открывается из меню — это главный ответ на вопрос «а что оно вообще может».
@MainActor
final class HelpWindow {
    private var panel: NSPanel?
    private var host: NSHostingView<HelpView>?

    func show() {
        if let panel {
            panel.makeKeyAndOrderFront(nil)
            return
        }
        let hosting = NSHostingView(rootView: HelpView { [weak self] in self?.close() })
        hosting.frame = CGRect(origin: .zero, size: CGSize(width: 470, height: 500))
        let panel = NSPanel(
            contentRect: hosting.frame,
            styleMask: [.titled, .closable, .nonactivatingPanel],
            backing: .buffered, defer: false
        )
        panel.title = tr("Что умеет")
        panel.titlebarAppearsTransparent = true
        panel.backgroundColor = NSColor(Term.background)
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        panel.contentView = hosting
        self.panel = panel
        self.host = hosting
        panel.center()
        panel.makeKeyAndOrderFront(nil)
    }

    func close() {
        panel?.orderOut(nil)
    }
}

/// Содержимое шпаргалки в стиле терминала.
struct HelpView: View {
    let close: () -> Void

    private struct Row: Identifiable {
        let id = UUID()
        let keys: String
        let text: String
    }

    private func section(_ title: String, _ rows: [Row]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("// " + title)
                .foregroundStyle(Term.green)
                .font(Term.small.bold())
            ForEach(rows) { row in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(row.keys)
                        .foregroundStyle(Term.green)
                        .frame(width: 128, alignment: .leading)
                    Text(row.text)
                        .foregroundStyle(Term.dim)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    section(tr("Управление"), [
                        Row(keys: tr("двойной щелчок"), text: tr("открыть чат")),
                        Row(keys: tr("одиночный"), text: tr("короткая реплика")),
                        Row(keys: tr("перетаскивание"), text: tr("перенести в другое место")),
                        Row(keys: "⌥⌘C", text: tr("чат из любого приложения")),
                    ])
                    section(tr("Чат"), [
                        Row(keys: "Tab", text: tr("дополнить команду")),
                        Row(keys: "↑ ↓", text: tr("листать отправленное")),
                        Row(keys: "Esc", text: tr("закрыть чат")),
                        Row(keys: "/help", text: tr("все команды")),
                        Row(keys: "/shell", text: tr("обычный zsh, exit — назад в чат")),
                        Row(keys: "/coffee", text: tr("не давать ноутбуку уснуть")),
                        Row(keys: "/аналитика", text: tr("расход токенов по моделям")),
                    ])
                    section(tr("Монитор"), [
                        Row(keys: tr("буквы"), text: tr("S.P.E.C.I.A.L. у Мота и стража, ПИАР у V")),
                        Row(keys: "− +", text: tr("изменить выбранную характеристику")),
                        Row(keys: tr("лимиты"), text: tr("остаток по подключениям, где он разрешён")),
                    ])
                    section(tr("Меню у значка"), [
                        Row(keys: tr("скрыть"), text: tr("спрятать компаньона или вернуть")),
                        Row(keys: tr("усыпить"), text: tr("тишина на час")),
                        Row(keys: tr("в угол"), text: tr("вернуть на место")),
                        Row(keys: tr("обновление"), text: tr("проверить и установить новую версию")),
                    ])
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
            }
            Divider().overlay(Term.dark)
            Button(action: close) {
                Text(tr("ЗАКРЫТЬ"))
                    .font(Term.small)
                    .foregroundStyle(Term.green)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.plain)
            .padding([.horizontal, .bottom], 12)
        }
        .font(Term.small)
        .background(Term.background)
    }
}
