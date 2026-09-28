import CaptureKit
import Foundation
import SwiftUI

/// A processed note, kept locally so nothing is ever lost (even if every destination fails).
struct HistoryEntry: Codable, Identifiable, Hashable {
    var id = UUID()
    var date: Date
    var transcript: String
    var tasks: [CaptureTask]
    var summary: String
}

/// Turns text into tasks and fans them out to every enabled destination in parallel.
enum CapturePipeline {
    static func process(_ transcript: String, now: Date = .now) async -> HistoryEntry {
        let tasks = await extract(transcript, now: now)
        guard !tasks.isEmpty else {
            return HistoryEntry(date: now, transcript: transcript, tasks: [], summary: "Nothing actionable — saved note")
        }
        let destinations = enabledDestinations()
        guard !destinations.isEmpty else {
            return HistoryEntry(date: now, transcript: transcript, tasks: tasks, summary: "\(tasks.count) task(s) — no destination on")
        }

        let results = await withTaskGroup(of: (String, String?).self) { group in
            for d in destinations {
                group.addTask {
                    do { try await d.deliver(tasks); return (d.name, nil) }
                    catch { return (d.name, error.localizedDescription) }
                }
            }
            return await group.reduce(into: [(String, String?)]()) { $0.append($1) }
        }
        let ok = results.filter { $0.1 == nil }.map(\.0).sorted()
        let failed = results.compactMap { r in r.1.map { "\(r.0): \($0)" } }
        var summary = "\(tasks.count) task\(tasks.count == 1 ? "" : "s")"
        if !ok.isEmpty { summary += " → " + ok.joined(separator: ", ") }
        if !failed.isEmpty { summary += (ok.isEmpty ? " ✗ " : " · ✗ ") + failed.joined(separator: "; ") }
        return HistoryEntry(date: now, transcript: transcript, tasks: tasks, summary: summary)
    }

    static func extract(_ transcript: String, now: Date) async -> [CaptureTask] {
        let d = UserDefaults.standard
        let choice = ExtractorChoice(rawValue: d.string(forKey: Pref.extractor) ?? "") ?? .auto
        let key = Secret.anthropicKey.value
        let claude: TaskExtractor? = key.isEmpty ? nil
            : ClaudeExtractor(apiKey: key, model: d.string(forKey: Pref.claudeModel) ?? "")

        let chain: [TaskExtractor?] = switch choice {
        case .auto: [OnDevice.extractor(), claude]
        case .apple: [OnDevice.extractor()]
        case .claude: [claude]
        case .simple: []
        }
        for extractor in chain.compactMap({ $0 }) {
            if let tasks = try? await extractor.extract(transcript, now: now) { return tasks }
        }
        return (try? await HeuristicExtractor().extract(transcript, now: now)) ?? []
    }

    static func enabledDestinations() -> [TaskDestination] {
        let d = UserDefaults.standard
        var out: [TaskDestination] = []
        if d.bool(forKey: Pref.useReminders) {
            out.append(RemindersDestination(defaultList: d.string(forKey: Pref.remindersList) ?? ""))
        }
        let todoist = Secret.todoistToken.value, notion = Secret.notionToken.value
        if d.bool(forKey: Pref.useTodoist), !todoist.isEmpty {
            out.append(TodoistDestination(token: todoist, defaultProjectId: d.string(forKey: Pref.todoistProject) ?? ""))
        }
        if d.bool(forKey: Pref.useNotion), !notion.isEmpty {
            out.append(NotionDestination(token: notion,
                                         databaseId: d.string(forKey: Pref.notionDatabase) ?? "",
                                         titleProperty: d.string(forKey: Pref.notionTitleProp) ?? "Name",
                                         dueProperty: d.string(forKey: Pref.notionDueProp) ?? ""))
        }
        return out
    }
}

/// One capture at a time: idle → listening → thinking → done.
@MainActor
final class CaptureController: ObservableObject {
    enum Phase: Equatable { case idle, listening, thinking, done(String), failed(String) }

    static let shared = CaptureController()

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var history: [HistoryEntry] = []
    let recorder = SpeechRecorder()

    private static let historyKey = "history"
    private var resetTask: Task<Void, Never>?
    private var starting = false

    private init() {
        Pref.registerDefaults()
        if let data = UserDefaults.standard.data(forKey: Self.historyKey),
           let saved = try? JSONDecoder().decode([HistoryEntry].self, from: data) {
            history = saved
        }
        recorder.onSilence = { [weak self] in Task { await self?.finish() } }
    }

    var isListening: Bool { phase == .listening }

    /// Single entry point for every trigger (⌥⌥⌥, swirl, Action Button, widget, …).
    func toggle() {
        switch phase {
        case .listening: Task { await finish() }
        case .thinking: break
        default: Task { await start() }
        }
    }

    func start() async {
        guard !starting, phase != .listening, phase != .thinking else { return }
        starting = true
        defer { starting = false }
        resetTask?.cancel()
        guard await SpeechRecorder.requestPermissions() else {
            return show(.failed("Allow Microphone & Speech Recognition"))
        }
        recorder.silenceTimeout = max(0.8, UserDefaults.standard.double(forKey: Pref.silenceSeconds))
        do {
            try recorder.start()
            phase = .listening
        } catch {
            show(.failed(error.localizedDescription))
        }
    }

    func finish() async {
        guard phase == .listening else { return }
        phase = .thinking
        let text = await recorder.stop()
        guard !text.isEmpty else { return show(.failed("Didn't catch that")) }
        await process(text)
    }

    func cancel() {
        guard phase == .listening else { return }
        recorder.cancel()
        phase = .idle
    }

    /// Also used for text/audio that arrives from the Watch.
    func process(_ text: String) async {
        phase = .thinking
        let entry = await CapturePipeline.process(text)
        record(entry)
        show(.done(entry.summary))
    }

    func record(_ entry: HistoryEntry) {
        history.insert(entry, at: 0)
        history = Array(history.prefix(30))
        if let data = try? JSONEncoder().encode(history) {
            UserDefaults.standard.set(data, forKey: Self.historyKey)
        }
    }

    private func show(_ p: Phase) {
        phase = p
        resetTask?.cancel()
        resetTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            self?.phase = .idle
        }
    }
}
