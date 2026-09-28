import Foundation
import WatchConnectivity

/// Receives voice notes recorded on the Watch. Audio files are queued in an inbox on disk and
/// processed (transcribe → tasks → destinations) as soon as possible, so nothing is lost if the
/// phone app isn't running when they arrive.
@MainActor
final class WatchLink: NSObject {
    static let shared = WatchLink()

    private var processing = false

    nonisolated static let inbox: URL = {
        let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("WatchInbox", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func processInbox() {
        guard !processing else { return }
        processing = true
        Task {
            defer { processing = false }
            let files = (try? FileManager.default.contentsOfDirectory(at: Self.inbox, includingPropertiesForKeys: [.creationDateKey]))?
                .sorted { $0.lastPathComponent < $1.lastPathComponent } ?? []
            for file in files {
                guard let text = try? await SpeechRecorder.transcribe(file: file) else {
                    // Keep it for the next activation unless it's clearly unusable (older than a day).
                    let created = (try? file.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? .distantPast
                    if created < .now.addingTimeInterval(-86_400) { try? FileManager.default.removeItem(at: file) }
                    continue
                }
                try? FileManager.default.removeItem(at: file)
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { reply("Didn't catch that"); continue }
                await CaptureController.shared.process(trimmed)
                reply(CaptureController.shared.history.first?.summary ?? "Saved")
            }
        }
    }

    private func reply(_ summary: String) {
        let session = WCSession.default
        guard session.activationState == .activated, session.isReachable else { return }
        session.sendMessage(["summary": summary], replyHandler: nil)
    }
}

extension WatchLink: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, didReceive file: WCSessionFile) {
        // The system deletes `file.fileURL` when this returns, so move it synchronously.
        let name = "\(Int(Date().timeIntervalSince1970 * 1000))-\(file.fileURL.lastPathComponent)"
        try? FileManager.default.moveItem(at: file.fileURL, to: Self.inbox.appendingPathComponent(name))
        Task { @MainActor in WatchLink.shared.processInbox() }
    }

    nonisolated func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {}
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}
    nonisolated func sessionDidDeactivate(_ session: WCSession) { session.activate() }
}
