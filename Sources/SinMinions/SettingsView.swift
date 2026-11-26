import SwiftUI
import Combine
import Observation
import SinMinionsCore

enum SettingsTab: Hashable { case general, llm, about }

/// Какая вкладка открыта: на нужную вкладку окно переключается извне (например, из чата без ключа).
@MainActor
@Observable
final class SettingsRouter {
    var tab: SettingsTab = .general
}

/// Окно настроек: три вкладки.
struct SettingsView: View {
    @Bindable var prefs: Prefs
    @Bindable var updater: Updater
    @Bindable var router: SettingsRouter
    let llm: LLMService

    var body: some View {
        TabView(selection: $router.tab) {
            GeneralSettings(prefs: prefs)
                .tabItem { Label(tr("Основные"), systemImage: "gearshape") }
                .tag(SettingsTab.general)
            LLMSettings(prefs: prefs, llm: llm)
                .tabItem { Label(tr("Нейросеть"), systemImage: "brain") }
                .tag(SettingsTab.llm)
            AboutSettings(updater: updater)
                .tabItem { Label(tr("О программе"), systemImage: "info.circle") }
                .tag(SettingsTab.about)
        }
        // Смена языка перерисовывает окно целиком: все подписи берутся заново.
        .id(prefs.language)
        // Высоту задаёт окно: если всё не помещается на экран, формы прокручиваются.
        .frame(minWidth: 460, maxWidth: .infinity, minHeight: 320, maxHeight: .infinity)
    }
}

// MARK: - Основные

private struct GeneralSettings: View {
    @Bindable var prefs: Prefs

    private var characterDescription: String {
        switch prefs.character {
        case .f: return tr("F: призрак Moth, терминал и монитор в стиле Fallout.")
        case .ab: return tr("ab: золотой страж, терминал и монитор в стиле Вархаммера.")
        case .v: return tr("V — vikcha piccha, аниме-девочка-маркетолог.")
        }
    }

    private var searchDescription: String {
        switch prefs.character {
        case .f: return tr("Что-нибудь ищет и находит (водяной чип и другое)")
        case .ab: return tr("Ищет реликвии Империума и находит их")
        case .v: return tr("Ищет маркетинговые находки: брифы, графики и идеи")
        }
    }

    @State private var launchAtLogin = LoginItem.isEnabled
    @State private var loginError: String?

