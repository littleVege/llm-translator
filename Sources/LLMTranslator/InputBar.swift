import AppKit
import Combine
import SwiftUI

/// Spotlight-style floating input bar, opened by left-clicking the status
/// bar icon. Type text, press Return to translate; Esc or clicking away
/// closes it.
@MainActor
final class InputBarController {
    static let shared = InputBarController()

    private let model: InputBarModel
    private var panel: KeyablePanel?
    private var anchorTop: CGFloat = 0
    private var resignObserver: NSObjectProtocol?
    private var localMonitor: Any?
    private let width: CGFloat = 640

    private init() {
        model = InputBarModel()
    }

    var isKey: Bool { panel?.isKeyWindow == true }

    func toggle() {
        if panel?.isVisible == true {
            hide()
        } else {
            show()
        }
    }

    func show() {
        let panel = ensurePanel()

        let fitting = panel.contentView?.fittingSize ?? NSSize(width: width, height: 64)
        panel.setContentSize(fitting)

        let mouse = NSEvent.mouseLocation
        guard let screen = screenContaining(mouse) else { return }
        let visible = screen.visibleFrame
        let top = visible.minY + visible.height * 0.68
        anchorTop = top
        panel.setFrameOrigin(NSPoint(
            x: visible.midX - fitting.width / 2,
            y: top - fitting.height
        ))

        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        model.focusTick += 1
        installMonitors()
    }

    func hide() {
        panel?.orderOut(nil)
        removeMonitors()
    }

    func translateCurrent() {
        model.translate()
    }

    private func pinResult() {
        guard let session = model.takeResultForPinning() else { return }
        let point = panel.map { NSPoint(x: $0.frame.minX - 14, y: $0.frame.maxY + 14) }
            ?? NSEvent.mouseLocation
        TranslationPopupController.shared.pin(session: session, at: point)
        hide()
    }

    private func contentSizeChanged(_ size: CGSize) {
        guard let panel, panel.isVisible else { return }
        var frame = panel.frame
        guard abs(frame.height - size.height) > 0.5 || abs(frame.width - size.width) > 0.5 else { return }

        let visible = screenContaining(NSPoint(x: frame.midX, y: frame.midY))?.visibleFrame
        frame.size = size
        frame.origin.y = anchorTop - size.height
        if let visible, frame.origin.y < visible.minY + 8 {
            frame.origin.y = visible.minY + 8
        }
        panel.setFrame(frame, display: true)
    }

    private func ensurePanel() -> KeyablePanel {
        if let panel { return panel }

        let panel = KeyablePanel(
            contentRect: NSRect(x: 0, y: 0, width: width, height: 64),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let root = InputBarView(
            model: model,
            onPin: { [weak self] in self?.pinResult() },
            onSize: { [weak self] size in self?.contentSizeChanged(size) }
        )
        panel.contentView = NSHostingView(rootView: root)

        self.panel = panel
        return panel
    }

    private func installMonitors() {
        removeMonitors()

        resignObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification,
            object: panel,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.hide() }
        }

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            guard let self, event.keyCode == 53, self.panel?.isKeyWindow == true else { return event }
            self.hide()
            return nil
        }
    }

    private func removeMonitors() {
        if let observer = resignObserver {
            NotificationCenter.default.removeObserver(observer)
            resignObserver = nil
        }
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
            localMonitor = nil
        }
    }
}

@MainActor
final class InputBarModel: ObservableObject {
    @Published var input = ""
    @Published var fromCode: String
    @Published var toCode: String
    @Published var focusTick = 0

    @Published private(set) var session: TranslationSession

    init(
        fromCode: String = AppSettings.shared.sourceCode,
        toCode: String = AppSettings.shared.targetCode
    ) {
        self.fromCode = fromCode
        self.toCode = toCode
        self.session = TranslationSession()
    }

    func takeResultForPinning() -> TranslationSession? {
        guard !session.output.isEmpty else { return nil }
        let result = session
        session = TranslationSession()
        return result
    }

    func translate() {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        session.start(text: text, from: Language.byCode(fromCode), to: Language.byCode(toCode))
    }

    func swap() {
        let settings = AppSettings.shared
        let previousFrom = fromCode
        fromCode = toCode
        if previousFrom == Language.auto.code {
            var candidate = settings.altTargetCode
            if candidate == fromCode { candidate = settings.targetCode }
            if candidate == fromCode { candidate = fromCode == "en" ? "zh-Hans" : "en" }
            toCode = candidate
        } else {
            toCode = previousFrom
        }
    }
}

struct InputBarView: View {
    @ObservedObject var model: InputBarModel
    let onPin: () -> Void
    let onSize: (CGSize) -> Void

    var body: some View {
        InputBarContentView(model: model, session: model.session, onPin: onPin, onSize: onSize)
    }
}

private struct InputBarContentView: View {
    @ObservedObject var model: InputBarModel
    @ObservedObject var session: TranslationSession
    let onPin: () -> Void
    let onSize: (CGSize) -> Void

    @FocusState private var focused: Bool
    @State private var copied = false

    private var canSend: Bool {
        !model.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "translate")
                    .font(.system(size: 16))
                    .foregroundStyle(.secondary)
                TextField("Translate text…", text: $model.input, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 15))
                    .lineLimit(1...4)
                    .focused($focused)
                    .onSubmit { model.translate() }
                Button(action: { model.translate() }) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(canSend ? Color.accentColor : Color.secondary)
                }
                .buttonStyle(.plain)
                .disabled(!canSend)
            }

            HStack(spacing: 8) {
                Picker("", selection: $model.fromCode) {
                    Text(Language.auto.displayName).tag(Language.auto.code)
                    ForEach(Language.all) { language in
                        Text(language.displayName).tag(language.code)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .fixedSize()

                Button(action: { model.swap() }) {
                    Image(systemName: "arrow.left.arrow.right")
                        .font(.system(size: 11))
                }
                .buttonStyle(.borderless)
                .help("Swap languages")

                Picker("", selection: $model.toCode) {
                    ForEach(Language.all) { language in
                        Text(language.displayName).tag(language.code)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .fixedSize()

                Spacer()

                if session.phase == .translating {
                    ProgressView()
                        .controlSize(.small)
                }
                if !session.output.isEmpty {
                    Button(action: onPin) {
                        Label("Pin", systemImage: "pin")
                            .font(.caption)
                    }
                    .buttonStyle(.borderless)
                    .help("Pin translation in a separate window on top")
                    Button {
                        session.copyOutput()
                        copied = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { copied = false }
                    } label: {
                        Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                            .font(.caption)
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(copied ? .green : .secondary)
                }
            }

            if showsResult {
                Divider()
                resultView
            }
        }
        .padding(14)
        .frame(width: 640)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(.separator, lineWidth: 1)
        )
        .reportSize(onSize)
        .onAppear { focused = true }
        .onChange(of: model.focusTick) { _, _ in focused = true }
    }

    private var showsResult: Bool {
        switch session.phase {
        case .translating, .done, .failed:
            return true
        default:
            return false
        }
    }

    @ViewBuilder
    private var resultView: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !session.pairLabel.isEmpty {
                Text(session.pairLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            switch session.phase {
            case .failed(let message):
                if !session.output.isEmpty {
                    OutputTextView(text: session.output, maxHeight: 300)
                }
                Label(message, systemImage: "exclamationmark.triangle")
                    .font(.system(size: 12))
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            default:
                if session.output.isEmpty {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Translating…")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                } else {
                    OutputTextView(
                        text: session.output,
                        maxHeight: 300,
                        followsLatest: session.phase == .translating
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
