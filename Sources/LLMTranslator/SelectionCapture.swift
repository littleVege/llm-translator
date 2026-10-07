import AppKit
import ApplicationServices
import Carbon.HIToolbox

/// Reads the text currently selected in whatever app is frontmost.
/// Tries the Accessibility API first, then falls back to simulating ⌘C
/// while preserving the user's clipboard.
enum SelectionCapture {
    @MainActor
    static func currentSelectedText() async -> String? {
        if let text = accessibilitySelection(),
           !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return text
        }
        return await pasteboardSelection()
    }

    private static func accessibilitySelection() -> String? {
        let systemWide = AXUIElementCreateSystemWide()

        var focusedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            systemWide, kAXFocusedUIElementAttribute as CFString, &focusedRef
        ) == .success,
            let focusedRef,
            CFGetTypeID(focusedRef) == AXUIElementGetTypeID()
        else { return nil }
        let element = focusedRef as! AXUIElement

        var selectedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element, kAXSelectedTextAttribute as CFString, &selectedRef
        ) == .success,
            let text = selectedRef as? String
        else { return nil }
        return text
    }

    @MainActor
    private static func pasteboardSelection() async -> String? {
        let pasteboard = NSPasteboard.general

        let savedItems: [[(NSPasteboard.PasteboardType, Data)]] =
            (pasteboard.pasteboardItems ?? []).map { item in
                item.types.compactMap { type in
                    item.data(forType: type).map { (type, $0) }
                }
            }
        let previousCount = pasteboard.changeCount

        postCopyKeystroke()

        var captured: String?
        for _ in 0..<25 {
            try? await Task.sleep(nanoseconds: 20_000_000)
            if pasteboard.changeCount != previousCount {
                captured = pasteboard.string(forType: .string)
                break
            }
        }

        // Only rewrite the pasteboard if our synthetic ⌘C actually changed it.
        if pasteboard.changeCount != previousCount {
            pasteboard.clearContents()
            let items = savedItems.map { pairs -> NSPasteboardItem in
                let item = NSPasteboardItem()
                for (type, data) in pairs {
                    item.setData(data, forType: type)
                }
                return item
            }
            if !items.isEmpty {
                pasteboard.writeObjects(items)
            }
        }

        let trimmed = captured?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : captured
    }

    private static func postCopyKeystroke() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_C), keyDown: true)
        keyDown?.flags = .maskCommand
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_C), keyDown: false)
        keyUp?.flags = .maskCommand
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }
}