    var body: some View {
        Form {
            Section(tr("Персонаж")) {
                // Вкладки персонажей: у каждого свои настройки поведения, облик и стиль терминала с монитором.
                Picker(tr("Персонаж"), selection: $prefs.character) {
                    ForEach(CompanionCharacter.allCases) { character in
                        Text(character.tabTitle).tag(character)
                    }
                }
                .pickerStyle(.segmented)
                Text(characterDescription)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Picker(tr("Размер"), selection: $prefs.scale) {
                    ForEach(Prefs.scales, id: \.self) { value in
                        Text(value == 1.5 ? "1,5×" : "\(Int(value))×").tag(value)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section(trf("Поведение: %@", "\(prefs.character.tabTitle)")) {
                if prefs.character == .v {
                    Picker(tr("Маршрут"), selection: $prefs.vikchaRoute) {
                        Text(tr("По рабочему столу")).tag(VikchaRoute.desktop)
                        Text(tr("По краю активного окна")).tag(VikchaRoute.windowEdge)
                        Text(tr("По низу экрана")).tag(VikchaRoute.screenBottom)
                    }
                    Toggle(tr("Самостоятельные прогулки"), isOn: $prefs.wanderEnabled)
                } else {
                    Toggle(tr("Перелёты по экрану"), isOn: $prefs.wanderEnabled)
                }
                Toggle(tr("Телепорты через порталы"), isOn: $prefs.teleportEnabled)
                Toggle(tr("Подлетает к курсору (в составе перелётов)"), isOn: $prefs.chaseEnabled)
                    .disabled(!prefs.wanderEnabled)
                Toggle(tr("Пугается быстрого курсора"), isOn: $prefs.scareEnabled)
                Toggle(tr("Отлетает в сторону, если щёлкнуть правой кнопкой"), isOn: $prefs.shooEnabled)
                Toggle(searchDescription, isOn: $prefs.searchEnabled)
                if prefs.character == .ab {
                    Toggle(tr("Играет на приставке рядом с телевизором"), isOn: $prefs.playEnabled)
                    Toggle(tr("Иногда поёт гимн"), isOn: $prefs.singEnabled)
                    Toggle(tr("Ночью надевает пижаму и колпак (по времени)"), isOn: $prefs.pajamaAuto)
                    if prefs.pajamaAuto {
                        Picker(tr("Пижама с"), selection: $prefs.pajamaFrom) {
                            ForEach(0..<24, id: \.self) { Text(String(format: "%02d:00", $0)).tag($0) }
                        }
                        Picker(tr("Пижама до"), selection: $prefs.pajamaTo) {
                            ForEach(0..<24, id: \.self) { Text(String(format: "%02d:00", $0)).tag($0) }
                        }
                        if prefs.pajamaFrom == prefs.pajamaTo {
                            Text(tr("Начало и конец совпадают: пижама весь день.")).font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                    Text(tr("Пижама надевается и на уровне «спит» буквы E в мониторе.")).font(.footnote).foregroundStyle(.secondary)
                }
                Toggle(tr("Играет в прятки: тает и выскакивает с «бу!»"), isOn: $prefs.hideSeekEnabled)
                Toggle(tr("Танцует, когда подключили зарядку"), isOn: $prefs.celebrateEnabled)
                Picker(tr("Частота перелётов и телепортов"), selection: $prefs.wanderFrequency) {
                    Text(tr("Редко (3–6 мин)")).tag(Frequency.rare)
                    Text(tr("Обычно (1–3 мин)")).tag(Frequency.normal)
                    Text(tr("Часто (20–60 с)")).tag(Frequency.often)
                }
                .disabled(!prefs.wanderEnabled && !prefs.teleportEnabled)
                Toggle(tr("Реплики"), isOn: $prefs.talkEnabled)
                Picker(tr("Частота реплик"), selection: $prefs.talkFrequency) {
                    Text(tr("Редко (5–15 мин)")).tag(Frequency.rare)
                    Text(tr("Обычно (2–5 мин)")).tag(Frequency.normal)
                    Text(tr("Часто (8–14 с)")).tag(Frequency.often)
                }
                .disabled(!prefs.talkEnabled)
                Picker(tr("Реплика на экране"), selection: $prefs.bubbleDuration) {
                    ForEach(BubbleDuration.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                Picker(tr("Засыпать при бездействии"), selection: $prefs.sleepMinutes) {
                    Text(tr("через 1 мин")).tag(1)
                    Text(tr("через 5 мин")).tag(5)
                    Text(tr("через 15 мин")).tag(15)
                    Text(tr("никогда")).tag(0)
                }
                .disabled(prefs.alwaysAsleep)
            }

            Section(tr("Система")) {
                Picker(tr("Язык"), selection: $prefs.language) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(language.title).tag(language)
                    }
                }
                Toggle(tr("Скрывать в полноэкранных приложениях"), isOn: $prefs.hideInFullScreen)
                Picker(tr("Размер шрифта чата"), selection: $prefs.chatFont) {
                    ForEach(ChatFont.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                Toggle(tr("Не закрывать чат при потере фокуса"), isOn: $prefs.chatStaysOpen)
                    .help(tr("Чат останется открытым, когда вы переключитесь в другое приложение"))
                Toggle(tr("Помнить режим «кофе» после перезапуска"), isOn: $prefs.coffeeKeep)
                    .help(tr("Ноутбук не будет засыпать, пока режим кофе не выключат вручную (буква E или /coffee)"))
                Toggle(tr("Запускать при входе в систему"), isOn: $launchAtLogin)
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
        }
        .formStyle(.grouped)
    }
}

// MARK: - Нейросеть

enum CheckState: Equatable {
    case idle, running
    /// Подключение работает; строка — дополнительные сведения (например, баланс).
    case ok(String?)
    case failed(String)
}

private enum EditorTarget: Identifiable {
    case new
    case edit(LLMConnection)

    var id: String {
        switch self {
        case .new: return "new"
        case let .edit(connection): return connection.id.uuidString
        }
    }

    var connection: LLMConnection? {
        if case let .edit(connection) = self { return connection }
        return nil
    }
}

/// Список подключений к нейросетям: до десяти, одно из них выбрано — оно отвечает в чате терминала.
private struct LLMSettings: View {
    @Bindable var prefs: Prefs
    let llm: LLMService

    @State private var editing: EditorTarget?
    @State private var pendingDelete: LLMConnection?
    /// Меняется при каждом сохранении ключа, чтобы строки перечитали состояние Связки ключей.
    @State private var refresh = 0

    var body: some View {
        Form {
            Section {
                if prefs.connections.items.isEmpty {
                    Text(tr("Подключений пока нет. Добавьте первое — например, GigaChat."))
                        .foregroundStyle(.secondary)
                }
                ForEach(Array(prefs.connections.items.enumerated()), id: \.element.id) { index, connection in
                    row(connection, index: index)
                }
                Button(tr("Добавить подключение…")) { editing = .new }
            } header: {
                Text(trf("Подключения (%@)", "\(prefs.connections.items.count)"))
            }

            Section {
                Text(tr("Отмеченное подключение отвечает в чате терминала. В терминале и на мониторе призрака его можно переключать кнопками «+» и «−» (в терминале — клавишами + и −) — по порядку этого списка. Порядок меняется стрелками справа; тот же порядок у строк блока «Лимиты». В нейросеть уходит только текст, который вы вводите в чате; данные о Mac не передаются. Ключи хранятся в Связке ключей."))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .sheet(item: $editing) { target in
            ConnectionEditor(prefs: prefs, llm: llm, existing: target.connection) {
                editing = nil
                refresh += 1
            }
        }
        .confirmationDialog(
            trf("Удалить подключение «%@»?", "\(pendingDelete?.name ?? "")"),
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            presenting: pendingDelete
        ) { connection in
            Button(tr("Удалить вместе с ключом"), role: .destructive) { remove(connection) }
        }
    }

    private func row(_ connection: LLMConnection, index: Int) -> some View {
        let isActive = prefs.connections.active?.id == connection.id
        let hasKey = Keychain.exists(connection.keyAccount)
        return HStack(spacing: 10) {
            Button {
                prefs.connections.setActive(connection.id)
            } label: {
                Image(systemName: isActive ? "largecircle.fill.circle" : "circle")
            }
            .buttonStyle(.plain)
            .disabled(!connection.useInChat)
            .help(connection.useInChat ? tr("Сделать выбранным") : tr("Не используется в чате"))
            VStack(alignment: .leading, spacing: 2) {
                Text(connection.name)
                Text("\(connection.provider.title) · \(connection.model) · " + (hasKey ? tr("ключ сохранён") : tr("ключ не задан"))
                    + (connection.useInChat ? "" : tr(" · не в чате")) + (connection.showLimits ? "" : tr(" · без лимитов")))
                    .font(.footnote)
                    .foregroundStyle(hasKey ? Color.secondary : Color.red)
            }
            Spacer()
            Button { prefs.connections.move(id: connection.id, by: -1) } label: { Image(systemName: "chevron.up") }
                .buttonStyle(.borderless)
                .disabled(index == 0)
                .help(tr("Выше в списке"))
            Button { prefs.connections.move(id: connection.id, by: 1) } label: { Image(systemName: "chevron.down") }
                .buttonStyle(.borderless)
                .disabled(index == prefs.connections.items.count - 1)
                .help(tr("Ниже в списке"))
            Button { editing = .edit(connection) } label: { Image(systemName: "pencil") }
                .buttonStyle(.borderless)
                .help(tr("Изменить"))
            Button { pendingDelete = connection } label: { Image(systemName: "trash") }
                .buttonStyle(.borderless)
                .help(tr("Удалить"))
        }
        .id("\(connection.id)-\(refresh)")
    }

    private func remove(_ connection: LLMConnection) {
        Keychain.delete(connection.keyAccount)
        prefs.connections.remove(id: connection.id)
        pendingDelete = nil
    }
}

/// Окно добавления и изменения подключения.
private struct ConnectionEditor: View {
    @Bindable var prefs: Prefs
    let llm: LLMService
    let existing: LLMConnection?
    let close: () -> Void

    private static let customTag = "__custom__"

    @State private var name: String
    @State private var provider: LLMProvider
    @State private var scope: String
    @State private var modelChoice: String
    @State private var customModel: String
    @State private var keyDraft = ""
    @State private var showLimits: Bool
    @State private var useInChat: Bool
    @State private var error: String?
    @State private var check: CheckState = .idle
    /// Что ответила Связка ключей на попытку прочитать сохранённый ключ.
    @State private var accessNote: String?

    init(prefs: Prefs, llm: LLMService, existing: LLMConnection?, close: @escaping () -> Void) {
        self.prefs = prefs
        self.llm = llm
        self.existing = existing
        self.close = close
        let provider = existing?.provider ?? .gigachat
        let model = existing?.model ?? provider.defaultModel
        let isCustom = !provider.models.contains(model)
        _name = State(initialValue: existing?.name ?? provider.title)
        _showLimits = State(initialValue: existing?.showLimits ?? true)
        _useInChat = State(initialValue: existing?.useInChat ?? true)
        _provider = State(initialValue: provider)
        _scope = State(initialValue: existing?.scope ?? GigaChatAPI.scopes[0])
        _modelChoice = State(initialValue: isCustom ? Self.customTag : model)
        _customModel = State(initialValue: isCustom ? model : "")
    }

    private var model: String {
        modelChoice == Self.customTag ? customModel.trimmingCharacters(in: .whitespaces) : modelChoice
    }
    /// Прежний ключ подходит, пока провайдер не сменили.
    private var keepsStoredKey: Bool { existing != nil && existing?.provider == provider }
    private var hasDraftKey: Bool { provider.normalizedKey(keyDraft) != nil }
    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && !model.isEmpty && (keepsStoredKey || hasDraftKey)
    }
    private var canCheck: Bool {
        hasDraftKey || (keepsStoredKey && existing.map { Keychain.exists($0.keyAccount) } == true)
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section(existing == nil ? tr("Новое подключение") : tr("Подключение")) {
                    TextField(tr("Название"), text: $name)
                    Picker(tr("Провайдер"), selection: $provider) {
                        ForEach(LLMProvider.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .onChange(of: provider) { old, new in
                        modelChoice = new.defaultModel
                        customModel = ""
                        check = .idle
                        if name == old.title { name = new.title }
                    }
                    SecureField(keyLabel, text: $keyDraft)
                    if let account = existing?.keyAccount, Keychain.exists(account) {
                        // Ключ уже сохранён: объясняем, почему macOS может спросить пароль,
                        // и даём кнопку, которая вызывает этот запрос осознанно.
                        HStack(spacing: 8) {
                            Text(tr("Ключ хранится в Связке ключей. macOS может спросить разрешение — выберите «Разрешать всегда»."))
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            Button(tr("Разрешить доступ")) { requestKeyAccess(account) }
                        }
                        if let accessNote {
                            Text(accessNote).font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                    if provider.usesScope {
                        Picker(tr("Область доступа"), selection: $scope) {
                            Text(tr("Физлица (GIGACHAT_API_PERS)")).tag("GIGACHAT_API_PERS")
                            Text(tr("ИП и юрлица, пакеты (GIGACHAT_API_B2B)")).tag("GIGACHAT_API_B2B")
                            Text(tr("ИП и юрлица, по факту (GIGACHAT_API_CORP)")).tag("GIGACHAT_API_CORP")
                        }
                    }
                    Picker(tr("Модель"), selection: $modelChoice) {
                        ForEach(provider.models, id: \.self) { Text($0).tag($0) }
                        Text(tr("Другая…")).tag(Self.customTag)
                    }
                    if modelChoice == Self.customTag {
                        TextField(tr("Идентификатор модели"), text: $customModel)
                    }
                    Toggle(tr("Использовать в чате"), isOn: $useInChat)
                    Toggle(tr("Запрашивать и показывать лимиты"), isOn: $showLimits)
                    LabeledContent(tr("Проверка")) {
                        HStack {
                            switch check {
                            case .idle: EmptyView()
                            case .running: Text(tr("проверка…")).foregroundStyle(.secondary)
                            case let .ok(info): Text(tr("работает") + (info.map { " · " + $0 } ?? "")).foregroundStyle(.secondary)
                            case .failed: Text(tr("не удалось")).foregroundStyle(.red)
                            }
                            Button(tr("Проверить")) { runCheck() }
                                .disabled(!canCheck || check == .running)
                        }
                    }
                    if case let .failed(message) = check {
                        Text(message).font(.footnote).foregroundStyle(.secondary)
                    }
                    if let error {
                        Text(error).font(.footnote).foregroundStyle(.red)
                    }
                }
                Section {
                    Text(note).font(.footnote).foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            HStack {
                Spacer()
                Button(tr("Отмена"), role: .cancel) { close() }
                    .keyboardShortcut(.cancelAction)
                Button(tr("Сохранить")) { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSave)
            }
            .padding(16)
        }
        .frame(width: 460, height: 500)
    }

    private var keyLabel: String {
        let base = provider == .gigachat ? tr("Ключ авторизации") : tr("API-ключ")
        return keepsStoredKey ? base + tr(" (пусто — оставить прежний)") : base
    }

    private var note: String {
        switch provider {
        case .gigachat:
            return tr("Ключ — это «Authorization data» из личного кабинета GigaChat API на developers.sber.ru. Модель GigaChat-3-Ultra доступна физлицам только по бесплатному пакету. Нужной модели нет в списке — выберите «Другая…» и введите идентификатор.")
        case .deepseek:
            return tr("API-ключ создаётся на platform.deepseek.com/api_keys. Запросы идут без режима размышления — так ответы короче и быстрее. Проверка показывает баланс. Нужной модели нет в списке — выберите «Другая…» и введите идентификатор.")
        case .claude:
            return tr("API-ключ создаётся в консоли Anthropic (platform.claude.com → API keys). Проверка показывает, сколько моделей доступно ключу. Остаток по ключу Anthropic не отдаёт, в блоке «Лимиты» будет прочерк. Нужной модели нет в списке — выберите «Другая…».")
        case .gpt:
            return tr("API-ключ — на platform.openai.com/api-keys. Системная подсказка уходит как developer, как требуют новые модели. Остаток по ключу OpenAI не отдаёт: смотрите в личном кабинете. Нужной модели нет в списке — выберите «Другая…».")
        case .grok:
            return tr("API-ключ — на console.x.ai/team/default/api-keys. Остаток по обычному ключу xAI не отдаёт (он доступен через отдельный ключ управления). Нужной модели нет в списке — выберите «Другая…».")
        case .gemini:
            return tr("API-ключ — на aistudio.google.com/apikey. Запросы идут на OpenAI-совместимый адрес Google. Остаток не отдаётся: лимиты смотрите в AI Studio. Нужной модели нет в списке — выберите «Другая…».")
        }
    }

    private func draft() -> LLMConnection {
        LLMConnection(
            id: existing?.id ?? UUID(), name: name, provider: provider, scope: scope, model: model,
            keyAccount: existing?.keyAccount, showLimits: showLimits, useInChat: useInChat
        )
    }

    /// Осознанный запрос доступа к сохранённому ключу: macOS показывает диалог один раз,
    /// «Разрешать всегда» привязывает разрешение к подписи этой сборки.
    private func requestKeyAccess(_ account: String) {
        let result = Keychain.readChecked(account)
        switch result.status {
        case errSecSuccess:
            accessNote = tr("Доступ к ключу есть")
        case errSecUserCanceled, errSecAuthFailed:
            accessNote = tr("Доступ не выдан — ключ не прочитан")
        default:
            accessNote = tr("Связка ключей не ответила")
        }
    }

    private func runCheck() {
        let stored = keepsStoredKey ? existing.flatMap { Keychain.read($0.keyAccount) } : nil
        guard let key = provider.normalizedKey(keyDraft) ?? stored else { return }
        let connection = draft()
        check = .running
        Task {
            do {
                check = .ok(try await llm.check(connection: connection, key: key))
            } catch {
                check = .failed(error.localizedDescription)
            }
        }
    }

    private func save() {
        var connection = draft()
        connection.name = name.trimmingCharacters(in: .whitespaces)
        do {
            if let key = provider.normalizedKey(keyDraft) {
                try Keychain.write(key, account: connection.keyAccount)
            }
        } catch {
            self.error = tr("Не удалось сохранить ключ: ") + error.localizedDescription
            return
        }
        if existing != nil {
            prefs.connections.update(connection)
        } else {
            prefs.connections.add(connection)
        }
        close()
    }
}

// MARK: - О программе

private struct AboutSettings: View {
    @Bindable var updater: Updater

    var body: some View {
        Form {
            Section(tr("Обновление")) {
                Toggle(tr("Проверять обновления автоматически"), isOn: $updater.autoCheck)
                LabeledContent(updater.statusLine) {
                    if let title = updater.actionTitle {
                        Button(title) { updater.primaryAction() }
                    }
                }
                if let details = updater.failureDetails {
                    Text(details).font(.footnote).foregroundStyle(.secondary)
                }
            }
            Section(tr("О программе")) {
                LabeledContent(tr("Версия"), value: updater.currentVersionString)
                Link(tr("Репозиторий на GitHub"), destination: URL(string: "https://github.com/claudesiniakov/sinminions")!)
                Text(tr("SinMinions — компаньоны для рабочего стола Mac. Двойной щелчок открывает чат с ИИ и монитор."))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
