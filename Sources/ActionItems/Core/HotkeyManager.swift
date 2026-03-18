import Carbon
import AppKit

/// Global hotkey manager using Carbon RegisterEventHotKey.
/// Works system-wide even when another app is focused.
class HotkeyManager {
    static let shared = HotkeyManager()

    private var hotkeys: [UInt32: () -> Void] = [:]
    private var hotkeyRefs: [EventHotKeyRef] = []
    private var eventHandlerRef: EventHandlerRef?
    private var nextID: UInt32 = 1

    // Default key codes (user can change in Settings)
    // ⌘⇧A = capture screen, ⌘⇧M = toggle meeting
    static let captureScreenID: UInt32 = 1
    static let toggleMeetingID: UInt32 = 2

    var onCaptureScreen: (() -> Void)?
    var onToggleMeeting: (() -> Void)?

    private init() {
        installEventHandler()
        registerDefaults()
    }

    // MARK: - Setup

    private func installEventHandler() {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, userData -> OSStatus in
            guard let userData else { return OSStatus(eventNotHandledErr) }
            let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
            return manager.handleHotkey(event: event!)
        }, 1, &eventType, Unmanaged.passUnretained(self).toOpaque(), &eventHandlerRef)
    }

    private func registerDefaults() {
        // ⌘⇧A — capture screen
        register(
            id: HotkeyManager.captureScreenID,
            keyCode: UInt32(kVK_ANSI_A),
            modifiers: UInt32(cmdKey | shiftKey)
        ) { [weak self] in
            self?.onCaptureScreen?()
        }

        // ⌘⇧M — toggle meeting
        register(
            id: HotkeyManager.toggleMeetingID,
            keyCode: UInt32(kVK_ANSI_M),
            modifiers: UInt32(cmdKey | shiftKey)
        ) { [weak self] in
            self?.onToggleMeeting?()
        }
    }

    // MARK: - Register / Unregister

    func register(id: UInt32, keyCode: UInt32, modifiers: UInt32, handler: @escaping () -> Void) {
        let hotkeyID = EventHotKeyID(signature: OSType(0x4149544D), id: id) // 'AITM'
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(keyCode, modifiers, hotkeyID, GetApplicationEventTarget(), 0, &ref)
        if status == noErr, let ref {
            hotkeyRefs.append(ref)
            hotkeys[id] = handler
        }
    }

    func unregisterAll() {
        hotkeyRefs.forEach { UnregisterEventHotKey($0) }
        hotkeyRefs.removeAll()
        hotkeys.removeAll()
    }

    // MARK: - Event handling

    private func handleHotkey(event: EventRef) -> OSStatus {
        var hotkeyID = EventHotKeyID()
        GetEventParameter(event,
                          UInt32(kEventParamDirectObject),
                          UInt32(typeEventHotKeyID),
                          nil,
                          MemoryLayout<EventHotKeyID>.size,
                          nil,
                          &hotkeyID)

        if let handler = hotkeys[hotkeyID.id] {
            DispatchQueue.main.async { handler() }
            return noErr
        }
        return OSStatus(eventNotHandledErr)
    }
}
