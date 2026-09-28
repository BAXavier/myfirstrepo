import Foundation

/// Detects N quick taps of a lone modifier key (e.g. ⌥ ⌥ ⌥).
/// Feed it modifier down/up transitions; any other key or modifier in between cancels the sequence.
public struct ModifierTapDetector: Sendable {
    public enum Event: Equatable, Sendable { case none, tap, trigger }

    public var requiredTaps: Int
    /// Max time between consecutive taps.
    public var maxGap: TimeInterval
    /// A press held longer than this is not a tap (you're using ⌥ as a modifier).
    public var maxHold: TimeInterval

    private var downAt: TimeInterval?
    private var lastTapAt: TimeInterval?
    private var count = 0
    private var tainted = false

    public init(requiredTaps: Int = 3, maxGap: TimeInterval = 0.45, maxHold: TimeInterval = 0.3) {
        self.requiredTaps = requiredTaps
        self.maxGap = maxGap
        self.maxHold = maxHold
    }

    public mutating func modifierDown(at t: TimeInterval) {
        downAt = t
        tainted = false
    }

    public mutating func modifierUp(at t: TimeInterval) -> Event {
        defer { downAt = nil }
        guard let d = downAt, !tainted, t - d <= maxHold else { count = 0; return .none }
        if let last = lastTapAt, d - last > maxGap { count = 0 }
        count += 1
        lastTapAt = t
        if count >= requiredTaps {
            count = 0
            lastTapAt = nil
            return .trigger
        }
        return .tap
    }

    /// Another key or modifier was used: whatever this was, it wasn't a tap sequence.
    public mutating func interrupt() {
        tainted = true
        count = 0
        lastTapAt = nil
    }
}

/// Detects a "swirl": the pointer/finger circling ~2 times quickly around a roughly fixed center.
/// O(n) per sample over a short window (n ≲ 150), so it's cheap enough to run on every mouse move.
public struct SwirlDetector: Sendable {
    public var requiredTurns: Double
    public var window: TimeInterval
    public var minRadius: Double
    public var maxRadius: Double

    private struct P: Sendable { var x, y, t: Double }
    private var points: [P] = []

    public init(requiredTurns: Double = 1.75, window: TimeInterval = 1.6,
                minRadius: Double = 20, maxRadius: Double = 500) {
        self.requiredTurns = requiredTurns
        self.window = window
        self.minRadius = minRadius
        self.maxRadius = maxRadius
    }

    public mutating func reset() { points.removeAll(keepingCapacity: true) }

    /// Returns true once when a swirl completes (and resets).
    public mutating func add(x: Double, y: Double, t: TimeInterval) -> Bool {
        if let last = points.last {
            // Throttle: ignore sub-step jitter, and start over after a pause.
            if t - last.t > 0.25 { points.removeAll(keepingCapacity: true) }
            else if hypot(x - last.x, y - last.y) < minRadius / 5 { return false }
        }
        points.append(P(x: x, y: y, t: t))
        if let firstValid = points.firstIndex(where: { t - $0.t <= window }), firstValid > 0 {
            points.removeFirst(firstValid)
        }
        guard points.count >= 16 else { return false }

        let n = Double(points.count)
        let cx = points.reduce(0) { $0 + $1.x } / n
        let cy = points.reduce(0) { $0 + $1.y } / n

        var radii = [Double]()
        radii.reserveCapacity(points.count)
        var total = 0.0, positive = 0, negative = 0
        var prevAngle = atan2(points[0].y - cy, points[0].x - cx)
        radii.append(hypot(points[0].x - cx, points[0].y - cy))
        for p in points.dropFirst() {
            let a = atan2(p.y - cy, p.x - cx)
            var d = a - prevAngle
            if d > .pi { d -= 2 * .pi } else if d <= -.pi { d += 2 * .pi }
            prevAngle = a
            radii.append(hypot(p.x - cx, p.y - cy))
            if abs(d) > 1.2 { continue } // passing near the center (a scribble, not a circle)
            total += d
            if d > 0 { positive += 1 } else if d < 0 { negative += 1 }
        }

        guard abs(total) >= requiredTurns * 2 * .pi else { return false }
        let mean = radii.reduce(0, +) / n
        guard mean >= minRadius, mean <= maxRadius else { return false }
        let variance = radii.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / n
        guard variance.squareRoot() / mean < 0.45 else { return false } // round-ish, not a line

        // Roundness: minor/major axis ratio from the point covariance rejects thin back-and-forth scribbles.
        var sxx = 0.0, syy = 0.0, sxy = 0.0
        for p in points {
            sxx += (p.x - cx) * (p.x - cx)
            syy += (p.y - cy) * (p.y - cy)
            sxy += (p.x - cx) * (p.y - cy)
        }
        let trace = (sxx + syy) / n, det = (sxx * syy - sxy * sxy) / (n * n)
        let disc = max(0, trace * trace / 4 - det).squareRoot()
        let major = trace / 2 + disc, minor = max(0, trace / 2 - disc)
        guard major > 0, (minor / major).squareRoot() >= 0.35 else { return false }

        guard Double(max(positive, negative)) / Double(max(1, positive + negative)) > 0.85 else { return false }

        reset()
        return true
    }
}
