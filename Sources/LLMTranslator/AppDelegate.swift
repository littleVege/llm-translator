import AppKit
import ApplicationServices
import Combine

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusController: StatusItemController?
    private let hotkeys = HotkeyManager()
    private var bag = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        setupMainMenu()

        statusController = StatusItemController(
            onLeftClick: { InputBarController.shared.toggle() },
            actions: .init(
                translateSelection: { [weak self] in self?.translateSelection(afterDelay: 0.2) },
                translateClipboard: { self.translateClipboard() },
                openInputBar: { InputBarController.shared.show() },
                openSettings: { SettingsWindowController.shared.show() },
                quit: { NSApp.terminate(nil) }
            )
        )

        hotkeys.handler = { [weak self] in self?.translateSelection(afterDelay: 0) }
        applyHotkey()
        AppSettings.shared.$hotkeyID
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] _ in self?.applyHotkey() }
            .store(in: &bag)

        if !UserDefaults.standard.bool(forKey: "didLaunchBefore") {
            UserDefaults.standard.set(true, forKey: "didLaunchBefore")
            SettingsWindowController.shared.show()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// An accessory app shows no menu bar, but without a main menu the standard
    /// editing shortcuts (⌘C/⌘V/⌘X/⌘A/⌘Z) never reach the focused text field.
    /// These nil-target items route through the responder chain to whatever
    /// text field is first responder.
    private func setupMainMenu() {
        let mainMenu = NSMenu()

        let appItem = NSMenuItem()
        mainMenu.addItem(appItem)
        let appMenu = NSMenu()
        appItem.submenu = appMenu
        appMenu.addItem(withTitle: "Settings…", action: #selector(openSettingsFromMenu), keyEquivalent: ",")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide LLM Translator", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit LLM Translator", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        let editItem = NSMenuItem()
        mainMenu.addItem(editItem)
        let editMenu = NSMenu(title: "Edit")
        editItem.submenu = editMenu
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSResponder.selectAll(_:)), keyEquivalent: "a")

        NSApp.mainMenu = mainMenu
    }

    @objc private func openSettingsFromMenu() {
        SettingsWindowController.shared.show()
    }

    private func applyHotkey() {
        let option = AppSettings.shared.hotkeyOption
        hotkeys.register(keyCode: option.keyCode, modifiers: option.carbonModifiers)
    }

    private func translateSelection(afterDelay delay: TimeInterval) {
        Task { @MainActor in
            // When the input bar has focus, the "selection" is our own text field:
            // translate its content instead of poking at other apps.
            if InputBarController.shared.isKey {
                InputBarController.shared.translateCurrent()
                return
            }
            if delay > 0 {
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
            let mouse = NSEvent.mouseLocation
            guard AccessibilityPermission.ensure() else {
                TranslationPopupController.shared.showPermissionHint(at: mouse)
                return
            }
            let text = await SelectionCapture.currentSelectedText()
            TranslationPopupController.shared.show(text: text, at: NSEvent.mouseLocation)
        }
    }

    private func translateClipboard() {
        let text = NSPasteboard.general.string(forType: .string)
        TranslationPopupController.shared.show(text: text, at: NSEvent.mouseLocation)
    }
}

enum AccessibilityPermission {
    /// Returns true when the app may read selections / post keystrokes.
    /// Shows the system grant dialog the first time it is missing.
    static func ensure() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    static var granted: Bool {
        AXIsProcessTrusted()
    }
}
