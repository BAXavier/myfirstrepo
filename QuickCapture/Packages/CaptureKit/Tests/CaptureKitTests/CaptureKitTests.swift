import XCTest
@testable import CaptureKit

final class GestureTests: XCTestCase {
    func testTripleOptionTriggers() {
        var d = ModifierTapDetector()
        var events: [ModifierTapDetector.Event] = []
        for i in 0..<3 {
            let t = Double(i) * 0.2
            d.modifierDown(at: t)
            events.append(d.modifierUp(at: t + 0.08))
        }
        XCTAssertEqual(events, [.tap, .tap, .trigger])
    }

    func testSlowTapsDoNotTrigger() {
        var d = ModifierTapDetector()
        var last: ModifierTapDetector.Event = .none
        for t in [0.0, 0.8, 1.6] {
            d.modifierDown(at: t)
            last = d.modifierUp(at: t + 0.08)
        }
        XCTAssertEqual(last, .tap)
    }

    func testOptionUsedAsModifierIsIgnored() {
        var d = ModifierTapDetector()
        d.modifierDown(at: 0); _ = d.modifierUp(at: 0.05)
        d.modifierDown(at: 0.2); d.interrupt() // ⌥ + some key
        XCTAssertEqual(d.modifierUp(at: 0.25), .none)
        d.modifierDown(at: 0.4)
        XCTAssertEqual(d.modifierUp(at: 0.45), .tap)
        d.modifierDown(at: 0.6)
        XCTAssertEqual(d.modifierUp(at: 1.2), .none) // held too long
    }

    private func circle(radius: Double, turns: Double, duration: Double, hz: Double = 120) -> [(Double, Double, Double)] {
        let n = Int(duration * hz)
        return (0..<n).map { i in
            let a = 2 * Double.pi * turns * Double(i) / Double(n)
            return (400 + radius * cos(a), 300 + radius * sin(a), Double(i) / hz)
        }
    }

    private func run(_ pts: [(Double, Double, Double)]) -> Bool {
        var s = SwirlDetector()
        return pts.contains { s.add(x: $0.0, y: $0.1, t: $0.2) }
    }

    func testFastDoubleCircleIsASwirl() {
        XCTAssertTrue(run(circle(radius: 80, turns: 2, duration: 1.0)))
    }

    func testSingleLoopSlowLoopAndLinesAreNot() {
        XCTAssertFalse(run(circle(radius: 80, turns: 1, duration: 0.6)))
        XCTAssertFalse(run(circle(radius: 80, turns: 2, duration: 4)))
        let scribble = (0..<240).map { i in (400 + 300 * sin(2 * .pi * 3 * Double(i) / 240), 300.0, Double(i) / 120) }
        XCTAssertFalse(run(scribble))
        let thin = (0..<240).map { i -> (Double, Double, Double) in
            let a = 2 * Double.pi * 4 * Double(i) / 240
            return (400 + 200 * sin(a), 300 + 200 * sin(a + 0.3), Double(i) / 120)
        }
        XCTAssertFalse(run(thin))
    }
}

final class ModelTests: XCTestCase {
    func testDueParsing() {
        XCTAssertEqual(CaptureTask(title: "a", due: "2026-10-02").dueComponents,
                       DateComponents(year: 2026, month: 10, day: 2))
        let timed = CaptureTask(title: "a", due: "2026-10-02T15:30").dueComponents
        XCTAssertEqual(timed?.hour, 15)
        XCTAssertEqual(timed?.minute, 30)
        XCTAssertNil(CaptureTask(title: "a", due: "next friday").dueComponents)
    }

    func testHeuristicSplit() {
        XCTAssertEqual(HeuristicExtractor.split("Remind me to call Sam. Um and buy milk! ok"),
                       ["Call Sam", "Buy milk"])
    }
}

final class ClaudeTests: XCTestCase {
    func testRequestShape() throws {
        let x = ClaudeExtractor(apiKey: "k", timeZone: TimeZone(identifier: "UTC")!)
        let req = try x.makeRequest(transcript: "buy milk", now: Date(timeIntervalSince1970: 0))
        XCTAssertEqual(req.value(forHTTPHeaderField: "x-api-key"), "k")
        XCTAssertEqual(req.value(forHTTPHeaderField: "anthropic-beta"), "server-side-fallback-2026-07-01")
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: req.httpBody!) as? [String: Any])
        XCTAssertEqual(body["model"] as? String, "claude-opus-5")
        XCTAssertEqual(body["fallbacks"] as? String, "default")
        let config = try XCTUnwrap(body["output_config"] as? [String: Any])
        XCTAssertEqual(config["effort"] as? String, "low")
        XCTAssertEqual((config["format"] as? [String: Any])?["type"] as? String, "json_schema")
    }

    func testHaikuOmitsUnsupportedParams() throws {
        let x = ClaudeExtractor(apiKey: "k", model: "claude-haiku-4-5")
        let body = try XCTUnwrap(JSONSerialization.jsonObject(
            with: x.makeRequest(transcript: "x", now: Date()).httpBody!) as? [String: Any])
        XCTAssertNil(body["fallbacks"])
        XCTAssertNil((body["output_config"] as? [String: Any])?["effort"])
    }

    func testParseResponse() throws {
        let json = #"""
        {"content":[{"type":"thinking","thinking":""},{"type":"text","text":"{\"tasks\":[{\"title\":\" Call Sam \",\"due\":\"2026-10-01T09:00\",\"priority\":1},{\"title\":\"\"}]}"}],"stop_reason":"end_turn"}
        """#
        let tasks = try ClaudeExtractor.parse(Data(json.utf8))
        XCTAssertEqual(tasks, [CaptureTask(title: "Call Sam", due: "2026-10-01T09:00", priority: 1)])
    }

    func testRefusalThrows() {
        let json = #"{"content":[],"stop_reason":"refusal"}"#
        XCTAssertThrowsError(try ClaudeExtractor.parse(Data(json.utf8)))
    }
}

final class DestinationTests: XCTestCase {
    func testTodoistBody() throws {
        let d = TodoistDestination(token: "t")
        let req = try d.makeRequest(CaptureTask(title: "Pay rent", due: "2026-10-01T09:05", priority: 1), projectId: "42")
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: req.httpBody!) as? [String: Any])
        XCTAssertEqual(body["due_string"] as? String, "2026-10-01 at 09:05")
        XCTAssertEqual(body["priority"] as? Int, 4)
        XCTAssertEqual(body["project_id"] as? String, "42")
    }

    func testNotionBody() throws {
        let d = NotionDestination(token: "t", databaseId: "db", dueProperty: "Due", timeZone: TimeZone(identifier: "UTC")!)
        let req = try d.makeRequest(CaptureTask(title: "Pay rent", due: "2026-10-01T09:05"))
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: req.httpBody!) as? [String: Any])
        let props = try XCTUnwrap(body["properties"] as? [String: Any])
        let date = try XCTUnwrap((props["Due"] as? [String: Any])?["date"] as? [String: Any])
        XCTAssertEqual(date["start"] as? String, "2026-10-01T09:05:00")
        XCTAssertEqual(date["time_zone"] as? String, "UTC")
    }
}
