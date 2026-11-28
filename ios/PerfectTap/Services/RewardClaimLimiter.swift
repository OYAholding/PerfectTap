import Foundation

/// Device-side fail-closed guard for optional rewarded placements.
///
/// The Supabase ledger remains the launch authority. This guard prevents the
/// existing unlimited local loop while server claims are disabled/offline.
/// With the authoritative economy ON it is only a UX pre-check: the server
/// (`record_verified_rewarded_claim`) enforces the real cap.
/// Callers must pass a day obtained from `authoritativeDayVerification`.
@MainActor
final class RewardClaimLimiter {
    static let shared = RewardClaimLimiter()

    enum Placement: String {
        case homeCoins = "home_coins"
        case doubleCoins = "double_coins"
        case revive = "revive"
        case seasonProgress = "season_progress"

        var dailyLimit: Int {
            switch self {
            case .homeCoins, .doubleCoins, .seasonProgress: return 1
            case .revive: return 3
            }
        }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func remaining(for placement: Placement, day: String, userID: String?) -> Int {
        max(0, placement.dailyLimit - count(for: placement, day: day, userID: userID))
    }

    func canClaim(_ placement: Placement, day: String, userID: String?) -> Bool {
        remaining(for: placement, day: day, userID: userID) > 0
    }

    /// 1-based index of the next claim today (`claim_index` in the SSV payload).
    func nextClaimIndex(for placement: RewardClaimLimiter.Placement, day: String, userID: String?) -> Int {
        min(placement.dailyLimit, count(for: placement, day: day, userID: userID) + 1)
    }

    @discardableResult
    func record(_ placement: Placement, day: String, userID: String?) -> Bool {
        let current = count(for: placement, day: day, userID: userID)
        guard current < placement.dailyLimit else { return false }
        defaults.set(current + 1, forKey: key(for: placement, day: day, userID: userID))
        return true
    }

    private func count(for placement: Placement, day: String, userID: String?) -> Int {
        defaults.integer(forKey: key(for: placement, day: day, userID: userID))
    }

    private func key(for placement: Placement, day: String, userID: String?) -> String {
        let account = (userID?.isEmpty == false ? userID! : "anonymous-device")
        return "perfecttap.reward.\(account).\(placement.rawValue).\(day)"
    }
}
