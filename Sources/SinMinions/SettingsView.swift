import SwiftUI
import Combine
import SinMinionsCore

/// Окно настроек.
struct SettingsView: View {
    @Bindable var prefs: Prefs
    @Bindable var updater: Updater
    let gigaChat: GigaChatClient

    @State private var hasAccess = SpotlightLauncher.hasAccess
    @State private var launchAtLogin = LoginItem.isEnabled
    @State private var loginError: String?
    @State private var resetFailed = false
    @State private var keyDraft = ""
    @State private var hasKey = Keychain.exists(GigaChatAccount.key)
    @State private var keyError: String?
    @State private var check: CheckState = .idle

    enum CheckState: Equatable {
        case idle, running, ok
        case failed(String)
    }
    private let accessTimer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    private func saveKey() {
        guard let key = GigaChatAPI.normalizedKey(keyDraft) else { return }
        do {
            try Keychain.write(key, account: GigaChatAccount.key)
            keyDraft = ""
            keyError = nil
            hasKey = true
            check = .idle
        } catch {
            keyError = "Не удалось сохранить ключ: " + error.localizedDescription
        }
    }

    private func removeKey() {
        Keychain.delete(GigaChatAccount.key)
        hasKey = false
        check = .idle
    }

    private func checkConnection() {
        guard let key = Keychain.read(GigaChatAccount.key) else {
            check = .failed("Ключ не читается из Связки ключей")
            return
        }
        check = .running
        let scope = prefs.llmScope
        Task {
            do {
                try await gigaChat.checkConnection(key: key, scope: scope)
                check = .ok
            } catch {
                check = .failed(error.localizedDescription)
            }
        }
    }

    var body: some View {
        Form {
            Section("Персонаж") {
                Picker("Размер", selection: $prefs.scale) {
                    ForEach(Prefs.scales, id: \.self) { value in
                        Text(value == 1.5 ? "1,5×" : "\(Int(value))×").tag(value)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section("Поведение") {
                Toggle("Перелёты по экрану", isOn: $prefs.wanderEnabled)
                Toggle("Телепорты через порталы", isOn: $prefs.teleportEnabled)
                Picker("Частота перелётов и телепортов", selection: $prefs.wanderFrequency) {
                    Text("Редко (3–6 мин)").tag(Frequency.rare)
                    Text("Обычно (1–3 мин)").tag(Frequency.normal)
                    Text("Часто (20–60 с)").tag(Frequency.often)
                }
                .disabled(!prefs.wanderEnabled && !prefs.teleportEnabled)
                Toggle("Реплики", isOn: $prefs.talkEnabled)
                Picker("Частота реплик", selection: $prefs.talkFrequency) {
                    Text("Редко (5–15 мин)").tag(Frequency.rare)
                    Text("Обычно (2–5 мин)").tag(Frequency.normal)
                    Text("Часто (8–14 с)").tag(Frequency.often)
                }
                .disabled(!prefs.talkEnabled)
                Picker("Засыпать при бездействии", selection: $prefs.sleepMinutes) {
                    Text("через 1 мин").tag(1)
                    Text("через 5 мин").tag(5)
                    Text("через 15 мин").tag(15)
                    Text("никогда").tag(0)
                }
            }

            Section("Spotlight") {
                Toggle("Двойной щелчок открывает Spotlight", isOn: $prefs.spotlightEnabled)
                LabeledContent("Универсальный доступ") {
                    if hasAccess {
                        Text("разрешён").foregroundStyle(.secondary)
                    } else {
                        Button("Выдать…") {
                            SpotlightLauncher.requestAccess()
                            SpotlightLauncher.openAccessSettings()
                        }
                    }
                }
                if !hasAccess {
                    Text("Без этого разрешения приложение не может нажать сочетание клавиш Spotlight. Остальное работает и без него.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    LabeledContent("Разрешение выдано, но не действует") {
                        Button("Сбросить и запросить заново") {
                            resetFailed = !SpotlightLauncher.resetAccess()
                        }
                    }
                    Text(resetFailed
                        ? "Сбросить не удалось. Удалите SinMinions из списка «Универсальный доступ» кнопкой «−» и добавьте снова."
                        : "Так бывает после обновления: система помнит разрешение прежней сборки. Сброс удаляет старую запись, после чего разрешение нужно выдать ещё раз.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Нейросеть — GigaChat") {
                SecureField("Ключ авторизации", text: $keyDraft)
                HStack {
                    Button("Сохранить ключ") { saveKey() }
                        .disabled(GigaChatAPI.normalizedKey(keyDraft) == nil)
                    if hasKey {
                        Button("Удалить ключ", role: .destructive) { removeKey() }
                    }
                }
                LabeledContent("Ключ") {
                    Text(hasKey ? "сохранён в Связке ключей" : "не задан").foregroundStyle(.secondary)
                }
                if let keyError {
                    Text(keyError).font(.footnote).foregroundStyle(.red)
                }
                Picker("Область доступа", selection: $prefs.llmScope) {
                    Text("Физлица (GIGACHAT_API_PERS)").tag("GIGACHAT_API_PERS")
                    Text("ИП и юрлица, пакеты (GIGACHAT_API_B2B)").tag("GIGACHAT_API_B2B")
                    Text("ИП и юрлица, по факту (GIGACHAT_API_CORP)").tag("GIGACHAT_API_CORP")
                }
                Picker("Модель", selection: $prefs.llmModel) {
                    ForEach(GigaChatAPI.models, id: \.self) { Text($0).tag($0) }
                }
                LabeledContent("Подключение") {
                    HStack {
                        switch check {
                        case .idle: EmptyView()
                        case .running: Text("проверка…").foregroundStyle(.secondary)
                        case .ok: Text("работает").foregroundStyle(.secondary)
                        case .failed: Text("не удалось").foregroundStyle(.red)
                        }
                        Button("Проверить") { checkConnection() }
                            .disabled(!hasKey || check == .running)
                    }
                }
                if case let .failed(message) = check {
                    Text(message).font(.footnote).foregroundStyle(.secondary)
                }
                Text("Ключ — это «Authorization data» из личного кабинета GigaChat API на developers.sber.ru. В GigaChat уходит только текст, который вы вводите в чате терминала (средний режим → «Чат с GigaChat»); данные о Mac не передаются.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Система") {
                Toggle("Скрывать в полноэкранных приложениях", isOn: $prefs.hideInFullScreen)
                Toggle("Запускать при входе в систему", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in
                        do {
                            if enabled { try LoginItem.enable() } else { try LoginItem.disable() }
                            loginError = nil
                        } catch {
                            loginError = error.localizedDescription
                        }
                    }
                if let loginError {
                    Text(loginError).font(.footnote).foregroundStyle(.red)
                }
            }

            Section("Обновление") {
                Toggle("Проверять обновления автоматически", isOn: $updater.autoCheck)
                LabeledContent(updater.statusLine) {
                    if let title = updater.actionTitle {
                        Button(title) { updater.primaryAction() }
                    }
                }
                if let details = updater.failureDetails {
                    Text(details).font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        // Высоту задаёт окно: если всё не помещается на экран, форма прокручивается.
        .frame(minWidth: 420, maxWidth: .infinity, minHeight: 280, maxHeight: .infinity)
        .onReceive(accessTimer) { _ in hasAccess = SpotlightLauncher.hasAccess }
    }
}
