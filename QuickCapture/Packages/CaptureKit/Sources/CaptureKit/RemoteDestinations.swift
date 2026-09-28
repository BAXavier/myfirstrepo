import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Todoist (unified API v1). Tasks are created concurrently.
public struct TodoistDestination: TaskDestination {
    public let name = "Todoist"
    public var token: String
    /// Used when a task names no list, or names one that doesn't exist. Empty = Inbox.
    public var defaultProjectId: String
    public var session: URLSession

    static let base = URL(string: "https://api.todoist.com/api/v1/")!

    public init(token: String, defaultProjectId: String = "", session: URLSession = .shared) {
        self.token = token
        self.defaultProjectId = defaultProjectId
        self.session = session
    }

    public func deliver(_ tasks: [CaptureTask]) async throws {
        let projects = tasks.contains { $0.list != nil } ? (try? await projectIds()) ?? [:] : [:]
        try await withThrowingTaskGroup(of: Void.self) { group in
            for task in tasks {
                let projectId = task.list.flatMap { projects[$0.lowercased()] } ?? defaultProjectId
                let request = try makeRequest(task, projectId: projectId)
                group.addTask { try await send(request) }
            }
            try await group.waitForAll()
        }
    }

    public func makeRequest(_ task: CaptureTask, projectId: String) throws -> URLRequest {
        var body: [String: Any] = ["content": task.title]
        if let notes = task.notes { body["description"] = notes }
        if let p = task.priority { body["priority"] = max(1, 5 - p) } // Todoist: 4 = urgent, 1 = normal
        if let c = task.dueComponents, let date = task.due?.prefix(10) {
            if let h = c.hour, let m = c.minute {
                body["due_string"] = "\(date) at \(twoDigits(h)):\(twoDigits(m))" // parsed in the user's tz
            } else {
                body["due_date"] = String(date)
            }
        }
        if !projectId.isEmpty { body["project_id"] = projectId }
        var req = authorized(URLRequest(url: Self.base.appendingPathComponent("tasks")))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        return req
    }

    private func projectIds() async throws -> [String: String] {
        struct Page: Decodable { struct P: Decodable { let id: String; let name: String }; let results: [P] }
        let (data, _) = try await session.data(for: authorized(URLRequest(url: Self.base.appendingPathComponent("projects"))))
        let page = try JSONDecoder().decode(Page.self, from: data)
        return Dictionary(page.results.map { ($0.name.lowercased(), $0.id) }, uniquingKeysWith: { a, _ in a })
    }

    private func authorized(_ req: URLRequest) -> URLRequest {
        var r = req
        r.timeoutInterval = 20
        r.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return r
    }

    private func send(_ req: URLRequest) async throws {
        let (_, resp) = try await session.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else { throw CaptureError("Todoist HTTP \(code)") }
    }
}

/// Notion: one page per task in a database.
public struct NotionDestination: TaskDestination {
    public let name = "Notion"
    public var token: String
    public var databaseId: String
    public var titleProperty: String
    /// Date property name; empty = don't set a date.
    public var dueProperty: String
    public var timeZone: TimeZone
    public var session: URLSession

    public init(token: String, databaseId: String, titleProperty: String = "Name", dueProperty: String = "",
                timeZone: TimeZone = .current, session: URLSession = .shared) {
        self.token = token
        self.databaseId = databaseId
        self.titleProperty = titleProperty.isEmpty ? "Name" : titleProperty
        self.dueProperty = dueProperty
        self.timeZone = timeZone
        self.session = session
    }

    public func deliver(_ tasks: [CaptureTask]) async throws {
        guard !databaseId.isEmpty else { throw CaptureError("Notion: set a database ID") }
        try await withThrowingTaskGroup(of: Void.self) { group in
            for task in tasks {
                let request = try makeRequest(task)
                group.addTask {
                    let (data, resp) = try await session.data(for: request)
                    let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
                    guard (200..<300).contains(code) else {
                        let msg = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["message"] as? String
                        throw CaptureError("Notion HTTP \(code)\(msg.map { ": \($0)" } ?? "")")
                    }
                }
            }
            try await group.waitForAll()
        }
    }

    public func makeRequest(_ task: CaptureTask) throws -> URLRequest {
        var properties: [String: Any] = [titleProperty: ["title": [["text": ["content": task.title]]]]]
        if !dueProperty.isEmpty, let c = task.dueComponents, let due = task.due {
            var date: [String: Any] = ["start": String(due.prefix(10))]
            if let h = c.hour, let m = c.minute {
                date["start"] = "\(due.prefix(10))T\(twoDigits(h)):\(twoDigits(m)):00"
                date["time_zone"] = timeZone.identifier
            }
            properties[dueProperty] = ["date": date]
        }
        var body: [String: Any] = ["parent": ["database_id": databaseId], "properties": properties]
        if let notes = task.notes, !notes.isEmpty {
            body["children"] = [[
                "object": "block", "type": "paragraph",
                "paragraph": ["rich_text": [["type": "text", "text": ["content": notes]]]],
            ]]
        }
        var req = URLRequest(url: URL(string: "https://api.notion.com/v1/pages")!)
        req.httpMethod = "POST"
        req.timeoutInterval = 20
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("2022-06-28", forHTTPHeaderField: "Notion-Version")
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        return req
    }
}

func twoDigits(_ n: Int) -> String { n < 10 ? "0\(n)" : "\(n)" }
