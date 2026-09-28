import CaptureKit
import SwiftUI

struct SettingsView: View {
    @AppStorage(Pref.extractor) private var extractor = ExtractorChoice.auto.rawValue
    @AppStorage(Pref.claudeModel) private var claudeModel = ""
    @AppStorage(Pref.useReminders) private var useReminders = true
    @AppStorage(Pref.remindersList) private var remindersList = ""
    @AppStorage(Pref.useTodoist) private var useTodoist = false
    @AppStorage(Pref.todoistProject) private var todoistProject = ""
    @AppStorage(Pref.useNotion) private var useNotion = false
    @AppStorage(Pref.notionDatabase) private var notionDatabase = ""
    @AppStorage(Pref.notionTitleProp) private var notionTitleProp = "Name"
    @AppStorage(Pref.notionDueProp) private var notionDueProp = ""
    @AppStorage(Pref.silenceSeconds) private var silenceSeconds = 1.8
    #if os(macOS)
    @AppStorage(Pref.tripleOptionEnabled) private var tripleOption = true
    @AppStorage(Pref.swirlEnabled) private var swirl = true
    #endif

    var body: some View {
        Form {
            #if os(macOS)
            Section("Triggers") {
                Toggle("Tap ⌥ Option three times", isOn: $tripleOption)
                Toggle("Swirl the mouse pointer twice", isOn: $swirl)
                Text("The ⌥ trigger needs Accessibility access (System Settings › Privacy & Security). While listening, tap ⌥ once to finish or press Esc to discard.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            #endif

            Section("Listening") {
                Stepper(String(format: "Auto-stop after %.1fs of silence", silenceSeconds),
                        value: $silenceSeconds, in: 0.8...5, step: 0.2)
            }

            Section("AI") {
                Picker("Convert with", selection: $extractor) {
                    ForEach(ExtractorChoice.allCases) { Text($0.label).tag($0.rawValue) }
                }
                if !OnDevice.isAvailable, extractor != ExtractorChoice.simple.rawValue {
                    Text("Apple Intelligence isn't available on this device; Claude is used when a key is set.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                SecretField(title: "Anthropic API key", secret: .anthropicKey)
                TextField("Claude model", text: $claudeModel, prompt: Text(ClaudeExtractor.defaultModel))
                    .autocorrectionDisabled()
            }

            Section("Send tasks to") {
                Toggle("Apple Reminders", isOn: $useReminders)
                if useReminders {
                    TextField("Default list", text: $remindersList, prompt: Text("System default"))
                }
                Toggle("Todoist", isOn: $useTodoist)
                if useTodoist {
                    SecretField(title: "Todoist API token", secret: .todoistToken)
                    TextField("Project ID", text: $todoistProject, prompt: Text("Inbox"))
                }
                Toggle("Notion", isOn: $useNotion)
                if useNotion {
                    SecretField(title: "Notion integration token", secret: .notionToken)
                    TextField("Database ID", text: $notionDatabase)
                    TextField("Title property", text: $notionTitleProp)
                    TextField("Date property", text: $notionDueProp, prompt: Text("optional, e.g. Due"))
                }
            }
        }
        .formStyle(.grouped)
    }
}

/// SecureField backed by the Keychain, saved on Return or when the field goes away.
private struct SecretField: View {
    let title: String
    let secret: Secret
    @State private var text = ""

    var body: some View {
        SecureField(title, text: $text)
            .autocorrectionDisabled()
            .onAppear { text = secret.value }
            .onSubmit { secret.value = text }
            .onDisappear { if text != secret.value { secret.value = text } }
    }
}
