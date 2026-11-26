import Foundation
import UIKit
import os
import FirebaseAnalytics

// MARK: - EconomyService
//
// Every coin source and sink goes through this one seam.
//
// * Flag OFF (`FeatureFlags.authoritativeEconomyEnabled == false`, shipping):
//   the legacy path — the caller's legacy amount is added to the local
//   profile exactly as before, with no network calls.
// * Flag ON: the client never mutates its balance. Grants become outbox
//   events (server computes the amount); spending/claims are server RPCs;
//   the displayed balance is the server's confirmed balance, with queued
//   events shown separately as "pending".

/// Observable economy state for the UI (confirmed + pending coins).
@MainActor
final class EconomyStatus: ObservableObject {
    @Published fileprivate(set) var pendingCoins: Int = 0
    @Published fileprivate(set) var confirmedBalance: Int? = nil
    @Published fileprivate(set) var legacyStatus: String? = nil
    /// The server answered `economy_disabled` (no active config): events stay
    /// queued, nothing is self-granted, paid coins wait server side
    /// (`pending_iap_coins`). Cleared when the server accepts an event again.
    @Published fileprivate(set) var serverEconomyDisabled: Bool = false
}

enum DailyClaimOutcome: Equatable {
    case claimed(coins: Int)
    case alreadyClaimed
    /// Saved in the outbox; the server applies it when reachable.
    case queued
    case failed(String)
}

enum WheelSpinOutcome: Equatable {
    case landed(segmentIndex: Int, coins: Int)
    case alreadyClaimed
    case queued
    case failed(String)
}

enum EconomyFlushReason: String {
    case gameOver, foreground, signIn, launch, retry, manual
}

@MainActor
protocol EconomyService: AnyObject {
    var isAuthoritative: Bool { get }
    var status: EconomyStatus { get }

    /// Records a coin source. Flag OFF: adds `legacyCoins` to `profile` (and to
    /// `stats.totalCoinsEarned` when `countsTowardTotalEarned`), exactly like
    /// the pre-1.2.0 code. Flag ON: enqueues an outbox event (estimate =
    /// `legacyCoins`) and leaves `profile.coins` untouched. Returns the event key.
    @discardableResult
    func recordGrant(_ grant: EconomyGrant, legacyCoins: Int, countsTowardTotalEarned: Bool,
                     profile: inout PlayerProfile) -> UUID?

    /// Coins the player may spend now (flag ON: confirmed balance only).
    func spendableBalance(profile: PlayerProfile) -> Int

    /// Coin shop purchase. Flag OFF: local deduction. Flag ON: `purchase_economy_item`.
    func purchaseItem(_ item: ShopItem) async -> Bool

    /// Flag ON daily reward (`claim_daily_economy_reward`).
    func claimDailyReward(estimatedCoins: Int) async -> DailyClaimOutcome
    /// Flag ON wheel: the server picks the segment.
    func spinWheel() async -> WheelSpinOutcome
    /// Flag ON starter cosmetic (one Common item from `starter_items`, once).
    func claimStarterItem(_ itemID: String) async -> Bool
    func starterItemChoices(profile: PlayerProfile) -> [ShopItem]

    /// Flag ON only: SSV payload for a rewarded ad; `nil` with flag OFF.
    func rewardedVerification(for placement: RewardClaimLimiter.Placement, claimIndex: Int,
                              referenceEventKey: UUID?) -> RewardedAdVerification?
    /// A rewarded ad finished. Flag OFF: grants `legacyCoins` locally. Flag ON:
    /// grants nothing — shows the estimate as pending and polls the server.
    func rewardedAdCompleted(_ placement: RewardClaimLimiter.Placement, legacyCoins: Int)

    /// StoreKit coin credit / refund debit (`EconomyManager.apply` entry point).
    func applyPurchasedCoins(_ delta: Int)

    func flush(reason: EconomyFlushReason) async
    func scheduleFlush(reason: EconomyFlushReason)
    func refreshConfirmedBalance() async
    /// The signed-in user changed (sign-in, account switch, sign-out).
    func accountDidChange()
}

// MARK: - Remote seam (faked in tests)

