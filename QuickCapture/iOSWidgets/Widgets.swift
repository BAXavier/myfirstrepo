import AppIntents
import SwiftUI
import WidgetKit

@main
struct QuickCaptureWidgets: WidgetBundle {
    var body: some Widget {
        CaptureControl()
        CaptureLauncher()
    }
}

/// Control Center, Lock Screen and Action Button control (iOS 18+).
struct CaptureControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "QuickCaptureControl") {
            ControlWidgetButton(action: StartCaptureIntent()) {
                Label("Quick Capture", systemImage: "mic.fill")
            }
        }
        .displayName("Quick Capture")
        .description("Start dictating a note that becomes to-dos.")
    }
}

/// Static launcher for the Lock Screen and Home Screen. No timeline refreshes: it never changes.
struct CaptureLauncher: Widget {
    struct Entry: TimelineEntry { let date = Date.distantPast }

    struct Provider: TimelineProvider {
        func placeholder(in context: Context) -> Entry { Entry() }
        func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) { completion(Entry()) }
        func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
            completion(Timeline(entries: [Entry()], policy: .never))
        }
    }

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "QuickCaptureLauncher", provider: Provider()) { _ in
            LauncherView()
                .widgetURL(URL(string: "quickcapture://record"))
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Quick Capture")
        .description("One tap to start talking.")
        .supportedFamilies([.accessoryCircular, .systemSmall])
    }
}

private struct LauncherView: View {
    @Environment(\.widgetFamily) private var family

    var body: some View {
        if family == .accessoryCircular {
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: "mic.fill").font(.title2)
            }
        } else {
            VStack(spacing: 8) {
                Image(systemName: "mic.circle.fill").font(.system(size: 48)).foregroundStyle(.red)
                Text("Capture").font(.headline)
            }
        }
    }
}
