import Carbon.HIToolbox
import Foundation

/// Registers a system-wide hotkey via Carbon. No special permission is
/// required for the hotkey itself (reading the selection is what needs
/// Accessibility).
final class HotkeyManager {
    var handler: (() -> Void)?

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?

    func register(keyCode: UInt32, modifiers: UInt32) {
        unregister()
        installHandlerIfNeeded()

        let hotKeyID = EventHotKeyID(signature: OSType(0x4C4C_5452), id: 1) // "LLTR"
        RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetEventDispatcherTarget(), 0, &hotKeyRef)
    }

    func unregister() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
    }

    private func installHandlerIfNeeded() {
        guard eventHandlerRef == nil else { return }
        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let selfPointer = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetEventDispatcherTarget(), { (_, _, userData) -> OSStatus in
            guard let userData else { return noErr }
            let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
            DispatchQueue.main.async { manager.handler?() }
            return noErr
        }, 1, &spec, selfPointer, &eventHandlerRef)
    }

    deinit {
        unregister()
        if let ref = eventHandlerRef {
            RemoveEventHandler(ref)
        }
    }
}

// Order matters: this is the order shown in the Settings picker, with the
// recommended default (⌥T — conflicts with nothing) first.
enum HotkeyOption: String, CaseIterable, Identifiable {
    case optT
    case cmdT
    case ctrlT
    case shiftCmdT
    case optCmdT

    var id: String { rawValue }

    var label: String {
        switch self {
        case .cmdT: return "⌘T"
        case .optT: return "⌥T"
        case .ctrlT: return "⌃T"
        case .shiftCmdT: return "⇧⌘T"
        case .optCmdT: return "⌥⌘T"
        }
    }

    var keyCode: UInt32 { UInt32(kVK_ANSI_T) }

    var carbonModifiers: UInt32 {
        switch self {
        case .cmdT: return UInt32(cmdKey)
        case .optT: return UInt32(optionKey)
        case .ctrlT: return UInt32(controlKey)
        case .shiftCmdT: return UInt32(shiftKey | cmdKey)
        case .optCmdT: return UInt32(optionKey | cmdKey)
        }
    }
}