@MainActor
protocol EconomyRemote: AnyObject {
    func submit(_ event: EconomyEvent) async -> Result<EconomyRPCResult, EconomyRemoteFailure>
    func purchaseItem(_ itemID: String, eventKey: UUID) async -> Result<EconomyRPCResult, EconomyRemoteFailure>
    func loadState() async -> Result<EconomyStateSnapshot, EconomyRemoteFailure>
    func loadProfile() async -> PlayerProfile?
}

/// Production remote: Supabase RPCs from the contract.
@MainActor
final class SupabaseEconomyRemote: EconomyRemote {
    private var service: SupabaseService? { Backend.shared as? SupabaseService }

    func submit(_ event: EconomyEvent) async -> Result<EconomyRPCResult, EconomyRemoteFailure> {
        guard let service else { return .failure(.network) }
        do {
            let mutation: SupabaseService.EconomyMutation
            if event.source == .dailyReward {
                mutation = try await service.claimDailyEconomyReward(eventID: event.eventKey)
            } else {
                mutation = try await service.submitEconomyEvent(
                    eventKey: event.eventKey, source: event.source.rawValue, payload: event.payload)
            }
            return .success(Self.result(mutation))
        } catch {
            return .failure(service.economyFailure(error))
        }
    }

    func purchaseItem(_ itemID: String, eventKey: UUID) async -> Result<EconomyRPCResult, EconomyRemoteFailure> {
        guard let service else { return .failure(.network) }
        do {
            return .success(Self.result(try await service.purchaseEconomyItem(itemID, eventID: eventKey)))
        } catch {
            return .failure(service.economyFailure(error))
        }
    }

    func loadState() async -> Result<EconomyStateSnapshot, EconomyRemoteFailure> {
        guard let service else { return .failure(.network) }
        do {
            let state = try await service.loadEconomyState()
            return .success(EconomyStateSnapshot(confirmedBalance: state.confirmedBalance,
                                                 coinDebt: state.coinDebt,
                                                 configVersion: state.configVersion,
                                                 legacyStatus: state.legacyStatus))
        } catch {
            return .failure(service.economyFailure(error))
        }
    }

    func loadProfile() async -> PlayerProfile? {
        await service?.loadProfile()
    }

    private static func result(_ m: SupabaseService.EconomyMutation) -> EconomyRPCResult {
        EconomyRPCResult(status: m.status, granted: m.granted, balance: m.balance,
                         coinDebt: m.coinDebt, segmentIndex: m.segmentIndex, itemID: m.itemID)
    }
}

// MARK: - LedgerEconomyService (production implementation)

@MainActor
final class LedgerEconomyService: EconomyService {
    static let shared = LedgerEconomyService()

    let status = EconomyStatus()

    private let authoritative: () -> Bool
    private let currentUserID: () -> String?
    private let remote: EconomyRemote
    private let outboxDirectory: URL
    private let loadProfile: () -> PlayerProfile
    /// Stores a server-derived profile locally (no cloud write-back).
    private let saveProfile: (PlayerProfile) -> Void
    /// Legacy path: local save + cloud sync, exactly like `updateProfile`.
    private let persistLegacy: (PlayerProfile) -> Void
    private let defaults: UserDefaults
    private let now: () -> Date
    /// Delay before each balance poll after a rewarded ad (SSV is asynchronous).
    private let rewardedPollDelays: [TimeInterval]

    private var outboxCache: EconomyOutbox?
    private var isFlushing = false
    private var retryTask: Task<Void, Never>?
    private var flushTask: Task<Void, Never>?
    private var awaitingVerification: [UUID: Int] = [:]
    private var foregroundObserver: NSObjectProtocol?

    private static let log = Logger(subsystem: "com.perfecttap.app", category: "Economy")

    /// Analytics for dropped/unattributed events (contract: "drop + log").
    private static func analytics(_ name: String, _ params: [String: String]) {
        Analytics.logEvent(name, parameters: params)
    }

