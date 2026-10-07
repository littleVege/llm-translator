import AppKit

/// Owns the menu bar icon. Left click toggles the input bar,
/// right click shows the menu.
@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    struct Actions {
        let translateSelection: () -> Void
        let translateClipboard: () -> Void
        let openInputBar: () -> Void
        let openSettings: () -> Void
        let quit: () -> Void
    }

    private let statusItem: NSStatusItem
    private let onLeftClick: () -> Void
    private let actions: Actions

    init(onLeftClick: @escaping () -> Void, actions: Actions) {
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        self.onLeftClick = onLeftClick
        self.actions = actions
        super.init()

        if let button = statusItem.button {
            button.image = Self.icon()
            button.target = self
            button.action = #selector(clicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.toolTip = "LLM Translator"
        }
    }

    private static func icon() -> NSImage? {
        for name in ["translate", "character.bubble", "globe"] {
            if let image = NSImage(systemSymbolName: name, accessibilityDescription: "LLM Translator") {
                return image
            }
        }
        return nil
    }

    @objc private func clicked() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showMenu()
        } else {
            onLeftClick()
        }
    }

    private func showMenu() {
        let menu = NSMenu()
        menu.delegate = self

        let hotkeyLabel = AppSettings.shared.hotkeyOption.label
        menu.addItem(makeItem("Translate Selection (\(hotkeyLabel))", #selector(translateSelection)))
        menu.addItem(makeItem("Translate Clipboard", #selector(translateClipboard)))
        menu.addItem(makeItem("Open Translator Bar", #selector(openInputBar)))
        menu.addItem(.separator())
        menu.addItem(makeItem("Settings…", #selector(openSettings)))
        menu.addItem(.separator())
        menu.addItem(makeItem("Quit LLM Translator", #selector(quit)))

        // Attach the menu only for this click so plain left clicks keep
        // triggering the action instead of opening the menu.
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
    }

    func menuDidClose(_ menu: NSMenu) {
        statusItem.menu = nil
    }

    private func makeItem(_ title: String, _ selector: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: selector, keyEquivalent: "")
        item.target = self
        return item
    }

    @objc private func translateSelection() { actions.translateSelection() }
    @objc private func translateClipboard() { actions.translateClipboard() }
    @objc private func openInputBar() { actions.openInputBar() }
    @objc private func openSettings() { actions.openSettings() }
    @objc private func quit() { actions.quit() }
}
