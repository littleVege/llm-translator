import AppKit
import ApplicationServices
import SwiftUI

/// Owns one dismissible result and any number of independently pinned results.
@MainActor
final class TranslationPopupController {
    static let shared = TranslationPopupController()

    private(set) var transient: TranslationResultWindowController?
    private(set) var pinned: [UUID: TranslationResultWindowController] = [:]

    func show(text: String?, at point: NSPoint) {
        let session = TranslationSession()
        session.start(text: text)
        show(session: session, at: point)
    }

    func showPermissionHint(at point: NSPoint) {
        let session = TranslationSession()
        session.showNeedsPermission()
        show(session: session, at: point)
    }

    func show(session: TranslationSession, at point: NSPoint) {
        hide()
        let window = makeWindow(session: session)
        transient = window
        window.present(at: point)
    }

    /// Takes ownership of the input bar's session, including an active stream.
    func pin(session: TranslationSession, at point: NSPoint) {
        let window = makeWindow(session: session)
        pinned[window.id] = window
        window.setPinned(true)
        window.present(at: point)
    }

    func hide() {
        transient?.close()
    }

    func togglePin(_ window: TranslationResultWindowController) {
        if window.state.isPinned {
            hide()
            transient = window
            pinned.removeValue(forKey: window.id)
            window.setPinned(false)
        } else {
            pinned[window.id] = window
            if transient === window { transient = nil }
            window.setPinned(true)
        }
    }

    private func makeWindow(session: TranslationSession) -> TranslationResultWindowController {
        TranslationResultWindowController(
            session: session,
            onTogglePin: { [weak self] window in self?.togglePin(window) },
            onClose: { [weak self] id in
                if self?.transient?.id == id { self?.transient = nil }
                self?.pinned.removeValue(forKey: id)
            }
        )
    }
}

@MainActor
final class TranslationWindowState: ObservableObject {
    @Published var isPinned = false
}

/// Each panel retains its own session so later requests cannot replace it.
@MainActor
final class TranslationResultWindowController: NSObject, NSWindowDelegate {
    let id = UUID()
    let session: TranslationSession
    let state = TranslationWindowState()
    private(set) var panel: NSPanel?

    private let onTogglePin: (TranslationResultWindowController) -> Void
    private let onClose: (UUID) -> Void
    private var monitors: [Any] = []
    private var anchorTop: CGFloat = 0
    private let width: CGFloat = 420

    init(
        session: TranslationSession,
        onTogglePin: @escaping (TranslationResultWindowController) -> Void,
        onClose: @escaping (UUID) -> Void
    ) {
        self.session = session
        self.onTogglePin = onTogglePin
        self.onClose = onClose
    }

    func close() {
        session.cancel()
        panel?.orderOut(nil)
        removeMonitors()
        // NSApplication can retain ordered-out panels; detach the hosting view
        // so a closed result releases its SwiftUI tree and translation session.
        panel?.contentView = nil
        panel?.close()
        panel = nil
        onClose(id)
    }

    func setPinned(_ pinned: Bool) {
        state.isPinned = pinned
        if pinned {
            removeMonitors()
        } else if panel?.isVisible == true {
            installMonitors()
        }
    }

    func present(at point: NSPoint) {
        let panel = ensurePanel()
        let fitting = panel.contentView?.fittingSize ?? NSSize(width: width, height: 120)
        panel.setContentSize(fitting)

        guard let screen = screenContaining(point) else { return }
        let visible = screen.visibleFrame
        var x = point.x + 14
        if x + fitting.width > visible.maxX { x = visible.maxX - fitting.width - 10 }
        x = max(x, visible.minX + 10)

        var top = point.y - 14
        if top - fitting.height < visible.minY {
            top = min(point.y + 14 + fitting.height, visible.maxY - 10)
        }
        top = min(top, visible.maxY - 10)
        anchorTop = top
        panel.setFrameOrigin(NSPoint(x: x, y: top - fitting.height))
        panel.orderFrontRegardless()
        if !state.isPinned { installMonitors() }
    }

