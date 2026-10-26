import XCTest
@testable import LLMTranslator

final class AccessibilityPermissionTests: XCTestCase {
    @MainActor
    func testRepeatedShortcutDoesNotRepeatSystemPromptWhenTrustIsDenied() {
        var prompts = 0
        let permission = AccessibilityPermission { prompt in
            if prompt { prompts += 1 }
            return false
        }
        for _ in 0..<5 { XCTAssertFalse(permission.ensure()) }
        XCTAssertEqual(prompts, 1, "Repeated shortcuts must not repeatedly request the system dialog")
    }

    @MainActor
    func testAlreadyAuthorizedNeverRequestsPrompt() {
        var prompts = 0
        let permission = AccessibilityPermission { prompt in
            if prompt { prompts += 1 }
            return true
        }
        XCTAssertTrue(permission.ensure())
        XCTAssertEqual(prompts, 0)
    }

    @MainActor
    func testAuthorizationIsRecheckedAfterUserChangesSystemSettings() {
        var trusted = false
        var prompts = 0
        let permission = AccessibilityPermission { prompt in
            if prompt { prompts += 1 }
            return trusted
        }
        XCTAssertFalse(permission.ensure())
        trusted = true
        XCTAssertTrue(permission.ensure())
        XCTAssertTrue(permission.granted)
        trusted = false
        XCTAssertFalse(permission.ensure())
        XCTAssertEqual(prompts, 1)
    }

    @MainActor
    func testPassiveChecksNeverTriggerPrompt() {
        var prompts = 0
        let permission = AccessibilityPermission { prompt in
            if prompt { prompts += 1 }
            return false
        }
        for _ in 0..<5 { XCTAssertFalse(permission.granted) }
        XCTAssertEqual(prompts, 0)
        XCTAssertFalse(permission.ensure())
        XCTAssertEqual(prompts, 1)
    }
}
