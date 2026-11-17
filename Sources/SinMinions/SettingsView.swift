import SwiftUI
import Combine

/// Окно настроек.
struct SettingsView: View {
    @Bindable var prefs: Prefs
    @Bindable var updater: Updater

    @State private var hasAccess = SpotlightLauncher.hasAccess
    @State private var launchAtLogin = LoginItem.isEnabled
    @State private var loginError: String?
    @State private var resetFailed = false
    private let accessTimer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

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
