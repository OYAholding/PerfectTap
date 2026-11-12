import Foundation

// MARK: - BackendCodec
// Backend-neutral mapping between the app's models and the snake_case
// dictionaries both backends store (Firestore documents / Postgres JSON).
// Moved out of FirebaseService unchanged so both implementations share it.
enum BackendCodec {

    // MARK: Values

    static func intValue(_ raw: Any?) -> Int? {
        if let value = raw as? Int { return value }
        if let value = raw as? NSNumber { return value.intValue }
        if let value = raw as? String { return Int(value) }
        return nil
    }

    static func doubleValue(_ raw: Any?) -> Double? {
        if let value = raw as? Double { return value }
        if let value = raw as? NSNumber { return value.doubleValue }
        if let value = raw as? String { return Double(value) }
        return nil
    }

    private static let isoFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let isoPlain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    /// Date from a Swift Date, a Firestore Timestamp, or a Postgres timestamptz string.
    static func dateValue(_ raw: Any?) -> Date? {
        if let date = raw as? Date { return date }
        if let string = raw as? String { return parseTimestamp(string) }
        // Firestore Timestamp without importing FirebaseFirestore here.
        if let obj = raw as? NSObject, obj.responds(to: NSSelectorFromString("dateValue")),
           let date = obj.perform(NSSelectorFromString("dateValue"))?.takeUnretainedValue() as? Date {
            return date
        }
        return nil
    }

    /// PostgREST returns e.g. "2026-11-12T08:49:16.381372+00:00" (microseconds).
    static func parseTimestamp(_ string: String) -> Date? {
        if let d = isoFractional.date(from: string) ?? isoPlain.date(from: string) { return d }
        // Trim sub-millisecond digits ISO8601DateFormatter can't parse.
        if let dot = string.firstIndex(of: "."),
           let tz = string[dot...].firstIndex(where: { $0 == "+" || $0 == "-" || $0 == "Z" }) {
            let fraction = string[string.index(after: dot)..<tz].prefix(3)
            let trimmed = String(string[..<dot]) + "." + fraction + String(string[tz...])
            return isoFractional.date(from: trimmed)
        }
        return nil
    }

    // MARK: Duel

    static func normalizedDuelScore(_ raw: Any?) -> Int? {
        guard let score = intValue(raw), Duel.scoreCountsAsFinished(score) else { return nil }
        return score
    }

    static func decodeDuel(id: String, data: [String: Any]) -> Duel {
        var duel = Duel()
        duel.id = id
        duel.code = data["code"] as? String ?? ""
        duel.hostId = data["host_id"] as? String ?? ""
        duel.hostName = data["host_name"] as? String ?? ""
        duel.hostAvatar = data["host_avatar"] as? String
        duel.hostScore = normalizedDuelScore(data["host_score"])
        duel.hostCombo = intValue(data["host_combo"])
        duel.guestId = data["guest_id"] as? String
        duel.guestName = data["guest_name"] as? String
        duel.guestAvatar = data["guest_avatar"] as? String
        duel.guestScore = normalizedDuelScore(data["guest_score"])
        duel.guestCombo = intValue(data["guest_combo"])
        duel.mode = GameMode(rawValue: data["mode"] as? String ?? "") ?? .duel
        duel.status = Duel.DuelStatus(rawValue: data["status"] as? String ?? "waiting") ?? .waiting
        if let createdAt = dateValue(data["created_at"]) {
            duel.createdAt = createdAt
        }
        return duel
    }

    // MARK: PlayerProfile

