import AppKit
import Carbon.HIToolbox

/// Глобальная горячая клавиша.
///
/// Carbon используется сознательно: `RegisterEventHotKey` регистрирует сочетание на уровне
/// системы и не требует «Универсального доступа», в отличие от глобальных мониторов событий.
/// Сочетание работает, даже когда приложение не активно.
final class HotKey {
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private let action: () -> Void
    private let identifier = EventHotKeyID(signature: OSType(0x534D_4E31), id: 1) // 'SMN1'

    /// - Parameters:
    ///   - keyCode: код клавиши Carbon, например `kVK_ANSI_C`.
    ///   - modifiers: модификаторы Carbon, например `cmdKey | optionKey`.
    init(
        keyCode: UInt32 = UInt32(kVK_ANSI_C),
        modifiers: UInt32 = UInt32(cmdKey | optionKey),
        action: @escaping () -> Void
    ) {
        self.action = action
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    private let keyCode: UInt32
    private let modifiers: UInt32

    deinit {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
    }

    /// true — сочетание зарегистрировано; false — занято другой программой.
    @discardableResult
    func register() -> Bool {
        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let userData = Unmanaged.passUnretained(self).toOpaque()
        let install = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let event, let userData else { return noErr }
                var pressed = EventHotKeyID()
                let status = GetEventParameter(
                    event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                    nil, MemoryLayout<EventHotKeyID>.size, nil, &pressed
                )
                guard status == noErr else { return noErr }
                let hotKey = Unmanaged<HotKey>.fromOpaque(userData).takeUnretainedValue()
                guard pressed.signature == hotKey.identifier.signature,
                      pressed.id == hotKey.identifier.id else { return noErr }
                DispatchQueue.main.async { hotKey.action() }
                return noErr
            },
            1, &spec, userData, &handlerRef
        )
        guard install == noErr else { return false }
        let registered = RegisterEventHotKey(
            keyCode, modifiers, identifier, GetApplicationEventTarget(), 0, &hotKeyRef
        )
        return registered == noErr
    }
}
