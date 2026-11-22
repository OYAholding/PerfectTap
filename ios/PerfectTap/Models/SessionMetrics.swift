import Foundation

// MARK: - SessionMetrics
//
// Per-round timing statistics computed from the signed error of every tap.
// These are GAME statistics ("how consistent was your timing in PerfectTap"),
// not a medical or attention measure — see docs/research/ADHD_ATTENTION_EVIDENCE.md
// (R1) and docs/research/COMPLIANCE.md. Stored on-device only; never uploaded,
// never used for ads.
//
// Signed error: milliseconds between the tap and the moment the indicator was
// (or will be) exactly at the bar centre. Negative = early, positive = late.
// The nearest centre crossing is always the direct one (no reflection in
// between), so error = (position − 0.5) × direction × secondsPerSweep.

struct SessionMetrics: Codable, Equatable, Identifiable {
    var id: UUID = UUID()
    var date: Date
    var mode: String
    /// Sessions are only comparable within the same protocol (same mode,
    /// length and pace). Practice: "practice:180:1.20". Other modes: rawValue.
    var protocolKey: String
    var durationSec: Double
    var taps: Int
    var hits: Int        // non-MISS taps
    var perfects: Int
    var meanSignedErrorMs: Double
    var meanAbsErrorMs: Double
    var sdErrorMs: Double
    /// Taps whose error was more than 2.5 SD from the round mean (≥ 10 taps).
    var lapses: Int
    /// The round ran to its natural end (timer / lives), not quit early.
    var completed: Bool

    var hitRate: Double { taps > 0 ? Double(hits) / Double(taps) : 0 }
    var perfectRate: Double { taps > 0 ? Double(perfects) / Double(taps) : 0 }

    static let minTapsForLapses = 10
    static let lapseSD = 2.5

    /// Signed timing error in ms for a tap at `position` moving in `direction`
    /// with `speed` seconds per full sweep.
    static func signedErrorMs(position: Double, direction: Double, speed: Double) -> Double {
        (position - 0.5) * (direction >= 0 ? 1 : -1) * speed * 1000
    }

    /// Returns nil when there were no taps.
    static func compute(mode: GameMode, protocolKey: String, date: Date = Date(),
                        durationSec: Double, errorsMs: [Double],
                        hits: Int, perfects: Int, completed: Bool) -> SessionMetrics? {
        guard !errorsMs.isEmpty else { return nil }
        let n = Double(errorsMs.count)
        let mean = errorsMs.reduce(0, +) / n
        let meanAbs = errorsMs.reduce(0) { $0 + abs($1) } / n
        let variance = errorsMs.count > 1
            ? errorsMs.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / (n - 1)
            : 0
        let sd = variance.squareRoot()
        var lapses = 0
        if errorsMs.count >= minTapsForLapses, sd > 0 {
            lapses = errorsMs.filter { abs($0 - mean) > lapseSD * sd }.count
        }
        return SessionMetrics(date: date, mode: mode.rawValue, protocolKey: protocolKey,
                              durationSec: durationSec, taps: errorsMs.count, hits: hits,
                              perfects: perfects, meanSignedErrorMs: mean, meanAbsErrorMs: meanAbs,
                              sdErrorMs: sd, lapses: lapses, completed: completed)
    }
}

// MARK: - Practice Session protocol

enum PracticeSession {
    /// Fixed pace: Classic's starting speed (PERFECT window ±48 ms).
    static let speed: Double = 1.2
    static let durations: [Int] = [60, 180, 300]
    static let defaultDuration = 180
    private static let durationKey = "pt_practice_duration"

    static var selectedDuration: Int {
        get {
            let v = UserDefaults.standard.integer(forKey: durationKey)
            return durations.contains(v) ? v : defaultDuration
        }
        set { UserDefaults.standard.set(newValue, forKey: durationKey) }
    }

    static func protocolKey(duration: Int) -> String {
        "practice:\(duration):\(String(format: "%.2f", speed))"
    }
}

// MARK: - Store (local only, bounded)

/// Keeps the last `capacity` sessions in Application Support. Reads are served
/// from memory; writes go to a serial utility queue so round end never waits
/// on disk I/O (see the 1.1.1 round-end stall fix).
final class SessionMetricsStore: @unchecked Sendable {
    static let shared = SessionMetricsStore()
    static let capacity = 200

    private let queue = DispatchQueue(label: "com.perfecttap.sessionMetrics", qos: .utility)
    private let lock = NSLock()
    private var cache: [SessionMetrics]?
    private let fileURL: URL

    init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            self.fileURL = dir.appendingPathComponent("session-metrics.json")
        }
    }

    /// Newest first.
    func all() -> [SessionMetrics] {
        lock.lock(); defer { lock.unlock() }
        if let cache { return cache }
        let loaded = (try? Data(contentsOf: fileURL))
            .flatMap { try? JSONDecoder().decode([SessionMetrics].self, from: $0) } ?? []
        cache = loaded
        return loaded
    }

    func sessions(protocolKey: String) -> [SessionMetrics] {
        all().filter { $0.protocolKey == protocolKey }
    }

    func record(_ metrics: SessionMetrics) {
        var list = all()
        list.insert(metrics, at: 0)
        if list.count > Self.capacity { list = Array(list.prefix(Self.capacity)) }
        lock.lock(); cache = list; lock.unlock()
        persist(list)
    }

    func clearAll() {
        lock.lock(); cache = []; lock.unlock()
        let url = fileURL
        queue.async { try? FileManager.default.removeItem(at: url) }
    }

    /// Blocks until pending writes finish (tests).
    func waitForWrites() { queue.sync {} }

    private func persist(_ list: [SessionMetrics]) {
        let url = fileURL
        queue.async {
            guard let data = try? JSONEncoder().encode(list) else { return }
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                     withIntermediateDirectories: true)
            try? data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        }
    }
}
