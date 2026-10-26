import AppKit
import XCTest
@testable import LLMTranslator

final class TranslationWindowTests: XCTestCase {
    @MainActor
    func testMultiplePinnedResultsSurviveNewTranslationAndDismissal() throws {
        _ = NSApplication.shared
        let controller = TranslationPopupController()
        let first = result("**First**")
        controller.show(session: first, at: NSPoint(x: 100, y: 600))
        let firstWindow = try XCTUnwrap(controller.transient)
        controller.togglePin(firstWindow)
        defer { firstWindow.close() }

        let second = result("## Second")
        controller.show(session: second, at: NSPoint(x: 550, y: 600))
        let secondWindow = try XCTUnwrap(controller.transient)
        controller.togglePin(secondWindow)
        defer { secondWindow.close() }

        XCTAssertEqual(controller.pinned.count, 2)
        XCTAssertNil(controller.transient)
        XCTAssertTrue(firstWindow.session === first)
        XCTAssertTrue(secondWindow.session === second)
        XCTAssertEqual(firstWindow.panel?.level, .statusBar)
        XCTAssertEqual(secondWindow.panel?.level, .statusBar)

        controller.show(session: result("Third"), at: NSPoint(x: 100, y: 350))
        controller.hide()
        firstWindow.dismissIfTransient()
        secondWindow.dismissIfTransient()
        XCTAssertEqual(controller.pinned.count, 2)
        XCTAssertTrue(firstWindow.panel?.isVisible == true)
        XCTAssertTrue(secondWindow.panel?.isVisible == true)
        XCTAssertEqual(first.output, "**First**")
        XCTAssertEqual(second.output, "## Second")

        firstWindow.close()
        XCTAssertEqual(controller.pinned.count, 1)
        XCTAssertTrue(secondWindow.panel?.isVisible == true)
    }

    @MainActor
    func testUnpinReplacesOnlyTransientAndRestoresDismissal() throws {
        _ = NSApplication.shared
        let controller = TranslationPopupController()
        controller.show(session: result("Pinned"), at: NSPoint(x: 100, y: 600))
        let pinned = try XCTUnwrap(controller.transient)
        controller.togglePin(pinned)
        controller.show(session: result("Temporary"), at: NSPoint(x: 550, y: 600))
        let temporary = try XCTUnwrap(controller.transient)

        controller.togglePin(pinned)
        XCTAssertTrue(controller.transient === pinned)
        XCTAssertTrue(controller.pinned.isEmpty)
        XCTAssertFalse(pinned.state.isPinned)
        XCTAssertFalse(temporary.panel?.isVisible == true)
        pinned.dismissIfTransient()
        XCTAssertNil(controller.transient)
        XCTAssertFalse(pinned.panel?.isVisible == true)
    }

    @MainActor
    func testInputBarTransfersLiveSessionWithoutSharingNextResult() throws {
        let model = InputBarModel(fromCode: "en", toCode: "zh-Hans")
        model.input = "Source text"
        model.session.output = "# Partial"
        model.session.phase = .translating
        let original = model.session
        let transferred = try XCTUnwrap(model.takeResultForPinning())
        XCTAssertTrue(transferred === original)
        XCTAssertFalse(model.session === original)
        XCTAssertEqual(transferred.phase, .translating)
        XCTAssertEqual(model.session.phase, .idle)
        XCTAssertEqual(model.input, "Source text")

        transferred.output += " output"
        model.session.output = "Next translation"
        XCTAssertEqual(transferred.output, "# Partial output")
        XCTAssertEqual(model.session.output, "Next translation")
    }

    @MainActor
    func testEmptyResultCannotBePinnedFromInputBar() {
        let model = InputBarModel(fromCode: "en", toCode: "zh-Hans")
        let session = model.session
        XCTAssertNil(model.takeResultForPinning())
        XCTAssertTrue(model.session === session)
    }

    @MainActor
    func testClosingWindowReleasesControllerAndSession() throws {
        _ = NSApplication.shared
        let controller = TranslationPopupController()
        weak var releasedWindow: TranslationResultWindowController?
        weak var releasedSession: TranslationSession?
        autoreleasepool {
            let session = result("Close me")
            controller.show(session: session, at: NSPoint(x: 100, y: 600))
            let window = controller.transient!
            releasedWindow = window
            releasedSession = session
            controller.togglePin(window)
            window.close()
        }
        XCTAssertTrue(controller.pinned.isEmpty)
        XCTAssertNil(controller.transient)
        XCTAssertNil(releasedWindow)
        // SwiftUI may retain the view/session until its next layout transaction.
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        XCTAssertNil(releasedSession)
    }

    @MainActor
    private func result(_ text: String) -> TranslationSession {
        let session = TranslationSession()
        session.output = text
        session.pairLabel = "English → 简体中文"
        session.phase = .done
        return session
    }
}
