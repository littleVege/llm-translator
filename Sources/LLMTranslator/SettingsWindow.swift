import AppKit
import ServiceManagement
import SwiftUI

@MainActor
final class SettingsWindowController {
    static let shared = SettingsWindowController()

    private var window: NSWindow?

    private init() {}

    func show() {
        if window == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 540, height: 660),
                styleMask: [.titled, .closable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            window.title = "LLM Translator Settings"
            window.isReleasedWhenClosed = false
            window.contentViewController = NSHostingController(rootView: SettingsView())
            window.center()
            self.window = window
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

struct SettingsView: View {
    @ObservedObject private var settings = AppSettings.shared
    @State private var loginEnabled = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?
    @State private var isCustomModel = false

    private static let otherModelTag = "__other__"

    private var currentProvider: Provider {
        Providers.byID(settings.providerID)
    }

    /// Bridges the model picker to `settings.model`. Selecting "Other…" flips
    /// to a free-text field instead of writing a sentinel into settings.
    private var modelSelection: Binding<String> {
        Binding(
            get: { isCustomModel ? Self.otherModelTag : settings.model },
            set: { newValue in
                if newValue == Self.otherModelTag {
                    isCustomModel = true
                } else {
                    isCustomModel = false
                    settings.model = newValue
                }
            }
        )
    }

    private var providerHint: String {
        let provider = currentProvider
        if provider.isCustom {
            return "Any OpenAI-compatible endpoint. The app calls {base URL}/chat/completions."
        }
        if provider.isLocal {
            return "Local endpoint — the API key can be left blank. Make sure the server is running."
        }
        return "The API key is stored in your macOS Keychain."
    }

    private func applyProvider(_ id: String) {
        let provider = Providers.byID(id)
        if !provider.isCustom {
            settings.baseURL = provider.baseURL
        }
        if provider.hasModelPresets {
            if !provider.models.contains(settings.model) {
                settings.model = provider.models.first ?? settings.model
            }
            isCustomModel = false
        } else {
            // Local runtimes / aggregators: model is whatever the user runs.
            isCustomModel = true
        }
    }

    var body: some View {
        Form {
            Section("Model") {
                Picker("Provider", selection: $settings.providerID) {
                    ForEach(Providers.all) { provider in
                        Text(provider.name).tag(provider.id)
                    }
                    Text(Providers.custom.name).tag(Providers.custom.id)
                }
                .onChange(of: settings.providerID) { _, newID in
                    applyProvider(newID)
                }

                if currentProvider.isCustom {
                    TextField("Base URL", text: $settings.baseURL, prompt: Text("https://your-endpoint/v1"))
                        .autocorrectionDisabled()
                } else {
                    LabeledContent("Base URL") {
                        Text(settings.baseURL)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }

                if currentProvider.hasModelPresets {
                    Picker("Model", selection: modelSelection) {
                        ForEach(currentProvider.models, id: \.self) { model in
                            Text(model).tag(model)
                        }
                        Text("Other…").tag(Self.otherModelTag)
                    }
                    if isCustomModel {
                        TextField("Model name", text: $settings.model, prompt: Text("model-id"))
                            .autocorrectionDisabled()
                    }
                } else {
                    TextField("Model", text: $settings.model, prompt: Text("model-id"))
                        .autocorrectionDisabled()
                }

                SecureField("API Key", text: $settings.apiKey)

                Text(providerHint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Languages") {
                Picker("Translate from", selection: $settings.sourceCode) {
                    Text(Language.auto.displayName).tag(Language.auto.code)
                    ForEach(Language.all) { language in
                        Text(language.displayName).tag(language.code)
                    }
                }
                Picker("Translate to", selection: $settings.targetCode) {
                    ForEach(Language.all) { language in
                        Text(language.displayName).tag(language.code)
                    }
                }
                Picker("Alternate target", selection: $settings.altTargetCode) {
                    ForEach(Language.all) { language in
                        Text(language.displayName).tag(language.code)
                    }
                }
                Text("With “Auto Detect”, the language is detected on-device. Text already in the target language is translated to the alternate target instead.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Shortcut") {
                Picker("Translate selection", selection: $settings.hotkeyID) {
                    ForEach(HotkeyOption.allCases) { option in
                        Text(option.label).tag(option.rawValue)
                    }
                }
                Text("⌥T (recommended) doesn’t clash with normal app shortcuts. ⌘T would override “new tab” and ⇧⌘T “reopen closed tab” in browsers while this app is running.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Instruction") {
                TextEditor(text: $settings.promptTemplate)
                    .font(.system(size: 12, design: .monospaced))
                    .frame(minHeight: 130)
                HStack {
                    Text("Placeholders: {from}, {to}")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Reset to Default") {
                        settings.promptTemplate = AppSettings.defaultPrompt
                    }
                }
            }

            Section("General") {
                Toggle("Launch at login", isOn: Binding(
                    get: { loginEnabled },
                    set: { setLaunchAtLogin($0) }
                ))
                if let loginError {
                    Text(loginError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 540, height: 660)
        .onAppear {
            isCustomModel = currentProvider.hasModelPresets
                ? !currentProvider.models.contains(settings.model)
                : true
        }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            loginEnabled = enabled
            loginError = nil
        } catch {
            loginEnabled = SMAppService.mainApp.status == .enabled
            loginError = "Could not update login item: \(error.localizedDescription). Run the packaged app (make app), not the bare binary."
        }
    }
}
