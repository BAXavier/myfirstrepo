import AppKit
import SwiftUI

/// Menu-bar-only app (LSUIElement): no Dock icon, no window until you need one.
@main
struct QuickCaptureMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var capture = CaptureController.shared

    var body: some Scene {
        MenuBarExtra {
            MenuContent(capture: capture)
        } label: {
            Image(systemName: capture.isListening ? "waveform.circle.fill" : "checklist")
        }

        Settings {
            SettingsView().frame(width: 460, height: 600)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        MainActor.assumeIsolated {
            HUD.shared.bind(to: CaptureController.shared)
            TriggerMonitor.shared.start()
        }
    }
}

private struct MenuContent: View {
    @ObservedObject var capture: CaptureController

    var body: some View {
        Button(capture.isListening ? "Finish Capture" : "Capture  (⌥ ⌥ ⌥)") { capture.toggle() }
        if !capture.history.isEmpty {
            Divider()
            Text("Recent")
            ForEach(capture.history.prefix(5)) { entry in
                Button("\(entry.summary) — \(entry.transcript.prefix(40))") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(entry.transcript, forType: .string)
                }
            }
        }
        Divider()
        SettingsLink { Text("Settings…") }.keyboardShortcut(",")
        Button("Quit") { NSApp.terminate(nil) }.keyboardShortcut("q")
    }
}
