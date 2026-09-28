import AVFoundation
import SwiftUI
import WatchConnectivity
import WatchKit

@main
struct QuickCaptureWatchApp: App {
    @StateObject private var model = WatchCapture()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            WatchCaptureView(model: model)
                // Open the app / tap the complication → already listening.
                // (Not on a mere wrist raise back to an app that's still in front.)
                .onAppear { if model.autoStart { model.start() } }
                .onChange(of: scenePhase) { old, phase in
                    if phase == .active, old == .background, model.autoStart { model.start() }
                    if phase == .background { model.stopIfRecording() }
                }
        }
    }
}

struct WatchCaptureView: View {
    @ObservedObject var model: WatchCapture

    var body: some View {
        VStack(spacing: 8) {
            Button { model.toggle() } label: {
                CaptureOrb(listening: model.isRecording, level: model.level, size: 96)
            }
            .buttonStyle(.plain)
            .handGestureShortcut(.primaryAction) // Double Tap starts / finishes
            .accessibilityLabel(model.isRecording ? "Finish" : "Capture")

            Text(model.status)
                .font(.footnote)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .lineLimit(3)
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { model.autoStart.toggle() } label: {
                    Image(systemName: model.autoStart ? "bolt.fill" : "bolt.slash")
                }
                .accessibilityLabel("Start listening on open")
            }
        }
    }
}

/// Records compact AAC audio and hands it to the iPhone, which transcribes it on-device and
/// turns it into tasks. The Watch stays dumb and fast: no models, no API keys.
@MainActor
final class WatchCapture: NSObject, ObservableObject {
    @Published private(set) var isRecording = false
    @Published private(set) var level: Float = 0
    @Published private(set) var status = "Tap or double-tap to talk"
    @Published var autoStart = UserDefaults.standard.object(forKey: "autoStart") as? Bool ?? true {
        didSet { UserDefaults.standard.set(autoStart, forKey: "autoStart") }
    }
    private var starting = false

    private var recorder: AVAudioRecorder?
    private var meterTimer: Timer?
    private var heardSpeech = false
    private var quietSince: Date?
    private var startedAt = Date()

    override init() {
        super.init()
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
        }
    }

    func toggle() { isRecording ? finish() : start() }

    func stopIfRecording() { if isRecording { finish() } }

    func start() {
        guard !isRecording, !starting else { return }
        starting = true
        Task {
            defer { starting = false }
            guard await AVAudioApplication.requestRecordPermission() else {
                status = "Allow microphone access"
                return
            }
            do {
                let session = AVAudioSession.sharedInstance()
                try session.setCategory(.record, mode: .default)
                try session.setActive(true)
                let url = FileManager.default.temporaryDirectory.appendingPathComponent("note-\(UUID().uuidString).m4a")
                let r = try AVAudioRecorder(url: url, settings: [
                    AVFormatIDKey: kAudioFormatMPEG4AAC,
                    AVSampleRateKey: 16_000,        // speech-quality, tiny files → quick transfer
                    AVNumberOfChannelsKey: 1,
                    AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue,
                ])
                r.isMeteringEnabled = true
                guard r.record() else { throw RecorderError("Couldn't start recording") }
                recorder = r
                isRecording = true
                heardSpeech = false
                quietSince = nil
                startedAt = .now
                status = "Listening…"
                WKInterfaceDevice.current().play(.start)
                meterTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
                    MainActor.assumeIsolated { self.meter() }
                }
            } catch {
                status = error.localizedDescription
            }
        }
    }

    func finish() {
        guard isRecording, let r = recorder else { return }
        meterTimer?.invalidate()
        r.stop()
        recorder = nil
        isRecording = false
        level = 0
        try? AVAudioSession.sharedInstance().setActive(false)
        WKInterfaceDevice.current().play(.stop)

        guard heardSpeech else {
            try? FileManager.default.removeItem(at: r.url)
            status = "Didn't catch that"
            return
        }
        WCSession.default.transferFile(r.url, metadata: ["kind": "voice"])
        status = WCSession.default.isReachable ? "Sent to iPhone…" : "Queued — will sync to iPhone"
    }

    /// Auto-stop after ~1.8 s of quiet once speech was heard, or 6 s of nothing, or 2 min total.
    private func meter() {
        guard let r = recorder else { return }
        r.updateMeters()
        let db = r.averagePower(forChannel: 0)
        level = max(0, min(1, (db + 50) / 40))
        let now = Date()
        if db > -32 {
            heardSpeech = true
            quietSince = nil
        } else if quietSince == nil {
            quietSince = now
        }
        let quiet = quietSince.map { now.timeIntervalSince($0) } ?? 0
        if (heardSpeech && quiet > 1.8) || (!heardSpeech && quiet > 6) || now.timeIntervalSince(startedAt) > 120 {
            finish()
        }
    }
}

extension WatchCapture: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {}

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        guard let summary = message["summary"] as? String else { return }
        Task { @MainActor in
            self.status = summary
            WKInterfaceDevice.current().play(.success)
        }
    }
}

struct RecorderError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}
