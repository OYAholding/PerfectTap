import Foundation

// MARK: - Duel match model (mirrors Firestore duels/{duelId})
struct Duel: Codable, Identifiable {
    var id: String = ""
    var code: String = ""
    var hostId: String = ""
    var hostName: String = ""
    var hostAvatar: String? = nil
    var hostScore: Int? = nil
    var hostCombo: Int? = nil
    var guestId: String? = nil
    var guestName: String? = nil
    var guestAvatar: String? = nil
    var guestScore: Int? = nil
    var guestCombo: Int? = nil
    var mode: GameMode = .duel
    var status: DuelStatus = .waiting
    var createdAt: Date = Date()

    enum DuelStatus: String, Codable {
        case waiting     = "waiting"
        case inProgress  = "in_progress"
        case completed   = "completed"
    }

    enum ParticipantRole {
        case host
        case guest
    }

    static func scoreCountsAsFinished(_ score: Int?) -> Bool {
        guard let score else { return false }
        return score >= 0
    }

    var hostFinished: Bool { Self.scoreCountsAsFinished(hostScore) }
    var guestFinished: Bool { Self.scoreCountsAsFinished(guestScore) }
    var bothFinished: Bool { hostFinished && guestFinished }
    var isComplete: Bool { status == .completed || bothFinished }

    func participantRole(forUID uid: String) -> ParticipantRole? {
        if uid == hostId { return .host }
        if let guestId, uid == guestId { return .guest }
        return nil
    }

    func isAwaitingOpponent(forUID uid: String) -> Bool {
        guard !isComplete, let role = participantRole(forUID: uid) else { return false }
        switch role {
        case .host:
            return hostFinished && !guestFinished
        case .guest:
            return guestFinished && !hostFinished
        }
    }

    func isActionableForPlay(forUID uid: String) -> Bool {
        guard status == .inProgress, !isComplete, let role = participantRole(forUID: uid) else {
            return false
        }
        switch role {
        case .host:
            guard let guestId, !guestId.isEmpty else { return false }
            return !hostFinished
        case .guest:
            return !guestFinished
        }
    }

    func result(forUID uid: String) -> DuelResult {
        guard let myScoreRaw = uid == hostId ? hostScore : guestScore,
              let theirScoreRaw = uid == hostId ? guestScore : hostScore,
              Self.scoreCountsAsFinished(myScoreRaw),
              Self.scoreCountsAsFinished(theirScoreRaw)
        else { return .unknown }
        let myScore = myScoreRaw
        let theirScore = theirScoreRaw
        if myScore > theirScore { return .win }
        if myScore < theirScore { return .loss }
        return .tie
    }

    enum DuelResult {
        case win, loss, tie, unknown
    }
}

// MARK: - Firestore encoding helpers
extension Duel {
    // Keys matching Firestore field names
    enum CodingKeys: String, CodingKey {
        case id, code
        case hostId     = "host_id"
        case hostName   = "host_name"
        case hostAvatar = "host_avatar"
        case hostScore  = "host_score"
        case hostCombo  = "host_combo"
        case guestId    = "guest_id"
        case guestName  = "guest_name"
        case guestAvatar = "guest_avatar"
        case guestScore = "guest_score"
        case guestCombo = "guest_combo"
        case mode
        case status
        case createdAt  = "created_at"
    }
}