    init(authoritative: @escaping () -> Bool = { FeatureFlags.authoritativeEconomyEnabled },
         currentUserID: (() -> String?)? = nil,
         remote: EconomyRemote? = nil,
         outboxDirectory: URL = EconomyOutbox.defaultDirectory,
         loadProfile: @escaping () -> PlayerProfile = { PlayerProfile.load() ?? PlayerProfile() },
         saveProfile: @escaping (PlayerProfile) -> Void = { $0.save() },
         persistLegacy: ((PlayerProfile) -> Void)? = nil,
         defaults: UserDefaults = .standard,
         now: @escaping () -> Date = Date.init,
         rewardedPollDelays: [TimeInterval] = [2, 6, 15],
         observeForeground: Bool = true) {
        self.authoritative = authoritative
        // Defaults resolved here: they touch main-actor singletons.
        self.currentUserID = currentUserID ?? { Backend.shared.currentUID }
        self.remote = remote ?? SupabaseEconomyRemote()
        self.outboxDirectory = outboxDirectory
        self.loadProfile = loadProfile
        self.saveProfile = saveProfile
        self.persistLegacy = persistLegacy ?? { EconomyManager.shared.persistProfile($0) }
        self.defaults = defaults
        self.now = now
        self.rewardedPollDelays = rewardedPollDelays
        if observeForeground {
            foregroundObserver = NotificationCenter.default.addObserver(
                forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main
            ) { [weak self] _ in
                Task { @MainActor in self?.scheduleFlush(reason: .foreground) }
            }
        }
    }

    var isAuthoritative: Bool { authoritative() }

    /// Estimates for "pending" coins use the candidate config while ON.
    private var estimateConfig: EconomyConfig { isAuthoritative ? .balancedPremiumRC1 : .legacy }

    // MARK: Outbox access (bound to the signed-in user)

    /// The outbox of the user signed in *now*; nil without a user.
    func currentOutbox() -> EconomyOutbox? {
        guard let uid = currentUserID()?.lowercased(), !uid.isEmpty else { return nil }
        if let cached = outboxCache, cached.userID == uid { return cached }
        let outbox = EconomyOutbox(userID: uid, directory: outboxDirectory)
        outboxCache = outbox
        return outbox
    }

    private func refreshPending() {
        let queued = isAuthoritative ? (currentOutbox()?.pendingCoins ?? 0) : 0
        let awaiting = awaitingVerification.values.reduce(0, +)
        let total = queued + awaiting
        if status.pendingCoins != total { status.pendingCoins = total }
    }

    // MARK: Grants

    @discardableResult
    func recordGrant(_ grant: EconomyGrant, legacyCoins: Int, countsTowardTotalEarned: Bool,
                     profile: inout PlayerProfile) -> UUID? {
        guard isAuthoritative else {
            // Legacy path, byte-for-byte the pre-1.2.0 arithmetic.
            guard legacyCoins > 0 else { return nil }
            profile.coins += legacyCoins
            if countsTowardTotalEarned { profile.stats.totalCoinsEarned += legacyCoins }
            return nil
        }
        // Earned-coins statistic stays a local stat; the balance does not move.
        if countsTowardTotalEarned, legacyCoins > 0 { profile.stats.totalCoinsEarned += legacyCoins }
        guard let source = grant.outboxSource else { return nil }
        guard let outbox = currentOutbox() else {
            Self.log.error("economy event without signed-in user dropped: \(source.rawValue, privacy: .public)")
            Self.analytics("economy_event_unattributed", ["source": source.rawValue])
            return nil
        }
        let event = EconomyEvent(eventKey: UUID(), source: source, payload: grant.payload,
                                 createdAt: now(), estimatedCoins: max(0, legacyCoins))
        outbox.enqueue(event)
        refreshPending()
        return event.eventKey
    }

    func spendableBalance(profile: PlayerProfile) -> Int {
        guard isAuthoritative else { return profile.coins }
        return status.confirmedBalance ?? profile.coins
    }

    // MARK: Shop

    func purchaseItem(_ item: ShopItem) async -> Bool {
        guard !item.isFree, !item.isPremium else { return false }
        guard isAuthoritative else { return legacyBuy(item) }
        guard let uid = currentUserID() else { return false }
        let profile = loadProfile()
        guard !EconomyManager.isOwned(item.id, in: profile) else { return true }
        guard spendableBalance(profile: profile) >= item.price else { return false }
        switch await remote.purchaseItem(item.id, eventKey: UUID()) {
        case .success(let result):
            guard EconomyErrorPolicy.acceptedStatuses.contains(result.status) else { return false }
            applyServerResult(result, forUser: uid, grantedItem: item.id)
            return true
        case .failure(let failure):
            if case .server(let code) = failure, code == "already_owned" {
                applyServerResult(EconomyRPCResult(status: code), forUser: uid, grantedItem: item.id)
                return true
            }
            logDrop(source: "shop_purchase", failure: failure)
            return false
        }
    }

