import AppKit
import ApplicationServices
import SwiftUI

/// Floating, non-activating panel that shows the translation next to the
/// mouse cursor. The frontmost app keeps focus while it is visible.
@MainActor
final class TranslationPopupController {
    static let shared = TranslationPopupController()

    private let session: TranslationSession
    private var panel: NSPanel?
    private var monitors: [Any] = []
    private var anchorTop: CGFloat = 0
    private let width: CGFloat = 420

    private init() {
        session = TranslationSession()
    }

    func show(text: String?, at point: NSPoint) {
        session.start(text: text)
        present(at: point)
    }

    func showPermissionHint(at point: NSPoint) {
        session.showNeedsPermission()
        present(at: point)
    }

    func hide() {
        session.cancel()
        panel?.orderOut(nil)
        removeMonitors()
    }

    private func present(at point: NSPoint) {
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
        installMonitors()
    }

    private func contentSizeChanged(_ size: CGSize) {
        guard let panel, panel.isVisible else { return }
        var frame = panel.frame
        guard abs(frame.height - size.height) > 0.5 || abs(frame.width - size.width) > 0.5 else { return }

        let visible = screenContaining(NSPoint(x: frame.midX, y: frame.midY))?.visibleFrame
        frame.size = size
        // Keep the top edge anchored so the popup grows downward from the cursor.
        frame.origin.y = anchorTop - size.height
        if let visible, frame.origin.y < visible.minY + 8 {
            frame.origin.y = visible.minY + 8
        }
        panel.setFrame(frame, display: true)
    }

    private func ensurePanel() -> NSPanel {
        if let panel { return panel }

        let panel = NSPanel(
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

        let root = PopupView(
            session: session,
            onClose: { [weak self] in self?.hide() },
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

        // A global key monitor only delivers events once Accessibility is
        // granted — which is exactly when the popup is usable anyway.
        if AccessibilityPermission.granted {
            let escMonitor = NSEvent.addGlobalMonitorForEvents(
                matching: [.keyDown],
                handler: { [weak self] event in
                    if event.keyCode == 53 { // Esc
                        Task { @MainActor in self?.hide() }
                    }
                }
            )
            if let escMonitor { monitors.append(escMonitor) }
        }

        let localMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .keyDown],
            handler: { [weak self] event in
                guard let self else { return event }
                if event.type == .keyDown {
                    if event.keyCode == 53, self.panel?.isVisible == true {
                        self.hide()
                        return nil
                    }
                    return event
                }
                if event.window !== self.panel {
                    self.hideIfClickedOutside()
                }
                return event
            }
        )
        if let localMonitor { monitors.append(localMonitor) }
    }

    private func hideIfClickedOutside() {
        guard let panel, panel.isVisible else { return }
        if !panel.frame.contains(NSEvent.mouseLocation) {
            hide()
        }
    }

    private func removeMonitors() {
        monitors.forEach { NSEvent.removeMonitor($0) }
        monitors.removeAll()
    }
}

struct PopupView: View {
    @ObservedObject var session: TranslationSession
    let onClose: () -> Void
    let onSize: (CGSize) -> Void

    @State private var copied = false

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
                    "Accessibility permission is required to read the selected text.",
                    systemImage: "lock.shield"
                )
                .font(.system(size: 12))
                .fixedSize(horizontal: false, vertical: true)
                Button("Open Accessibility Settings") {
                    let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
                    NSWorkspace.shared.open(url)
                }
                Text("Enable “LLM Translator”, then press \(AppSettings.shared.hotkeyOption.label) again.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
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
