import SwiftUI
import WidgetKit

/// Watch face complication / Smart Stack tile. Tapping it opens the app, which starts listening.
@main
struct QuickCaptureComplication: Widget {
    struct Entry: TimelineEntry { let date = Date.distantPast }

    struct Provider: TimelineProvider {
        func placeholder(in context: Context) -> Entry { Entry() }
        func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) { completion(Entry()) }
        func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
            completion(Timeline(entries: [Entry()], policy: .never))
        }
    }

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "QuickCaptureComplication", provider: Provider()) { _ in
            ComplicationView().containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Quick Capture")
        .description("Tap to start talking.")
        .supportedFamilies([.accessoryCircular, .accessoryCorner, .accessoryRectangular])
    }
}

private struct ComplicationView: View {
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .accessoryRectangular:
            Label("Capture", systemImage: "mic.fill").font(.headline)
        case .accessoryCorner:
            Image(systemName: "mic.fill").font(.title3).widgetLabel("Capture")
        default:
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: "mic.fill").font(.title3)
            }
        }
    }
}