    private func legacyBuy(_ item: ShopItem) -> Bool {
        var profile = loadProfile()
        guard !EconomyManager.isOwned(item.id, in: profile), profile.coins >= item.price else { return false }
        profile.coins -= item.price
        if !profile.ownedItems.contains(item.id) { profile.ownedItems.append(item.id) }
        persistLegacy(profile)
        return true
    }

    // MARK: Interactive claims (outbox first, then sent immediately)

    func claimDailyReward(estimatedCoins: Int) async -> DailyClaimOutcome {
        guard isAuthoritative, let outbox = currentOutbox() else { return .failed("economy_unavailable") }
        let event = EconomyEvent(eventKey: UUID(), source: .dailyReward, payload: [:],
                                 createdAt: now(), estimatedCoins: estimatedCoins)
        outbox.enqueue(event)
        refreshPending()
        switch await deliverNow(event, outbox: outbox) {
        case .accepted(let result):
            if let serverProfile = await remote.loadProfile(), currentUserID()?.lowercased() == outbox.userID {
                var merged = serverProfile
                if let balance = result.balance { merged.coins = balance }
                saveProfile(merged)
            }
            return .claimed(coins: result.granted ?? estimatedCoins)
        case .alreadyHeld: return .alreadyClaimed
        case .queued: return .queued
        case .dropped(let code): return .failed(code)
        }
    }

    func spinWheel() async -> WheelSpinOutcome {
        guard isAuthoritative, let outbox = currentOutbox() else { return .failed("economy_unavailable") }
        let event = EconomyEvent(eventKey: UUID(), source: .wheel, payload: [:], createdAt: now())
        outbox.enqueue(event)
        switch await deliverNow(event, outbox: outbox) {
        case .accepted(let result):
            guard let index = result.segmentIndex else {
                return result.status == "duplicate" ? .alreadyClaimed : .failed("invalid_response")
            }
            return .landed(segmentIndex: index, coins: result.granted ?? 0)
        case .alreadyHeld: return .alreadyClaimed
        case .queued: return .queued
        case .dropped(let code): return .failed(code)
        }
    }

    func claimStarterItem(_ itemID: String) async -> Bool {
        guard isAuthoritative, let uid = currentUserID(),
              starterItemChoices(profile: loadProfile()).contains(where: { $0.id == itemID }) else { return false }
        let event = EconomyEvent(eventKey: UUID(), source: .starterItem,
                                 payload: ["item_id": .string(itemID)], createdAt: now())
        switch await remote.submit(event) {
        case .success(let result) where EconomyErrorPolicy.acceptedStatuses.contains(result.status):
            applyServerResult(result, forUser: uid, grantedItem: result.itemID ?? itemID)
            markStarterClaimed(uid)
            return true
        case .success:
            return false
        case .failure(let failure):
            if EconomyErrorPolicy.disposition(for: failure) == .success {
                // Already claimed on this account: never offer the choice again.
                markStarterClaimed(uid)
            }
            logDrop(source: "starter_item", failure: failure)
            return false
        }
    }

    func starterItemChoices(profile: PlayerProfile) -> [ShopItem] {
        guard isAuthoritative, let uid = currentUserID(), !starterClaimed(uid) else { return [] }
        // Existing owners keep everything and are not offered a starter.
        let ownsCoinItem = profile.ownedItems.contains { id in
            guard let item = ShopItem.item(id: id) else { return false }
            return !item.isFree && !item.isPremium
        }
        guard !ownsCoinItem else { return [] }
        return estimateConfig.starterItems.compactMap(ShopItem.item(id:)).filter { $0.rarity == .common }
    }

    private func starterKey(_ uid: String) -> String { "perfecttap.economy.starterClaimed.\(uid.lowercased())" }
    private func starterClaimed(_ uid: String) -> Bool { defaults.bool(forKey: starterKey(uid)) }
    private func markStarterClaimed(_ uid: String) { defaults.set(true, forKey: starterKey(uid)) }

    // MARK: Rewarded ads

