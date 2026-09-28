import Foundation

/// Shared instructions so the on-device model and Claude behave the same.
public enum ExtractionPrompt {
    public static let system = """
    You turn a quick, spoken voice memo into to-do items. Latency-sensitive; begin your answer immediately.

    - One task per distinct action. Titles are short and imperative (under 10 words), keep names and specifics.
    - Resolve relative dates ("tomorrow", "next Friday", "in two hours", "tonight") against the current date \
    and time given with the memo. Write `due` as YYYY-MM-DD, or YYYY-MM-DDTHH:MM (24h, local) when a time is \
    stated or clearly implied. Leave it out if there is no date.
    - `priority`: 1 urgent, 2 high, 3 medium. Leave it out unless the speaker signals importance.
    - `list`: only when the speaker names a list or project ("add milk to groceries", "for work").
    - `notes`: only for useful detail that doesn't fit the title.
    - Speech is messy: ignore filler, false starts and repeated words; when the speaker corrects themselves, \
    keep the corrected version.
    - If nothing is actionable, return an empty task list.
    """

    public static func user(_ transcript: String, now: Date, timeZone: TimeZone = .current) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = timeZone
        f.dateFormat = "EEEE yyyy-MM-dd'T'HH:mm"
        return "Current local date and time: \(f.string(from: now)) (\(timeZone.identifier))\n\nVoice memo:\n\(transcript)"
    }

    /// JSON Schema for Claude structured outputs.
    public static let schema: [String: Any] = [
        "type": "object",
        "additionalProperties": false,
        "required": ["tasks"],
        "properties": [
            "tasks": [
                "type": "array",
                "items": [
                    "type": "object",
                    "additionalProperties": false,
                    "required": ["title"],
                    "properties": [
                        "title": ["type": "string"],
                        "notes": ["type": "string"],
                        "due": ["type": "string"],
                        "priority": ["type": "integer", "enum": [1, 2, 3]],
                        "list": ["type": "string"],
                    ],
                ],
            ],
        ],
    ]
}

/// Zero-dependency fallback: one task per sentence. Used offline or when no model is configured,
/// so a captured note is never dropped.
public struct HeuristicExtractor: TaskExtractor {
    public init() {}

    public func extract(_ transcript: String, now: Date) async throws -> [CaptureTask] {
        Self.split(transcript).map { CaptureTask(title: $0) }
    }

    static let fillers = ["remind me to ", "i need to ", "i have to ", "i should ", "don't forget to ",
                          "remember to ", "also ", "and ", "then ", "um ", "uh ", "okay ", "so "]

    public static func split(_ text: String) -> [String] {
        text.components(separatedBy: CharacterSet(charactersIn: ".!?;\n"))
            .map { sentence in
                var s = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
                var stripped = true
                while stripped {
                    stripped = false
                    for f in fillers where s.lowercased().hasPrefix(f) {
                        s = String(s.dropFirst(f.count))
                        stripped = true
                    }
                }
                return s.prefix(1).uppercased() + s.dropFirst()
            }
            .filter { $0.count > 2 }
    }
}
