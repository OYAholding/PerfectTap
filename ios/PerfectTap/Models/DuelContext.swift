import Foundation

// MARK: - DuelContext (single source of truth for an active duel session)
// Replaces scattered perfecttap_duel_id / perfecttap_duel_role UserDefaults keys.
// Persisted as one JSON blob under a single key.

struct DuelContext: Codable {
    let duelId: String
    let role: Role
    let mode: GameMode
    let savedAt: TimeInterval?

    enum Role: String, Codable {
        case host
        case guest
    }

    // MARK: - Persistence

    private static let key = "perfecttap_duel_context"
    private static let maxContextAge: TimeInterval = 2 * 60 * 60 // 2 hours
    private static let pendingLaunchAtKey = "perfecttap_duel_pending_launch_at"
    private static let maxPendingLaunchAge: TimeInterval = 5 * 60 // 5 minutes

    static func save(duelId: String, role: Role, mode: GameMode) {
        let ctx = DuelContext(duelId: duelId, role: role, mode: mode, savedAt: Date().timeIntervalSince1970)
        if let data = try? JSONEncoder().encode(ctx) {
            UserDefaults.standard.set(data, forKey: key)
            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: pendingLaunchAtKey)
        }
    }

    /// One-shot marker proving the next launched game was duel-intended.
    /// This blocks stale context from being picked up by unrelated solo runs.
    static func consumePendingLaunchMarker() -> Bool {
        guard let launchedAt = UserDefaults.standard.object(forKey: pendingLaunchAtKey) as? TimeInterval else {
            return false
        }
        UserDefaults.standard.removeObject(forKey: pendingLaunchAtKey)
        let age = Date().timeIntervalSince1970 - launchedAt
        return age >= 0 && age <= maxPendingLaunchAge
    }

    static func load() -> DuelContext? {
        // Try unified key first
        if let data = UserDefaults.standard.data(forKey: key),
           let ctx = try? JSONDecoder().decode(DuelContext.self, from: data) {
            if let savedAt = ctx.savedAt,
               Date().timeIntervalSince1970 - savedAt > maxContextAge {
                clear()
                return nil
            }
            return ctx
        }
        // One-time migration from legacy scattered keys
        if let duelId = UserDefaults.standard.string(forKey: "perfecttap_duel_id"),
           !duelId.isEmpty,
           let roleStr = UserDefaults.standard.string(forKey: "perfecttap_duel_role"),
           let role = Role(rawValue: roleStr) {
            let ctx = DuelContext(duelId: duelId, role: role, mode: .duel, savedAt: Date().timeIntervalSince1970)
            if let data = try? JSONEncoder().encode(ctx) {
                UserDefaults.standard.set(data, forKey: key)
            }
            // Clean up legacy keys
            UserDefaults.standard.removeObject(forKey: "perfecttap_duel_id")
            UserDefaults.standard.removeObject(forKey: "perfecttap_duel_role")
            return ctx
        }
        return nil
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
        UserDefaults.standard.removeObject(forKey: pendingLaunchAtKey)
        // Also clear legacy keys in case they linger
        UserDefaults.standard.removeObject(forKey: "perfecttap_duel_id")
        UserDefaults.standard.removeObject(forKey: "perfecttap_duel_role")
    }

    static var isValid: Bool {
        load() != nil
    }
}

// MARK: - Duel Invite Auto-Launch Receipts (durable one-shot guard)
// Persists handled invite/duel IDs so reopening screens does not re-trigger launch.
struct DuelInviteLaunchReceiptStore {
    private static let handledInviteIdsKey = "perfecttap_handled_duel_invite_ids"
    private static let handledDuelIdsKey = "perfecttap_handled_duel_ids"
    private static let maxTrackedIds = 200

    static func isHandled(inviteId: String, duelId: String) -> Bool {
        let handledInvites = Set(UserDefaults.standard.stringArray(forKey: handledInviteIdsKey) ?? [])
        let handledDuels = Set(UserDefaults.standard.stringArray(forKey: handledDuelIdsKey) ?? [])
        return handledInvites.contains(inviteId) || handledDuels.contains(duelId)
    }

    static func markHandled(inviteId: String, duelId: String) {
        var inviteIds = UserDefaults.standard.stringArray(forKey: handledInviteIdsKey) ?? []
        var duelIds = UserDefaults.standard.stringArray(forKey: handledDuelIdsKey) ?? []

        if !inviteIds.contains(inviteId) { inviteIds.insert(inviteId, at: 0) }
        if !duelIds.contains(duelId) { duelIds.insert(duelId, at: 0) }

        if inviteIds.count > maxTrackedIds { inviteIds = Array(inviteIds.prefix(maxTrackedIds)) }
        if duelIds.count > maxTrackedIds { duelIds = Array(duelIds.prefix(maxTrackedIds)) }

        UserDefaults.standard.set(inviteIds, forKey: handledInviteIdsKey)
        UserDefaults.standard.set(duelIds, forKey: handledDuelIdsKey)
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: handledInviteIdsKey)
        UserDefaults.standard.removeObject(forKey: handledDuelIdsKey)
    }
}