    func rewardedVerification(for placement: RewardClaimLimiter.Placement, claimIndex: Int,
                              referenceEventKey: UUID?) -> RewardedAdVerification? {
        guard isAuthoritative, let uid = currentUserID(), !uid.isEmpty else { return nil }
        return RewardedAdVerification(userIdentifier: uid, eventKey: UUID(), source: placement.serverSource,
                                      claimIndex: max(1, claimIndex), referenceEventKey: referenceEventKey)
    }

    func rewardedAdCompleted(_ placement: RewardClaimLimiter.Placement, legacyCoins: Int) {
        guard isAuthoritative else {
            guard legacyCoins > 0 else { return }
            let source: CoinSource = placement == .doubleCoins ? .gameplay : .rewardedAd
            var profile = loadProfile()
            recordGrant(.legacy(source), legacyCoins: legacyCoins, countsTowardTotalEarned: true, profile: &profile)
            persistLegacy(profile)
            return
        }
        // Never self-grant: the SSV callback credits the ledger. Show the
        // estimate as pending until a refreshed balance confirms it.
        let token = UUID()
        if legacyCoins > 0 { awaitingVerification[token] = legacyCoins }
        refreshPending()
        pollAfterReward(token: token)
    }

    private func pollAfterReward(token: UUID) {
        let delays = rewardedPollDelays
        Task { [weak self] in
            var baseline = self?.status.confirmedBalance
            for delay in delays {
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                guard let self else { return }
                await self.refreshConfirmedBalance()
                if let balance = self.status.confirmedBalance, let before = baseline, balance > before { break }
                if baseline == nil { baseline = self.status.confirmedBalance }
            }
            self?.awaitingVerification[token] = nil
            self?.refreshPending()
        }
    }

    // MARK: StoreKit

    func applyPurchasedCoins(_ delta: Int) {
        guard delta != 0 else { return }
        guard isAuthoritative else {
            var profile = loadProfile()
            if delta > 0 {
                recordGrant(.legacy(.purchase), legacyCoins: delta, countsTowardTotalEarned: true, profile: &profile)
            } else {
                profile.coins = max(0, profile.coins + delta)
            }
            persistLegacy(profile)
            return
        }
        // `record_verified_purchase` / `revoke_purchase` move the ledger
        // server side (or hold the coins as `pending_iap_coins` while no
        // config is active). Never credit locally — that would double credit.
        // Show a purchase as pending until the confirmed balance catches up.
        let token = UUID()
        if delta > 0 { awaitingVerification[token] = delta }
        refreshPending()
        pollAfterReward(token: token)
    }

    // MARK: Delivery

    private enum Delivery {
        case accepted(EconomyRPCResult)
        case alreadyHeld
        /// Kept in the outbox. `blocking`: stop the flush (offline / refused);
        /// otherwise later events are still sent.
        case queued(blocking: Bool = true)
        case dropped(String)
    }

    /// Sends one queued event now and settles it in the outbox.
    private func deliverNow(_ event: EconomyEvent, outbox: EconomyOutbox) async -> Delivery {
        guard currentUserID()?.lowercased() == outbox.userID else { return .queued() }
        let outcome = await remote.submit(event)
        // The user may have switched while the request was in flight: the
        // result belongs to the outbox's user, never to the new one.
        let stillSameUser = currentUserID()?.lowercased() == outbox.userID
        switch outcome {
        case .success(let result) where EconomyErrorPolicy.acceptedStatuses.contains(result.status):
            outbox.remove(event.eventKey)
            if stillSameUser { status.serverEconomyDisabled = false }
            if stillSameUser { applyServerResult(result, forUser: outbox.userID, grantedItem: result.itemID) }
            refreshPending()
            // Duplicates return the original granted/segmentIndex/itemID.
            return .accepted(result)
        case .success(let result):
            outbox.remove(event.eventKey)
            refreshPending()
            logDrop(source: event.source.rawValue, failure: .server(result.status))
            return .dropped(result.status)
        case .failure(let failure):
            if failure == .server("economy_disabled"), stillSameUser { status.serverEconomyDisabled = true }
            let disposition = EconomyErrorPolicy.disposition(for: failure, event: event, now: now())
            switch disposition {
            case .success:
                outbox.remove(event.eventKey)
                refreshPending()
                return .alreadyHeld
            case .retry, .retryNonBlocking:
                var retried = event
                retried.attempts += 1
                retried.nextAttemptAt = now().addingTimeInterval(EconomyErrorPolicy.backoff(attempts: retried.attempts))
                outbox.update(retried)
                return .queued(blocking: disposition == .retry)
            case .drop:
                outbox.remove(event.eventKey)
                refreshPending()
                logDrop(source: event.source.rawValue, failure: failure)
                if case .server(let code) = failure { return .dropped(code) }
                return .dropped("unknown")
            }
        }
    }

