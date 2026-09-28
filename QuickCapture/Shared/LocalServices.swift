import CaptureKit
import EventKit
import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

// MARK: - On-device model (Apple Intelligence): free, private, no network.

enum OnDevice {
    static var isAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(iOS 26, macOS 26, *) { return SystemLanguageModel.default.isAvailable }
        #endif
        return false
    }

    static func extractor() -> TaskExtractor? {
        #if canImport(FoundationModels)
        if #available(iOS 26, macOS 26, *), SystemLanguageModel.default.isAvailable { return OnDeviceExtractor() }
        #endif
        return nil
    }
}

#if canImport(FoundationModels)
@available(iOS 26, macOS 26, *)
struct OnDeviceExtractor: TaskExtractor {
    @Generable
    struct Item {
        @Guide(description: "Short imperative task title")
        var title: String
        @Guide(description: "Extra detail, only if useful")
        var notes: String?
        @Guide(description: "YYYY-MM-DD, or YYYY-MM-DDTHH:MM when a time is given")
        var due: String?
        @Guide(description: "1 urgent, 2 high, 3 medium; omit if unstated")
        var priority: Int?
        @Guide(description: "List or project name, only if the speaker named one")
        var list: String?
    }

    @Generable
    struct Result {
        var tasks: [Item]
    }

    func extract(_ transcript: String, now: Date) async throws -> [CaptureTask] {
        let session = LanguageModelSession(instructions: ExtractionPrompt.system)
        let response = try await session.respond(to: ExtractionPrompt.user(transcript, now: now), generating: Result.self)
        return response.content.tasks
            .map { CaptureTask(title: $0.title, notes: $0.notes, due: $0.due, priority: $0.priority, list: $0.list) }
            .filter { !$0.title.trimmingCharacters(in: .whitespaces).isEmpty }
    }
}
#endif

// MARK: - Apple Reminders

final class RemindersDestination: TaskDestination, @unchecked Sendable {
    let name = "Reminders"
    let defaultList: String
    private let store = EKEventStore()

    init(defaultList: String) { self.defaultList = defaultList }

    func deliver(_ tasks: [CaptureTask]) async throws {
        guard try await store.requestFullAccessToReminders() else {
            throw CaptureError("Allow Reminders access in Settings")
        }
        let lists = store.calendars(for: .reminder)
        func list(named name: String?) -> EKCalendar? {
            guard let name, !name.isEmpty else { return nil }
            return lists.first { $0.title.caseInsensitiveCompare(name) == .orderedSame }
        }
        let fallback = list(named: defaultList) ?? store.defaultCalendarForNewReminders()

        for task in tasks {
            let r = EKReminder(eventStore: store)
            r.title = task.title
            r.notes = task.notes
            r.calendar = list(named: task.list) ?? fallback
            if let due = task.dueComponents {
                r.dueDateComponents = due
                if task.dueHasTime, let date = Calendar.current.date(from: due) {
                    r.addAlarm(EKAlarm(absoluteDate: date))
                }
            }
            switch task.priority { // EventKit: 1 high, 5 medium, 9 low
            case 1: r.priority = 1
            case 2: r.priority = 3
            case 3: r.priority = 5
            default: break
            }
            try store.save(r, commit: false)
        }
        try store.commit()
    }
}
