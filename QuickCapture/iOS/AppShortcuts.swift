import AppIntents

/// Runs without opening the app: pair with Shortcuts' "Dictate Text" (or any text source) for a
/// zero-UI capture from Siri, Back Tap, the Action Button, or a Watch shortcut.
struct CaptureTextIntent: AppIntent {
    static let title: LocalizedStringResource = "Capture Text as Tasks"
    static let description = IntentDescription("Turns text into to-dos and sends them to your task apps.")

    @Parameter(title: "Text", inputOptions: String.IntentInputOptions(multiline: true))
    var text: String

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<String> {
        let entry = await CapturePipeline.process(text)
        CaptureController.shared.record(entry)
        return .result(value: entry.summary, dialog: "\(entry.summary)")
    }
}

struct QuickCaptureShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: StartCaptureIntent(),
                    phrases: ["Capture with \(.applicationName)", "New \(.applicationName) note"],
                    shortTitle: "Quick Capture",
                    systemImageName: "mic.fill")
        AppShortcut(intent: CaptureTextIntent(),
                    phrases: ["Add tasks with \(.applicationName)"],
                    shortTitle: "Capture Text",
                    systemImageName: "text.badge.plus")
    }
}