    private func applyServerResult(_ result: EconomyRPCResult, forUser uid: String, grantedItem: String?) {
        guard currentUserID()?.lowercased() == uid.lowercased() else { return }
        if let balance = result.balance { status.confirmedBalance = balance }
        let item = grantedItem.flatMap { $0.isEmpty ? nil : $0 }
        guard result.balance != nil || item != nil else { return }
        var profile = loadProfile()
        if let balance = result.balance { profile.coins = balance }
        if let item, !profile.ownedItems.contains(item) { profile.ownedItems.append(item) }
        saveProfile(profile)
    }

    private func logDrop(source: String, failure: EconomyRemoteFailure) {
        let code: String
        switch failure {
        case .network: code = "network"
        case .server(let value): code = value
        }
        Self.log.error("economy event rejected source=\(source, privacy: .public) code=\(code, privacy: .public)")
        Self.analytics("economy_event_rejected", ["source": source, "code": code])
    }

    // MARK: Flush

    func scheduleFlush(reason: EconomyFlushReason) {
        guard isAuthoritative else { return }
        flushTask?.cancel()
        flushTask = Task { [weak self] in
            // Leave the frame that triggered us (game over transition) alone.
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            await self?.flush(reason: reason)
        }
    }

    func flush(reason: EconomyFlushReason) async {
        guard isAuthoritative, !isFlushing, let outbox = currentOutbox() else { return }
        isFlushing = true
        defer { isFlushing = false }

        var hitNetworkFailure = false
        let snapshot = outbox.events
        for event in snapshot {
            if Task.isCancelled { break }
            // Never send one account's events under another account.
            guard currentUserID()?.lowercased() == outbox.userID else { break }
            if now().timeIntervalSince(event.createdAt) > EconomyErrorPolicy.maximumEventAge {
                outbox.remove(event.eventKey)
                logDrop(source: event.source.rawValue, failure: .server("expired_client_event"))
                continue
            }
            if let next = event.nextAttemptAt, next > now(), reason != .manual { continue }
            if case .queued(let blocking) = await deliverNow(event, outbox: outbox), blocking {
                hitNetworkFailure = true
                break   // offline or temporarily refused: keep order, back off
            }
        }
        refreshPending()
        if hitNetworkFailure || !outbox.isEmpty {
            scheduleRetry(outbox: outbox)
        }
        await refreshConfirmedBalance()
    }

    private func scheduleRetry(outbox: EconomyOutbox) {
        retryTask?.cancel()
        let soonest = outbox.events.compactMap(\.nextAttemptAt).min() ?? now().addingTimeInterval(5)
        let delay = max(1, soonest.timeIntervalSince(now()))
        retryTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await self?.flush(reason: .retry)
        }
    }

    func refreshConfirmedBalance() async {
        guard isAuthoritative, let uid = currentUserID()?.lowercased() else { return }
        guard case .success(let state) = await remote.loadState() else { return }
        guard currentUserID()?.lowercased() == uid else { return }
        status.legacyStatus = state.legacyStatus
        // No active config: the ledger mirror is not authoritative yet (paid
        // coins sit in pending_iap_coins). Keep the legacy-safe local balance.
        guard !status.serverEconomyDisabled else { return }
        status.confirmedBalance = state.confirmedBalance
        var profile = loadProfile()
        if profile.coins != state.confirmedBalance {
            profile.coins = state.confirmedBalance
            saveProfile(profile)
        }
    }

    /// Cancels scheduled flush/retry/poll work (tests, teardown).
    func cancelPendingWork() {
        retryTask?.cancel()
        flushTask?.cancel()
        retryTask = nil
        flushTask = nil
    }

    func accountDidChange() {
        retryTask?.cancel()
        flushTask?.cancel()
        awaitingVerification.removeAll()
        outboxCache = nil
        status.confirmedBalance = nil
        status.legacyStatus = nil
        refreshPending()
        scheduleFlush(reason: .signIn)
    }
}
