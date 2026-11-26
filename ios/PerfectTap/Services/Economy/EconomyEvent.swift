import Foundation

// MARK: - Economy wire types (docs/ECONOMY_SERVICE_CONTRACT.md, v1)
//
// The client never sends an amount. It sends *what happened* (`source` +
// `payload`) under a client-generated `event_key` that is created once, stored
// in the outbox before the first send and reused on every retry.

/// JSON scalar used in `p_payload`. Kept tiny on purpose: payloads are flat.
enum EconomyJSONValue: Codable, Equatable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(Bool.self) { self = .bool(value); return }
        if let value = try? container.decode(Int.self) { self = .int(value); return }
        if let value = try? container.decode(Double.self) { self = .double(value); return }
        self = .string(try container.decode(String.self))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .int(let value): try container.encode(value)
        case .double(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        }
    }
}

/// `p_source` values the client submits through `submit_economy_event`
/// (plus `daily_reward`, which travels through `claim_daily_economy_reward`).
enum EconomyEventSource: String, Codable, CaseIterable {
    case gameplay
    case duel
    case quest
    case achievement
    case challenge
    case seasonTier = "season_tier"
    case wheel
    case starterItem = "starter_item"
    case dailyReward = "daily_reward"
}

/// One persisted outbox entry.
struct EconomyEvent: Codable, Equatable, Identifiable {
    let eventKey: UUID
    let source: EconomyEventSource
    let payload: [String: EconomyJSONValue]
    let createdAt: Date
    var attempts: Int = 0
    var nextAttemptAt: Date? = nil
    /// Client-side estimate shown to the player as "pending". Never sent.
    var estimatedCoins: Int = 0

    var id: UUID { eventKey }
}

/// Normalized result of any economy RPC (contract "Response").
struct EconomyRPCResult: Equatable {
    var status: String
    var granted: Int? = nil
    var balance: Int? = nil
    var coinDebt: Int? = nil
    var segmentIndex: Int? = nil
    var itemID: String? = nil
}

/// `get_my_economy_state()`.
struct EconomyStateSnapshot: Equatable {
    var confirmedBalance: Int
    var coinDebt: Int
    var configVersion: String?
    var legacyStatus: String
}

/// Why an economy RPC failed.
enum EconomyRemoteFailure: Error, Equatable {
    /// Did not reach the server (offline, timeout, 5xx relay, no session).
    case network
    /// `private.fail(code)` — the contract error code.
    case server(String)
}

/// What the outbox does with an event after a failure.
enum EconomyErrorDisposition: Equatable {
    /// The server already holds the effect: remove the event.
    case success
    /// Keep the event and retry with backoff.
    case retry
    /// Terminal rejection: drop the event and log it.
    case drop
    /// Keep the event and retry with backoff, without stopping the flush of
    /// the events queued after it (season claims across a boundary).
    case retryNonBlocking
}

enum EconomyErrorPolicy {
    /// Contract: `duplicate`, `already_claimed`, `already_owned` are terminal-success.
    static let terminalSuccess: Set<String> = ["duplicate", "already_claimed", "already_owned"]
    /// Temporary server states: the event stays valid and is retried.
    static let retryable: Set<String> = ["economy_disabled", "rate_limited", "profile_required",
                                          "duel_score_pending"]
    /// Terminal rejections: the event can never succeed, drop it and log.
    /// `legacy_review_required` is terminal-with-message: an unreconciled
    /// account must not cause a retry storm (server facts, Agent B).
    static let terminal: Set<String> = ["insufficient_coins", "claim_limit", "item_unavailable",
                                         "invalid_payload", "implausible_result", "invalid_metadata",
                                         "invalid_source", "wrong_day", "invalid_response",
                                         "duel_not_found", "legacy_review_required"]

    /// Player-facing text for interactive failures.
    static func userMessage(for code: String) -> String {
        switch code {
        case "legacy_review_required":
            return "Your coin balance is being reviewed. Rewards resume once the review is finished."
        case "insufficient_coins":
            return "Not enough confirmed coins."
        case "claim_limit", "already_claimed":
            return "This reward was already claimed today."
        default:
            return "The server could not confirm this reward. No coins were changed."
        }
    }
    /// Response statuses that mean the event was accepted.
    static let acceptedStatuses: Set<String> = ["applied", "duplicate", "capped",
                                                 "already_owned", "recorded"]

    static func disposition(for failure: EconomyRemoteFailure) -> EconomyErrorDisposition {
        switch failure {
        case .network:
            return .retry
        case .server(let code):
            if terminalSuccess.contains(code) { return .success }
            if terminal.contains(code) { return .drop }
            // Retryable codes and anything unknown (e.g. an RPC not deployed
            // yet) keep the earned event; `maximumEventAge` bounds the retries.
            return .retry
        }
    }

