import AppKit
import SwiftUI

/// Borderless panel that can still take keyboard focus (for the input bar).
final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

@MainActor
func screenContaining(_ point: NSPoint) -> NSScreen? {
    NSScreen.screens.first { NSMouseInRect(point, $0.frame, false) }
        ?? NSScreen.main
        ?? NSScreen.screens.first
}

struct ContentSizeKey: PreferenceKey {
    static var defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        value = nextValue()
    }
}

struct TextHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

extension View {
    /// Reports the laid-out size of this view so the hosting panel can be
    /// resized to fit as streamed content grows.
    func reportSize(_ onChange: @escaping (CGSize) -> Void) -> some View {
        background(
            GeometryReader { proxy in
                Color.clear.preference(key: ContentSizeKey.self, value: proxy.size)
            }
        )
        .onPreferenceChange(ContentSizeKey.self, perform: onChange)
    }
}

/// Streamed translation text: natural height while short, scrolls when long.
struct OutputTextView: View {
    let text: String
    var maxHeight: CGFloat = 340
    var followsLatest = false

    @State private var contentHeight: CGFloat = 0
    private let bottomID = "translation-output-bottom"

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    Text(text)
                        .font(.system(size: 13))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            GeometryReader { geometry in
                                Color.clear.preference(
                                    key: TextHeightKey.self,
                                    value: geometry.size.height
                                )
                            }
                        )
                    Color.clear
                        .frame(height: 1)
                        .id(bottomID)
                }
            }
            .onChange(of: text) { _, _ in
                guard followsLatest else { return }
                // Run after SwiftUI has laid out the newly appended text.
                DispatchQueue.main.async {
                    proxy.scrollTo(bottomID, anchor: .bottom)
                }
            }
        }
        .frame(height: min(max(contentHeight, 22), maxHeight))
        .onPreferenceChange(TextHeightKey.self) { contentHeight = $0 }
    }
}
