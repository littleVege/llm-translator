import AppKit
import SwiftUI
import XCTest
@testable import LLMTranslator

final class MarkdownLayoutTests: XCTestCase {
    @MainActor
    func testMarkdownFitsPopupWidthInBothAppearances() throws {
        _ = NSApplication.shared
        for scheme in [ColorScheme.light, .dark] {
            let view = NSHostingView(rootView:
                TranslationMarkdownView(text: Self.sample)
                    .frame(width: 392, alignment: .leading)
                    .padding(14)
                    .background(scheme == .dark ? Color.black : Color.white)
                    .environment(\.colorScheme, scheme)
            )
            let panel = NSPanel(
                contentRect: NSRect(origin: .zero, size: view.fittingSize),
                styleMask: [.borderless], backing: .buffered, defer: false
            )
            panel.isReleasedWhenClosed = false
            panel.contentView = view
            defer { panel.contentView = nil; panel.close() }
            for _ in 0..<3 {
                settleLayout()
                panel.setContentSize(view.fittingSize)
                view.layoutSubtreeIfNeeded()
            }
            let size = view.fittingSize
            XCTAssertEqual(size.width, 420, accuracy: 1)
            XCTAssertGreaterThan(size.height, 400)
            XCTAssertLessThan(size.height, 1800)
            try saveSnapshot(view, named: "markdown-\(scheme)")
        }
    }

    @MainActor
    func testLongStreamingOutputStaysWithinPopupHeight() throws {
        _ = NSApplication.shared
        let controller = TranslationPopupController()
        let session = TranslationSession()
        session.phase = .translating
        session.output = "# First chunk"
        controller.show(session: session, at: NSPoint(x: 100, y: 700))
        let window = try XCTUnwrap(controller.transient)
        defer { window.close() }
        settleLayout()
        let initialHeight = try XCTUnwrap(window.panel).frame.height
        // An incomplete fenced block is a normal intermediate streaming state.
        session.output = Self.sample + "\n\n```swift\n" + String(repeating: "print(\"流式翻译\")\n", count: 80)
        settleLayout()
        let panel = try XCTUnwrap(window.panel)
        XCTAssertEqual(panel.frame.width, 420, accuracy: 1)
        XCTAssertGreaterThan(panel.frame.height, initialHeight)
        XCTAssertLessThanOrEqual(panel.frame.height, 410)
        try saveSnapshot(try XCTUnwrap(panel.contentView), named: "streaming-popup")
    }

    @MainActor
    private func settleLayout() {
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
    }

    @MainActor
    private func saveSnapshot(_ view: NSView, named name: String) throws {
        guard let path = ProcessInfo.processInfo.environment["LLM_TRANSLATOR_SNAPSHOT_DIRECTORY"] else { return }
        let directory = URL(fileURLWithPath: path, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        let data = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        try data.write(to: directory.appendingPathComponent("\(name).png"))
    }

    private static let sample = """
    # Markdown 翻译结果

    **重点内容**、*斜体*、~~删除线~~与 `inline code`。
    保留原文换行，支持 [链接](https://example.com)。

    ## 清单与引用

    - 第一项内容
      - 嵌套项目
    - 第二项内容

    1. 开始翻译
    2. 固定多个结果

    > 置顶窗口可拖动，切换应用后仍然保留。

    - [x] Markdown 渲染
    - [ ] 下一项任务

    ```swift
    let message = "这是一行很长的代码，用来检查横向滚动是否保留完整的原始内容，而不会把固定宽度的浮窗撑开。"
    print(message)
    ```

    | 功能 | 说明 | 状态 | 备注 |
    | --- | --- | --- | --- |
    | Markdown | 标题、列表和代码块 | 已支持 | 保留原始源码 |
    | Pin | 多个独立置顶窗口 | 已支持 | 点击外部不会关闭 |

    ---

    普通段落仍然可以选中和复制。
    """
}
