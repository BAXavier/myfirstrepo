import AVFoundation
import Speech

/// Live mic → on-device speech recognition with partial results and silence auto-stop.
@MainActor
final class SpeechRecorder: ObservableObject {
    @Published private(set) var transcript = ""
    @Published private(set) var level: Float = 0
    @Published private(set) var isRecording = false

    /// Called when the speaker has gone quiet for `silenceTimeout` after saying something.
    var onSilence: (() -> Void)?
    var silenceTimeout: TimeInterval = 1.8
    /// Give up if nothing at all is said for this long.
    var initialTimeout: TimeInterval = 6

    private let engine = AVAudioEngine()
    private let recognizer = SFSpeechRecognizer(locale: .current) ?? SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var silenceTimer: Task<Void, Never>?
    private var finalWaiter: CheckedContinuation<Void, Never>?

    static func requestPermissions() async -> Bool {
        let speech = await withCheckedContinuation { c in
            SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0 == .authorized) }
        }
        #if os(iOS)
        let mic = await AVAudioApplication.requestRecordPermission()
        #else
        let mic = await AVCaptureDevice.requestAccess(for: .audio)
        #endif
        return speech && mic
    }

    func start() throws {
        guard !isRecording else { return }
        guard let recognizer, recognizer.isAvailable else { throw RecorderError("Speech recognition unavailable") }

        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: [.duckOthers])
        try session.setActive(true, options: .notifyOthersOnDeactivation)
        #endif

        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        req.taskHint = .dictation
        req.addsPunctuation = true
        if recognizer.supportsOnDeviceRecognition { req.requiresOnDeviceRecognition = true } // fast + private
        request = req

        let input = engine.inputNode
        input.installTap(onBus: 0, bufferSize: 1024, format: input.outputFormat(forBus: 0),
                         block: Self.makeTap(request: req) { [weak self] lvl in
                             Task { @MainActor in self?.level = lvl }
                         })
        engine.prepare()
        try engine.start()

        transcript = ""
        isRecording = true
        task = recognizer.recognitionTask(with: req, resultHandler: Self.makeResultHandler { [weak self] text, isFinal in
            Task { @MainActor in self?.handle(text: text, isFinal: isFinal) }
        })
        armSilenceTimer(after: initialTimeout)
    }

    /// Stops listening and returns the final transcript (waits briefly for the recognizer to finalize).
    func stop() async -> String {
        guard isRecording else { return transcript }
        isRecording = false
        silenceTimer?.cancel()
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            finalWaiter = c
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(1200))
                self?.resumeFinalWaiter()
            }
        }
        task?.cancel()
        task = nil
        request = nil
        level = 0
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif
        return transcript.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func cancel() {
        guard isRecording else { return }
        Task { _ = await stop(); transcript = "" }
    }

    private func handle(text: String?, isFinal: Bool) {
        if let text, !text.isEmpty, text != transcript {
            transcript = text
            if isRecording { armSilenceTimer(after: silenceTimeout) }
        }
        if isFinal { resumeFinalWaiter() }
    }

    private func resumeFinalWaiter() {
        finalWaiter?.resume()
        finalWaiter = nil
    }

    private func armSilenceTimer(after seconds: TimeInterval) {
        silenceTimer?.cancel()
        silenceTimer = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled, let self, self.isRecording else { return }
            self.onSilence?()
        }
    }

    // Built outside the main actor: these run on audio / recognizer threads.
    nonisolated private static func makeTap(request: SFSpeechAudioBufferRecognitionRequest,
                                            onLevel: @escaping @Sendable (Float) -> Void) -> AVAudioNodeTapBlock {
        var frame = 0
        return { buffer, _ in
            request.append(buffer)
            frame += 1
            guard frame % 4 == 0, let data = buffer.floatChannelData?[0] else { return } // ~10 Hz meter
            let n = Int(buffer.frameLength)
            var sum: Float = 0
            for i in 0..<n { sum += data[i] * data[i] }
            let rms = n > 0 ? (sum / Float(n)).squareRoot() : 0
            onLevel(min(1, rms * 12))
        }
    }

    nonisolated private static func makeResultHandler(
        _ onResult: @escaping @Sendable (String?, Bool) -> Void
    ) -> (SFSpeechRecognitionResult?, Error?) -> Void {
        { result, error in
            onResult(result?.bestTranscription.formattedString, result?.isFinal ?? (error != nil))
        }
    }

    /// Transcribes a recorded file (used for audio sent from the Watch).
    nonisolated static func transcribe(file: URL) async throws -> String {
        guard let recognizer = SFSpeechRecognizer(locale: .current) ?? SFSpeechRecognizer(locale: Locale(identifier: "en-US")) else {
            throw RecorderError("Speech recognition unavailable")
        }
        let req = SFSpeechURLRecognitionRequest(url: file)
        req.taskHint = .dictation
        req.addsPunctuation = true
        req.shouldReportPartialResults = false
        if recognizer.supportsOnDeviceRecognition { req.requiresOnDeviceRecognition = true }
        return try await withCheckedThrowingContinuation { c in
            var done = false
            _ = recognizer.recognitionTask(with: req) { result, error in
                guard !done else { return }
                if let result, result.isFinal {
                    done = true
                    c.resume(returning: result.bestTranscription.formattedString)
                } else if let error {
                    done = true
                    c.resume(throwing: error)
                }
            }
        }
    }
}

struct RecorderError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}
