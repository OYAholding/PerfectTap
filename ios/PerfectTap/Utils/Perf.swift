import Foundation
import QuartzCore
import os

// MARK: - Perf instrumentation
//
// Two layers:
//  1. os_signpost intervals (subsystem `com.perfecttap.perf`, category
//     PointsOfInterest) for Instruments on a real device. Near-zero cost when no
//     tool is recording.
//  2. An in-process probe (DEBUG + launch argument `-PTPerfProbe` only) that
//     measures main-thread frame pacing with its own display link plus the
//     duration of named spans, and writes `perf-probe.json` into the app's
//     Documents folder every 2 s. The perf UI tests and
//     `scripts/perf-run.sh` read that file from the simulator container.
//
// Release builds never run the probe: `Perf.probeEnabled` is false.

enum Perf {
    static let log = OSLog(subsystem: "com.perfecttap.perf", category: .pointsOfInterest)
    static let signposter = OSSignposter(logHandle: log)

    static let probeEnabled: Bool = {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("-PTPerfProbe")
        #else
        return false
        #endif
    }()

    /// Measure a synchronous block (signpost + probe span).
    @discardableResult
    static func measure<T>(_ name: StaticString, _ block: () throws -> T) rethrows -> T {
        let state = signposter.beginInterval(name)
        let start = CACurrentMediaTime()
        defer {
            signposter.endInterval(name, state)
            if probeEnabled {
                FrameMonitor.shared.recordSpan(String(describing: name),
                                               ms: (CACurrentMediaTime() - start) * 1000)
            }
        }
        return try block()
    }

    /// Open an interval that ends somewhere else (e.g. round end → Game Over shown).
    static func begin(_ name: StaticString) -> PerfInterval {
        PerfInterval(name: name, state: signposter.beginInterval(name), start: CACurrentMediaTime())
    }

    static func event(_ name: StaticString) {
        signposter.emitEvent(name)
    }
}

struct PerfInterval {
    let name: StaticString
    let state: OSSignpostIntervalState
    let start: CFTimeInterval

    func end() {
        Perf.signposter.endInterval(name, state)
        if Perf.probeEnabled {
            FrameMonitor.shared.recordSpan(String(describing: name),
                                           ms: (CACurrentMediaTime() - start) * 1000)
        }
    }
}

// MARK: - FrameMonitor (probe only)
/// Records every main-thread display-link delta. A delta well above 16.7 ms
/// means the main thread could not service the frame (a hitch); ≥ 250 ms is
/// reported separately as a hang-class stall.
@MainActor
final class FrameMonitor {
    static let shared = FrameMonitor()

    struct Bucket: Codable {
        var frames = 0
        var over25ms = 0     // ≥ 1 dropped frame at 60 Hz
        var over50ms = 0
        var over100ms = 0    // clearly visible hitch
        var over250ms = 0    // hang-class stall
        var maxMs = 0.0
        var totalMs = 0.0
        var samples: [Float] = []   // reservoir for percentiles (capped)

        mutating func add(_ ms: Double) {
            frames += 1
            totalMs += ms
            if ms > maxMs { maxMs = ms }
            if ms >= 25 { over25ms += 1 }
            if ms >= 50 { over50ms += 1 }
            if ms >= 100 { over100ms += 1 }
            if ms >= 250 { over250ms += 1 }
            if samples.count < 200_000 { samples.append(Float(ms)) }
        }
    }

    struct Stall: Codable {
        let atSec: Double
        let ms: Double
        let context: String
        let inGameplay: Bool
    }

    struct Span: Codable {
        var count = 0
        var totalMs = 0.0
        var maxMs = 0.0
    }

    struct Report: Codable {
        struct BucketSummary: Codable {
            let frames: Int
            let over25ms: Int
            let over50ms: Int
            let over100ms: Int
            let over250ms: Int
            let maxMs: Double
            let p50Ms: Double
            let p95Ms: Double
            let p99Ms: Double
            let hitchRatioPct: Double   // share of frames ≥ 25 ms
        }
        let build: String
        let device: String
        let uptimeSec: Double
        let all: BucketSummary
        let gameplay: BucketSummary
        let spans: [String: Span]
        let gameSessions: Int
        let residentMemoryMB: Double
        let stalls: [Stall]
        let timeline: [Mark]
    }

