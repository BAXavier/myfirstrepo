import CaptureKit
import SwiftUI
import UIKit

@main
struct QuickCapturePhoneApp: App {
    @StateObject private var capture = CaptureController.shared
    @Environment(\.scenePhase) private var scenePhase

    init() {
        MainActor.assumeIsolated { WatchLink.shared.activate() }
    }

    var body: some Scene {
        WindowGroup {
            RootView(capture: capture)
                .onOpenURL { url in
                    if url.host == "record" { startNow() } // quickcapture://record (widgets)
                }
                .onReceive(NotificationCenter.default.publisher(for: .startCapture)) { _ in startNow() }
                .onChange(of: scenePhase) { _, phase in
                    guard phase == .active else { return }
                    if CaptureRequest.pending { startNow() }
                    WatchLink.shared.processInbox()
                }
        }
    }

    private func startNow() {
        CaptureRequest.pending = false
        Task { await capture.start() }
    }
}

struct RootView: View {
    @ObservedObject var capture: CaptureController
    @State private var showSettings = false
    @State private var swirl = SwirlDetector(minRadius: 25)

    var body: some View {
        NavigationStack {
            List {
                Section {
                    CaptureHeader(capture: capture, recorder: capture.recorder)
                        .listRowBackground(Color.clear)
                }
                if !capture.history.isEmpty {
                    Section("Recent") {
                        ForEach(capture.history) { HistoryRow(entry: $0) }
                    }
                }
            }
            .navigationTitle("Quick Capture")
            .toolbar {
                Button { showSettings = true } label: { Image(systemName: "gearshape") }
            }
            .sheet(isPresented: $showSettings) {
                NavigationStack {
                    SettingsView()
                        .navigationTitle("Settings")
                        .toolbar { Button("Done") { showSettings = false } }
                }
            }
        }
        // Swirl a finger twice anywhere to start / finish.
        .simultaneousGesture(
            DragGesture(minimumDistance: 8, coordinateSpace: .global)
                .onChanged { v in
                    if swirl.add(x: v.location.x, y: v.location.y, t: v.time.timeIntervalSinceReferenceDate) {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        capture.toggle()
                    }
                }
                .onEnded { _ in swirl.reset() }
        )
        .sensoryFeedback(.start, trigger: capture.isListening) { _, new in new }
        .sensoryFeedback(.success, trigger: capture.history.first?.id)
    }
}

private struct CaptureHeader: View {
    @ObservedObject var capture: CaptureController
    @ObservedObject var recorder: SpeechRecorder

    var body: some View {
        VStack(spacing: 14) {
            Button { capture.toggle() } label: {
                CaptureOrb(listening: capture.isListening, level: recorder.level, size: 120)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(capture.isListening ? "Finish capture" : "Start capture")

            Text(status)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .padding(.vertical, 8)
    }

    private var status: String {
        switch capture.phase {
        case .idle: "Tap, or swirl a finger twice, to talk"
        case .listening: recorder.transcript.isEmpty ? "Listening… pause when you're done" : recorder.transcript
        case .thinking: "Making tasks…"
        case .done(let s), .failed(let s): s
        }
    }
}

private struct HistoryRow: View {
    let entry: HistoryEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(entry.summary).font(.subheadline.weight(.semibold))
            ForEach(entry.tasks, id: \.self) { task in
                Label {
                    Text(task.title) + Text(task.due.map { "  · \($0)" } ?? "").foregroundStyle(.secondary)
                } icon: {
                    Image(systemName: "circle")
                }
                .font(.subheadline)
            }
            if entry.tasks.isEmpty {
                Text(entry.transcript).font(.footnote).foregroundStyle(.secondary)
            }
        }
        .contextMenu {
            Button("Copy transcript") { UIPasteboard.general.string = entry.transcript }
        }
    }
}
