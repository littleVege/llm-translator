import AppKit

// Top-level code runs on the main thread but is not statically
// MainActor-isolated, so hop explicitly before touching AppKit.
MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
}