    private var link: CADisplayLink?
    private var last: CFTimeInterval = 0
    private var all = Bucket()
    private var gameplay = Bucket()
    /// Spans can be recorded from any thread (audio setup may run off main).
    private nonisolated let spanLock = OSAllocatedUnfairLock(initialState: [String: Span]())
    private var started: CFTimeInterval = 0
    private var flushTimer: Timer?
    private(set) var gameSessions = 0
    /// Set by GameViewModel while a round is in countdown/playing.
    var isInGameplay = false
    /// Free-form label of what the app is doing (mode, "gameOver", …).
    var context = "launch" {
        didSet {
            guard Perf.probeEnabled, timeline.count < 300 else { return }
            timeline.append(Mark(atSec: CACurrentMediaTime() - started, context: context))
        }
    }
    private var stalls: [Stall] = []
    private var timeline: [Mark] = []

    struct Mark: Codable {
        let atSec: Double
        let context: String
    }

    /// Named instant on the timeline (probe only).
    func mark(_ label: String) {
        guard Perf.probeEnabled, timeline.count < 300 else { return }
        timeline.append(Mark(atSec: CACurrentMediaTime() - started, context: label))
    }

    func startIfEnabled() {
        guard Perf.probeEnabled, link == nil else { return }
        started = CACurrentMediaTime()
        let proxy = FrameMonitorProxy { [weak self] l in self?.tick(l) }
        let l = CADisplayLink(target: proxy, selector: #selector(FrameMonitorProxy.tick(_:)))
        l.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 60, preferred: 60)
        l.add(to: .main, forMode: .common)
        link = l
        flushTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
            Task { @MainActor in FrameMonitor.shared.flush() }
        }
    }

    func noteGameStarted() { gameSessions += 1 }

    private func tick(_ l: CADisplayLink) {
        let now = l.timestamp
        guard !paused else { last = 0; return }
        defer { last = now }
        guard last > 0 else { return }
        let ms = (now - last) * 1000
        all.add(ms)
        if isInGameplay { gameplay.add(ms) }
        if ms >= 100, stalls.count < 100 {
            stalls.append(Stall(atSec: now - started, ms: ms, context: context, inGameplay: isInGameplay))
        }
    }

    private var paused = false
    /// App inactive/background: the gap is not a stall.
    func setPaused(_ value: Bool) { paused = value; last = 0 }

    nonisolated func recordSpan(_ name: String, ms: Double) {
        spanLock.withLock { spans in
            var s = spans[name, default: Span()]
            s.count += 1
            s.totalMs += ms
            if ms > s.maxMs { s.maxMs = ms }
            spans[name] = s
        }
    }

    func flush() {
        let report = makeReport()
        let spansCopy = report
        DispatchQueue.global(qos: .utility).async {
            guard let data = try? JSONEncoder().encode(spansCopy),
                  let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            else { return }
            try? data.write(to: dir.appendingPathComponent("perf-probe.json"), options: .atomic)
        }
    }

    private func summarize(_ b: Bucket) -> Report.BucketSummary {
        let sorted = b.samples.sorted()
        func pct(_ p: Double) -> Double {
            guard !sorted.isEmpty else { return 0 }
            let idx = min(sorted.count - 1, Int(Double(sorted.count - 1) * p))
            return Double(sorted[idx])
        }
        return .init(frames: b.frames, over25ms: b.over25ms, over50ms: b.over50ms,
                     over100ms: b.over100ms, over250ms: b.over250ms, maxMs: b.maxMs,
                     p50Ms: pct(0.5), p95Ms: pct(0.95), p99Ms: pct(0.99),
                     hitchRatioPct: b.frames > 0 ? Double(b.over25ms) / Double(b.frames) * 100 : 0)
    }

    private func makeReport() -> Report {
        let info = Bundle.main.infoDictionary
        let build = "\(info?["CFBundleShortVersionString"] ?? "?") (\(info?["CFBundleVersion"] ?? "?"))"
        return Report(build: build,
                      device: ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] ?? "device",
                      uptimeSec: CACurrentMediaTime() - started,
                      all: summarize(all), gameplay: summarize(gameplay),
                      spans: spanLock.withLock { $0 }, gameSessions: gameSessions,
                      residentMemoryMB: Self.residentMemoryMB(), stalls: stalls, timeline: timeline)
    }

    private static func residentMemoryMB() -> Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return kr == KERN_SUCCESS ? Double(info.phys_footprint) / 1_048_576 : 0
    }
}

private final class FrameMonitorProxy {
    let cb: (CADisplayLink) -> Void
    init(_ cb: @escaping (CADisplayLink) -> Void) { self.cb = cb }
    @objc func tick(_ l: CADisplayLink) { cb(l) }
}
