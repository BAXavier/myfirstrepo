import Foundation

/// One actionable item extracted from a voice note.
public struct CaptureTask: Codable, Hashable, Sendable {
    /// Short imperative title, e.g. "Call Sam about the lease".
    public var title: String
    /// Extra detail that doesn't fit in the title.
    public var notes: String?
    /// Local due date `YYYY-MM-DD` or date-time `YYYY-MM-DDTHH:MM`.
    public var due: String?
    /// 1 = urgent, 2 = high, 3 = medium, nil = none.
    public var priority: Int?
    /// List / project name the speaker asked for, e.g. "Groceries".
    public var list: String?

    public init(title: String, notes: String? = nil, due: String? = nil, priority: Int? = nil, list: String? = nil) {
        self.title = title
        self.notes = notes
        self.due = due
        self.priority = priority
        self.list = list
    }

    /// Parsed `due`, or nil if absent/malformed. `hour`/`minute` are set only for date-times.
    public var dueComponents: DateComponents? {
        guard let due else { return nil }
        return Self.parseDue(due)
    }

    public var dueHasTime: Bool { dueComponents?.hour != nil }

    static func parseDue(_ raw: String) -> DateComponents? {
        let s = raw.trimmingCharacters(in: .whitespaces)
        let parts = s.split(separator: "T", maxSplits: 1).map(String.init)
        let ymd = parts[0].split(separator: "-").compactMap { Int($0) }
        guard ymd.count == 3, (1...12).contains(ymd[1]), (1...31).contains(ymd[2]) else { return nil }
        var c = DateComponents(year: ymd[0], month: ymd[1], day: ymd[2])
        if parts.count == 2 {
            let hm = parts[1].split(separator: ":").prefix(2).compactMap { Int($0) }
            guard hm.count == 2, (0...23).contains(hm[0]), (0...59).contains(hm[1]) else { return c }
            c.hour = hm[0]
            c.minute = hm[1]
        }
        return c
    }
}

public struct ExtractionResult: Codable, Sendable {
    public var tasks: [CaptureTask]
    public init(tasks: [CaptureTask]) { self.tasks = tasks }
}

/// Turns a transcript into tasks.
public protocol TaskExtractor: Sendable {
    func extract(_ transcript: String, now: Date) async throws -> [CaptureTask]
}

/// Somewhere tasks end up (Reminders, Todoist, Notion, ...).
public protocol TaskDestination: Sendable {
    var name: String { get }
    func deliver(_ tasks: [CaptureTask]) async throws
}

public struct CaptureError: LocalizedError, Sendable {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}
