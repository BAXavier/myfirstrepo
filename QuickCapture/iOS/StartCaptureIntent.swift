import AppIntents
import Foundation

// Compiled into both the app and the widget extension so Control Center / Lock Screen controls can use it.
// `openAppWhenRun` makes it execute in the app process, which then starts listening immediately.

extension Notification.Name {
    static let startCapture = Notification.Name("QuickCapture.startCapture")
}

@MainActor
enum CaptureRequest {
    /// Set when the intent runs before the UI is ready (cold launch); consumed by the app on activation.
    static var pending = false
}

struct StartCaptureIntent: AppIntent {
    static let title: LocalizedStringResource = "Quick Capture"
    static let description = IntentDescription("Start dictating a note that becomes to-dos.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        CaptureRequest.pending = true
        NotificationCenter.default.post(name: .startCapture, object: nil)
        return .result()
    }
}
