import Foundation

// MARK: - PendingDuelStore
// Durable record of duel runs this device played, so that:
//  * a score submission that failed (offline, app killed) is retried later;
//  * win/loss/tie is counted exactly once per duel, even if the player left
//    the results screen before the opponent finished.
// Previously both only happened while DuelResultsView stayed on screen.
struct PendingDuel: Codable, Equatable {
    let duelId: String
    let role: String
    let score: Int
    let maxCombo: Int
    let taps: Int
    let perfects: Int
    let sessionId: String?
    var submitted: Bool
    let playedAt: TimeInterval
}

enum PendingDuelStore {
    private static let pendingKey = "perfecttap_pending_duels"
    private static let recordedKey = "perfecttap_recorded_duel_results"
    private static let maxAge: TimeInterval = 8 * 24 * 60 * 60   // server drops unfinished duels after 7 days
    private static let maxRecorded = 300

    static func all() -> [PendingDuel] {
        guard let data = UserDefaults.standard.data(forKey: pendingKey),
              let list = try? JSONDecoder().decode([PendingDuel].self, from: data) else { return [] }
        let cutoff = Date().timeIntervalSince1970 - maxAge
        return list.filter { $0.playedAt >= cutoff }
    }

    private static func save(_ list: [PendingDuel]) {
        if let data = try? JSONEncoder().encode(list) {
            UserDefaults.standard.set(data, forKey: pendingKey)
        }
    }

    /// Adds (or replaces) the run for a duel. One run per duel per device.
    static func upsert(_ duel: PendingDuel) {
        var list = all().filter { $0.duelId != duel.duelId }
        list.append(duel)
        save(list)
    }

    static func markSubmitted(duelId: String) {
        save(all().map { var d = $0; if d.duelId == duelId { d.submitted = true }; return d })
    }

    static func remove(duelId: String) {
        save(all().filter { $0.duelId != duelId })
    }

    /// Most recent duel played here (results screen fallback once DuelContext is cleared).
    static var mostRecentDuelId: String? {
        all().max(by: { $0.playedAt < $1.playedAt })?.duelId
    }

    // MARK: One-time stats receipts

    static func isStatsRecorded(duelId: String) -> Bool {
        (UserDefaults.standard.stringArray(forKey: recordedKey) ?? []).contains(duelId)
    }

    static func markStatsRecorded(duelId: String) {
        var ids = UserDefaults.standard.stringArray(forKey: recordedKey) ?? []
        guard !ids.contains(duelId) else { return }
        ids.insert(duelId, at: 0)
        UserDefaults.standard.set(Array(ids.prefix(maxRecorded)), forKey: recordedKey)
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: pendingKey)
        UserDefaults.standard.removeObject(forKey: recordedKey)
    }
}

// MARK: - DuelSettlement
@MainActor
enum DuelSettlement {
    private static var isSettling = false

    /// Submits a finished duel run. Returns true once the server has the score.
    @discardableResult
    static func submit(_ pending: PendingDuel) async -> Bool {
        PendingDuelStore.upsert(pending)
        let ok = await Backend.shared.submitDuelScore(
            duelId: pending.duelId, role: pending.role, score: pending.score, maxCombo: pending.maxCombo,
            taps: pending.taps, perfects: pending.perfects, sessionId: pending.sessionId)
        if ok { PendingDuelStore.markSubmitted(duelId: pending.duelId) }
        return ok
    }

    /// Counts win/loss/tie once per duel. Safe to call repeatedly.
    @discardableResult
    static func recordStatsIfNeeded(_ duel: Duel, uid: String) -> Bool {
        guard duel.isComplete, !PendingDuelStore.isStatsRecorded(duelId: duel.id),
              duel.participantRole(forUID: uid) != nil else { return false }
        let result = duel.result(forUID: uid)
        guard result != .unknown else { return false }
        PendingDuelStore.markStatsRecorded(duelId: duel.id)
        EconomyManager.shared.updateProfile { profile in
            switch result {
            case .win: profile.stats.duelWins += 1
            case .loss: profile.stats.duelLosses += 1
            case .tie: profile.stats.duelTies += 1
            case .unknown: break
            }
        }
        PendingDuelStore.remove(duelId: duel.id)
        return true
    }

    /// Retries unsent scores and settles finished duels. Called from Home.
    static func settle() async {
        guard !isSettling, let uid = Backend.shared.currentUID else { return }
        isSettling = true
        defer { isSettling = false }
        var pending = PendingDuelStore.all()
        for run in pending where !run.submitted {
            _ = await submit(run)
        }
        pending = PendingDuelStore.all().filter(\.submitted)
        guard !pending.isEmpty else { return }
        let duels = await Backend.shared.loadDuels(duelIds: pending.map(\.duelId))
        for duel in duels.values {
            recordStatsIfNeeded(duel, uid: uid)
        }
    }
}