    static func decodeProfile(_ data: [String: Any]) -> PlayerProfile? {
        var p = PlayerProfile()
        p.uid              = data["uid"] as? String ?? ""
        p.username         = data["username"] as? String ?? ""
        p.avatar           = data["avatar"] as? String ?? "default"
        p.coins            = intValue(data["coins"]) ?? 0
        p.level            = intValue(data["level"]) ?? 1
        p.xp               = intValue(data["xp"]) ?? 0
        p.bestClassic      = intValue(data["best_classic"]) ?? 0
        p.bestEndless      = intValue(data["best_endless"]) ?? 0
        p.bestTimed        = intValue(data["best_timed"]) ?? 0
        p.bestSudden       = intValue(data["best_sudden"]) ?? 0
        p.bestComboFrenzy  = intValue(data["best_combofrenzy"]) ?? 0
        p.friendCode       = data["friend_code"] as? String ?? ""
        p.friends          = data["friends"] as? [String] ?? []
        p.ownedItems       = data["owned_items"] as? [String] ?? []
        p.equippedTheme    = data["equipped_theme"] as? String ?? "default"
        p.equippedAvatar   = data["equipped_avatar"] as? String ?? "default"
        p.equippedTapFX    = data["equipped_tapfx"] as? String ?? "fx_default"
        p.equippedTrail    = data["equipped_trail"] as? String ?? "trail_none"
        p.equippedBadge    = data["equipped_badge"] as? String ?? ""
        p.dailyRewardStreak    = intValue(data["daily_reward_streak"]) ?? 0
        p.dailyRewardLastClaim = data["daily_reward_last_claim"] as? String ?? ""
        p.activeChallenge  = data["active_challenge"] as? String ?? ""
        p.seasonXP         = intValue(data["season_xp"]) ?? 0
        p.seasonTier       = intValue(data["season_tier"]) ?? 0
        p.seasonPremium    = data["season_premium"] as? Bool ?? false
        p.seasonAdProgress = intValue(data["season_ad_progress"]) ?? 0
        p.seasonClaimedTiers = (data["season_claimed_tiers"] as? [Any] ?? []).compactMap { intValue($0) }
        p.questsJSON       = data["quests_json"] as? String ?? "{}"
        p.achievements     = data["achievements"] as? [String] ?? []
        p.completedChallenges = data["completed_challenges"] as? [String] ?? []
        p.noAds            = data["no_ads"] as? Bool ?? false
        p.revivesUsedToday = intValue(data["revives_used_today"]) ?? 0
        p.lastReviveDate   = data["last_revive_date"] as? String ?? ""
        if let extra = data["best_scores_extra"] as? [String: Any] {
            p.bestScoresExtra = extra.reduce(into: [:]) { partialResult, entry in
                if let value = intValue(entry.value) {
                    partialResult[entry.key] = value
                }
            }
        }
        for mode in GameMode.selectableModes {
            let key = mode.bestScoreKey
            guard !key.isEmpty else { continue }
            if let value = intValue(data[key]) {
                p.bestScoresExtra[key] = max(p.bestScoresExtra[key] ?? 0, value)
            }
        }
        if let boostData = data["boost"] as? [String: Any],
           let value = doubleValue(boostData["value"]) {
            p.boost = ScoreBoost(
                value: value,
                used: boostData["used"] as? Bool ?? false,
                games: intValue(boostData["games"]) ?? 0
            )
        }
        if let history = data["score_history"] as? [[String: Any]] {
            p.scoreHistory = history.compactMap { row in
                guard let score = intValue(row["score"]), let date = row["date"] as? String else { return nil }
                let id = (row["id"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? UUID().uuidString
                return ScoreEntry(id: id, score: score, date: date)
            }
        }
        if let statsData = data["stats"] as? [String: Any] {
            p.stats.totalGames        = intValue(statsData["totalGames"]) ?? 0
            p.stats.duelWins          = intValue(statsData["duelWins"]) ?? 0
            p.stats.duelLosses        = intValue(statsData["duelLosses"]) ?? 0
            p.stats.duelTies          = intValue(statsData["duelTies"]) ?? 0
            p.stats.totalCoinsEarned  = intValue(statsData["totalCoinsEarned"]) ?? 0
            p.stats.perfectTaps       = intValue(statsData["perfectTaps"]) ?? 0
            p.stats.highestCombo      = intValue(statsData["highestCombo"]) ?? 0
        }
        p.normalizeAndMigrate()
        return p
    }

    /// `nullValue` is how the backend represents an explicit null
    /// (NSNull for Firestore and JSON).
    static func encodeProfile(_ profile: PlayerProfile) -> [String: Any] {
        var p = profile
        p.normalizeAndMigrate()
        var data: [String: Any] = [
            "uid": p.uid,
            "username": p.username,
            "username_lower": p.username.lowercased(),
            "avatar": p.socialAvatarID,
            "coins": p.coins,
            "level": p.level,
            "xp": p.xp,
            "best_classic": p.bestClassic,
            "best_endless": p.bestEndless,
            "best_timed": p.bestTimed,
            "best_sudden": p.bestSudden,
            "best_combofrenzy": p.bestComboFrenzy,
            "friend_code": p.friendCode,
            "friends": p.friends,
            "owned_items": p.ownedItems,
            "equipped_theme": p.equippedTheme,
            "equipped_avatar": p.equippedAvatar,
            "equipped_tapfx": p.equippedTapFX,
            "equipped_trail": p.equippedTrail,
            "equipped_badge": p.equippedBadge,
            "daily_reward_streak": p.dailyRewardStreak,
            "daily_reward_last_claim": p.dailyRewardLastClaim,
            "active_challenge": p.activeChallenge,
            "season_xp": p.seasonXP,
            "season_tier": p.seasonTier,
            "season_premium": p.seasonPremium,
            "season_ad_progress": p.seasonAdProgress,
            "season_claimed_tiers": p.seasonClaimedTiers,
            "quests_json": p.questsJSON,
            "achievements": p.achievements,
            "completed_challenges": p.completedChallenges,
            "no_ads": p.noAds,
            "revives_used_today": p.revivesUsedToday,
            "last_revive_date": p.lastReviveDate,
            "best_scores_extra": p.bestScoresExtra,
            "score_history": p.scoreHistory.map { ["id": $0.id, "score": $0.score, "date": $0.date] },
            "stats": [
                "totalGames": p.stats.totalGames,
                "duelWins": p.stats.duelWins,
                "duelLosses": p.stats.duelLosses,
                "duelTies": p.stats.duelTies,
                "totalCoinsEarned": p.stats.totalCoinsEarned,
                "perfectTaps": p.stats.perfectTaps,
                "highestCombo": p.stats.highestCombo,
            ]
        ]
        if let boost = p.boost {
            data["boost"] = ["value": boost.value, "used": boost.used, "games": boost.games]
        } else {
            data["boost"] = NSNull()
        }
        for (key, value) in p.bestScoresExtra {
            data[key] = value
        }
        return data
    }
}

// MARK: - JSONPayload
/// Encodes an untyped `[String: Any]` tree (as produced by `encodeProfile`)
/// so it can be sent as a Postgres jsonb RPC parameter.
struct JSONPayload: Encodable {
    let value: Any

    init(_ value: Any) { self.value = value }

    private struct Key: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }
        init(_ s: String) { stringValue = s }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }

    func encode(to encoder: Encoder) throws {
        switch value {
        case let dict as [String: Any]:
            var c = encoder.container(keyedBy: Key.self)
            for (k, v) in dict { try c.encode(JSONPayload(v), forKey: Key(k)) }
        case let array as [Any]:
            var c = encoder.unkeyedContainer()
            for v in array { try c.encode(JSONPayload(v)) }
        default:
            var c = encoder.singleValueContainer()
            switch value {
            case is NSNull: try c.encodeNil()
            case let s as String: try c.encode(s)
            // NSNumber first: Swift Bool/Int/Double bridge to it, and the CF type
            // check keeps 1/0 from JSONSerialization from being read as Bool.
            case let n as NSNumber:
                if CFGetTypeID(n) == CFBooleanGetTypeID() { try c.encode(n.boolValue) }
                else if CFNumberIsFloatType(n) { try c.encode(n.doubleValue) }
                else { try c.encode(n.int64Value) }
            case let date as Date: try c.encode(ISO8601DateFormatter().string(from: date))
            default:
                throw EncodingError.invalidValue(value, .init(codingPath: encoder.codingPath,
                                                              debugDescription: "Unsupported JSON value \(type(of: value))"))
            }
        }
    }
}