    func windowDidMove(_ notification: Notification) {
        // A user can drag a pinned result while it is still streaming.
        // Subsequent size changes must grow from the new position.
        if let panel { anchorTop = panel.frame.maxY }
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

    private func ensurePanel() -> NSPanel {
        if let panel { return panel }
        let panel = KeyablePanel(
            contentRect: NSRect(x: 0, y: 0, width: width, height: 120),
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
        panel.becomesKeyOnlyIfNeeded = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.delegate = self

        let root = PopupView(
            session: session,
            windowState: state,
            onTogglePin: { [weak self] in
                guard let self else { return }
                self.onTogglePin(self)
            },
            onClose: { [weak self] in self?.close() },
            onSize: { [weak self] size in self?.contentSizeChanged(size) }
        )
        panel.contentView = NSHostingView(rootView: root)
        self.panel = panel
        return panel
    }

    private func installMonitors() {
        removeMonitors()
        let clickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown],
            handler: { [weak self] _ in
                Task { @MainActor in self?.hideIfClickedOutside() }
            }
        )
        if let clickMonitor { monitors.append(clickMonitor) }

        if AccessibilityPermission.shared.granted {
            let escMonitor = NSEvent.addGlobalMonitorForEvents(
                matching: [.keyDown],
                handler: { [weak self] event in
                    if event.keyCode == 53 {
                        Task { @MainActor in self?.dismissIfTransient() }
                    }
                }
            )
            if let escMonitor { monitors.append(escMonitor) }
        }

        let localMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .keyDown],
            handler: { [weak self] event in
                guard let self, !self.state.isPinned else { return event }
                if event.type == .keyDown {
                    // Do not swallow Esc intended for another pinned result or input bar.
                    if event.keyCode == 53, event.window === self.panel,
                       self.panel?.isVisible == true {
                        self.dismissIfTransient()
                        return nil
                    }
                    return event
                }
                if event.window !== self.panel { self.hideIfClickedOutside() }
                return event
            }
        )
        if let localMonitor { monitors.append(localMonitor) }
    }

    func dismissIfTransient() {
        // Also protects against a global-monitor callback queued just before pinning.
        guard !state.isPinned else { return }
        close()
    }

    private func hideIfClickedOutside() {
        guard let panel, panel.isVisible else { return }
        if !panel.frame.contains(NSEvent.mouseLocation) { dismissIfTransient() }
    }

    private func removeMonitors() {
        monitors.forEach { NSEvent.removeMonitor($0) }
        monitors.removeAll()
    }
}

struct PopupView: View {
    @ObservedObject var session: TranslationSession
    @ObservedObject var windowState: TranslationWindowState
    let onTogglePin: () -> Void
    let onClose: () -> Void
    let onSize: (CGSize) -> Void

    @State private var copied = false
    @State private var accessibilityGranted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            Divider()
            content
        }
        .padding(14)
        .frame(width: 420, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(.separator, lineWidth: 1)
        )
        .reportSize(onSize)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "translate")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Text(session.pairLabel.isEmpty ? "LLM Translator" : session.pairLabel)
                .font(.caption)
                .foregroundStyle(.secondary)
            if session.phase == .translating {
                ProgressView()
                    .controlSize(.mini)
            }
            Spacer()
            if !session.output.isEmpty {
                Button(action: onTogglePin) {
                    Image(systemName: windowState.isPinned ? "pin.fill" : "pin")
                        .font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .foregroundStyle(windowState.isPinned ? Color.accentColor : .secondary)
                .help(windowState.isPinned ? "Unpin translation" : "Pin translation on top")
                .accessibilityLabel(windowState.isPinned ? "Unpin translation" : "Pin translation on top")
                Button {
                    session.copyOutput()
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { copied = false }
                } label: {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .foregroundStyle(copied ? .green : .secondary)
                .help("Copy translation")
            }
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 11))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Close")
        }
    }

    @ViewBuilder
    private var content: some View {
        switch session.phase {
        case .noSelection:
            Label(
                "No text selected. Select some text, then press \(AppSettings.shared.hotkeyOption.label).",
                systemImage: "cursorarrow.rays"
            )
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

        case .needsPermission:
            VStack(alignment: .leading, spacing: 8) {
                Label(
                    accessibilityGranted
                        ? "Accessibility access is available. Select text and try the shortcut again."
                        : "macOS has not authorized this copy of LLM Translator to read selected text.",
                    systemImage: accessibilityGranted ? "checkmark.shield" : "lock.shield"
                )
                .font(.system(size: 12))
                .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button("Open Accessibility Settings") {
                        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
                        NSWorkspace.shared.open(url)
                    }
                    Button("Check Again") {
                        accessibilityGranted = AccessibilityPermission.shared.granted
                    }
                }
                if !accessibilityGranted {
                    Text("Already enabled after an update? Quit LLM Translator, remove its old entry with −, then add this app again with + and enable it. Reopen the app afterward.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Show This App in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
                    }
                    Text(Bundle.main.bundleURL.path)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("You can also copy the text yourself and use Translate Clipboard from the menu bar.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .onAppear {
                accessibilityGranted = AccessibilityPermission.shared.granted
            }

        case .failed(let message):
            VStack(alignment: .leading, spacing: 8) {
                if !session.output.isEmpty {
                    OutputTextView(text: session.output)
                }
                Label(message, systemImage: "exclamationmark.triangle")
                    .font(.system(size: 12))
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

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
                OutputTextView(text: session.output, followsLatest: session.phase == .translating)
            }
        }
    }
}
