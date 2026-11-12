import Foundation

// MARK: - TimingEngine
// Pure, side-effect-free timing math shared by GameViewModel and unit tests.
// Foundation-only on purpose: no SwiftUI/UIKit/Firebase so it can be tested
// on any host.
//
// Coordinate system: indicator position is 0.0 (left edge) … 1.0 (right edge),
// bar center is 0.5. Zone sizes in GameConfig (0.04 / 0.10 / 0.20) are
// fractions of the FULL bar width measured from the center — exactly how the
// original web version (`Math.abs(pos - 50) <= 4`) and TapBarView draw them.

// MARK: - Accuracy result from a tap
enum TapAccuracy: String {
    case perfect = "PERFECT"
    case great   = "GREAT"
    case good    = "GOOD"
    case miss    = "MISS"

    var color: String {
        switch self {
        case .perfect: return "violet"
        case .great:   return "green"
        case .good:    return "yellow"
        case .miss:    return "red"
        }
    }
}

/// EARLY = tapped before the indicator reached the center; LATE = after.
enum TapTiming: String {
    case early = "EARLY"
    case late = "LATE"
}

enum TimingEngine {

    /// Moves the indicator by `dt` seconds at `speed` (seconds per full sweep),
    /// reflecting off both edges. Any overshoot past an edge is carried back
    /// into the bar instead of being clamped, so long frames don't "stick"
    /// the indicator to the wall. Negative `dt` extrapolates backwards in time.
    static func advance(position: Double, direction: Double, dt: Double, speed: Double)
        -> (position: Double, direction: Double)
    {
        guard speed > 0, dt != 0, dt.isFinite else { return (position, direction) }
        var dir: Double = direction >= 0 ? 1 : -1
        let backwards = dt < 0
        if backwards { dir = -dir }
        var pos = position + dir * (abs(dt) / speed)

        // Reflect (bounded loop — at most a few iterations for sane dt).
        var guardCount = 0
        while (pos > 1.0 || pos < 0.0) && guardCount < 8 {
            if pos > 1.0 { pos = 2.0 - pos; dir = -1 }
            else if pos < 0.0 { pos = -pos; dir = 1 }
            guardCount += 1
        }
        pos = min(1.0, max(0.0, pos))
        if backwards { dir = -dir }
        return (pos, dir)
    }

    /// Whether a tap came before or after the indicator crossed the center,
    /// given its travel direction at that moment (+1 → right, −1 → left).
    /// Used for the EARLY / LATE hint under non-PERFECT results.
    static func timing(position: Double, direction: Double) -> TapTiming {
        let ahead = (0.5 - position) * (direction >= 0 ? 1 : -1)
        return ahead > 0 ? .early : .late
    }

    /// Distance from the bar center as a fraction of the full bar width (0 … 0.5).
    static func distanceFromCenter(_ position: Double) -> Double {
        abs(position - 0.5)
    }

    /// Classifies a tap at `position`.
    /// - Parameters:
    ///   - perfectScale: multiplier applied to the PERFECT half-width (Tiny Window, Precision…).
    ///   - strictPerfectOnly: anything that isn't PERFECT becomes MISS (Precision mode).
    static func accuracy(at position: Double,
                         perfectScale: Double = 1.0,
                         strictPerfectOnly: Bool = false) -> TapAccuracy {
        // Epsilon keeps exact boundaries inclusive on BOTH sides
        // (|0.54 - 0.5| and |0.46 - 0.5| differ in floating point).
        let d = distanceFromCenter(position) - boundaryEpsilon
        let result: TapAccuracy
        if d <= GameConfig.perfectZone * perfectScale { result = .perfect }
        else if d <= GameConfig.greatZone            { result = .great }
        else if d <= GameConfig.goodZone             { result = .good }
        else                                          { result = .miss }
        if strictPerfectOnly && result != .perfect { return .miss }
        return result
    }

    static func basePoints(for accuracy: TapAccuracy) -> Int {
        switch accuracy {
        case .perfect: return GameConfig.perfectPoints
        case .great:   return GameConfig.greatPoints
        case .good:    return GameConfig.goodPoints
        case .miss:    return GameConfig.missPoints
        }
    }

    /// Max amount of time (seconds) we'll extrapolate the indicator from the
    /// last rendered frame to a touch timestamp. Larger gaps mean the touch
    /// timestamp is unreliable (or we were paused), so we fall back to the
    /// last frame's position.
    static let maxTouchExtrapolation: Double = 0.050

    static let boundaryEpsilon: Double = 1e-9

    /// How many display frames the on-screen indicator lags the simulation
    /// (CADisplayLink tick → SwiftUI commit → render server → glass).
    /// 1 frame is a conservative default; a future "timing calibration"
    /// setting could let players tune this per device.
    static let displayLatencyFrames: Double = 1.0
}