    /// Event-aware disposition. A `season_tier` refused as `invalid_payload`
    /// (wrong / closed / not-yet-open season) is dropped only once its season
    /// is outside the claim window by the shared calendar rule (current season,
    /// or the previous one until end + `grace_hours`). Inside the window the
    /// refusal can only be clock skew around a boundary, so the earned tier is
    /// kept and retried (`retryNonBlocking`: it never holds up other events).
    static func disposition(for failure: EconomyRemoteFailure, event: EconomyEvent, now: Date,
                            rule: EconomyConfig.SeasonCalendarRule = EconomyConfig.current.seasonCalendar)
        -> EconomyErrorDisposition {
        let base = disposition(for: failure)
        guard base == .drop, event.source == .seasonTier, failure == .server("invalid_payload"),
              case .string(let seasonID)? = event.payload["season_id"],
              SeasonSchedule.isClaimable(seasonID: seasonID, now: now, rule: rule) else { return base }
        return .retryNonBlocking
    }

    /// Exponential backoff: 5 s, 10 s, 20 s … capped at one hour.
    static func backoff(attempts: Int) -> TimeInterval {
        let exponent = min(max(attempts - 1, 0), 10)
        return min(3_600, 5 * pow(2, Double(exponent)))
    }

    /// Events older than this are dropped (the server rejects stale gameplay
    /// after 72 h anyway); prevents an unbounded outbox.
    static let maximumEventAge: TimeInterval = 7 * 24 * 3_600
}

// MARK: - Rewarded-ad server-side verification payload

/// Passed to AdMob's `ServerSideVerificationOptions`. Google forwards it to
/// the `admob-ssv` Edge Function, which grants via `record_verified_rewarded_claim`.
struct RewardedAdVerification: Equatable {
    let userIdentifier: String
    let eventKey: UUID
    let source: String
    let claimIndex: Int
    let referenceEventKey: UUID?

    /// Compact JSON for `customRewardText` (`custom_data` in the SSV callback).
    var customData: String {
        var object: [String: Any] = [
            "event_key": eventKey.uuidString.lowercased(),
            "source": source,
            "claim_index": claimIndex,
        ]
        if let referenceEventKey {
            object["reference_event_key"] = referenceEventKey.uuidString.lowercased()
        }
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]),
              let text = String(data: data, encoding: .utf8) else { return "" }
        return text
    }
}

extension RewardClaimLimiter.Placement {
    /// Contract source for `record_verified_rewarded_claim`.
    var serverSource: String {
        switch self {
        case .homeCoins: return "home_rewarded"
        case .doubleCoins: return "double_coins"
        case .revive: return "revive"
        case .seasonProgress: return "season_progress"
        }
    }
}

// MARK: - Grants (what happened, described once for both rollout paths)

struct GameplayFacts: Equatable {
    var mode: GameMode
    var score: Int
    var maxCombo: Int
    var perfects: Int
    var taps: Int
    var durationMs: Int
    var playedAt: Date
    var sessionID: String
}

enum EconomyGrant: Equatable {
    case gameplay(GameplayFacts)
    case duel(duelID: String)
    case quest(id: String, difficulty: DailyQuest.Difficulty, serverDay: String)
    case achievement(id: String)
    case challenge(id: String)
    case seasonTier(seasonID: String, tier: Int)
    /// Legacy-only entry points (flag ON: server-picked / SSV / StoreKit).
    case legacy(CoinSource)

    /// Outbox source when the authoritative economy is enabled; `nil` means
    /// the grant is never submitted by the client.
    var outboxSource: EconomyEventSource? {
        switch self {
        case .gameplay: return .gameplay
        case .duel: return .duel
        case .quest: return .quest
        case .achievement: return .achievement
        case .challenge: return .challenge
        case .seasonTier: return .seasonTier
        case .legacy: return nil
        }
    }

    var payload: [String: EconomyJSONValue] {
        switch self {
        case .gameplay(let facts):
            return [
                "mode": .string(facts.mode.rawValue),
                "score": .int(facts.score),
                "max_combo": .int(facts.maxCombo),
                "perfects": .int(facts.perfects),
                "taps": .int(facts.taps),
                "duration_ms": .int(max(1, facts.durationMs)),
                "played_at": .string(EconomyDates.iso8601.string(from: facts.playedAt)),
                "session_id": .string(facts.sessionID),
            ]
        case .duel(let duelID):
            return ["duel_id": .string(duelID)]
        case .quest(let id, let difficulty, let serverDay):
            return ["quest_id": .string(id), "difficulty": .string(difficulty.rawValue),
                    "server_day": .string(serverDay)]
        case .achievement(let id):
            return ["achievement_id": .string(id)]
        case .challenge(let id):
            return ["challenge_id": .string(id)]
        case .seasonTier(let seasonID, let tier):
            return ["season_id": .string(seasonID), "tier": .int(tier)]
        case .legacy:
            return [:]
        }
    }
}

enum EconomyDates {
    static let iso8601: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    /// UTC calendar day ("yyyy-MM-dd"), the server's day boundary.
    static func utcDay(_ date: Date = Date()) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 1970, c.month ?? 1, c.day ?? 1)
    }
}
