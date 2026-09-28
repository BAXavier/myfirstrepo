import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Calls the Claude Messages API with a JSON-schema constrained output.
/// Swift has no official Anthropic SDK, so this is a single raw HTTPS request.
public struct ClaudeExtractor: TaskExtractor {
    public static let defaultModel = "claude-opus-5"

    public var apiKey: String
    public var model: String
    public var timeZone: TimeZone
    public var session: URLSession

    public init(apiKey: String, model: String = ClaudeExtractor.defaultModel,
                timeZone: TimeZone = .current, session: URLSession = .shared) {
        self.apiKey = apiKey
        self.model = model.isEmpty ? Self.defaultModel : model
        self.timeZone = timeZone
        self.session = session
    }

    public func extract(_ transcript: String, now: Date) async throws -> [CaptureTask] {
        let (data, response) = try await session.data(for: makeRequest(transcript: transcript, now: now))
        guard let http = response as? HTTPURLResponse else { throw CaptureError("Claude: no response") }
        guard http.statusCode == 200 else {
            throw CaptureError("Claude HTTP \(http.statusCode): \(Self.apiErrorMessage(data) ?? "request failed")")
        }
        return try Self.parse(data)
    }

    // Effort and server-side refusal fallbacks exist on the Opus/Fable line but not on Haiku 4.5.
    var supportsEffort: Bool { !model.contains("haiku") }
    var supportsDefaultFallbacks: Bool { model.hasPrefix("claude-opus-5") || model.hasPrefix("claude-fable-5") }

    public func makeRequest(transcript: String, now: Date) throws -> URLRequest {
        var req = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        req.httpMethod = "POST"
        req.timeoutInterval = 30
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        req.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        var outputConfig: [String: Any] = ["format": ["type": "json_schema", "schema": ExtractionPrompt.schema]]
        if supportsEffort { outputConfig["effort"] = "low" } // short extraction task: favor latency

        var body: [String: Any] = [
            "model": model,
            "max_tokens": 4096,
            "system": ExtractionPrompt.system,
            "output_config": outputConfig,
            "messages": [["role": "user", "content": ExtractionPrompt.user(transcript, now: now, timeZone: timeZone)]],
        ]
        if supportsDefaultFallbacks {
            // If a safety classifier declines, the API re-runs on a fallback model instead of failing.
            req.setValue("server-side-fallback-2026-07-01", forHTTPHeaderField: "anthropic-beta")
            body["fallbacks"] = "default"
        }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        return req
    }

    private struct MessageResponse: Decodable {
        struct Block: Decodable { let type: String; let text: String? }
        let content: [Block]
        let stop_reason: String?
    }

    public static func parse(_ data: Data) throws -> [CaptureTask] {
        let msg = try JSONDecoder().decode(MessageResponse.self, from: data)
        if msg.stop_reason == "refusal" { throw CaptureError("Claude declined this note") }
        if msg.stop_reason == "max_tokens" { throw CaptureError("Claude response was cut off") }
        guard let text = msg.content.first(where: { $0.type == "text" })?.text else {
            throw CaptureError("Claude returned no text")
        }
        let result = try JSONDecoder().decode(ExtractionResult.self, from: Data(text.utf8))
        return result.tasks
            .map { var t = $0; t.title = t.title.trimmingCharacters(in: .whitespacesAndNewlines); return t }
            .filter { !$0.title.isEmpty }
    }

    static func apiErrorMessage(_ data: Data) -> String? {
        struct Envelope: Decodable { struct E: Decodable { let message: String }; let error: E }
        return (try? JSONDecoder().decode(Envelope.self, from: data))?.error.message
    }
}
