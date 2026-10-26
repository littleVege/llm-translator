import ApplicationServices

/// Permission checks use the running process's identity, not the visible switch
/// in System Settings. After an ad-hoc update those identities may differ.
@MainActor
final class AccessibilityPermission {
    static let shared = AccessibilityPermission()

    private let checkTrust: (_ prompt: Bool) -> Bool
    private var hasRequestedPrompt = false

    init(checkTrust: @escaping (Bool) -> Bool = { prompt in
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }) {
        self.checkTrust = checkTrust
    }

    var granted: Bool { checkTrust(false) }

    func ensure() -> Bool {
        // Always recheck: the user may have granted access since the last try.
        guard !granted else { return true }
        guard !hasRequestedPrompt else { return false }
        hasRequestedPrompt = true
        // The system dialog is asynchronous. Its return value only describes
        // current trust; opening Settings does not itself grant permission.
        return checkTrust(true)
    }
}
