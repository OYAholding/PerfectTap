import Foundation
import GoogleMobileAds

// MARK: - Debug-only logging helper
// Compiles to nothing in Release builds — no console output, no string interpolation overhead.
@inline(__always)
private func adLog(_ message: @autoclosure () -> String) {
    #if DEBUG
    print("[AdManager] \(message())")
    #endif
}

@inline(__always)
private func adErrorDetails(_ error: Error) -> String {
    let nsError = error as NSError
    return "localized=\"\(error.localizedDescription)\", domain=\(nsError.domain), code=\(nsError.code), userInfo=\(nsError.userInfo)"
}

// MARK: - Ad Placement Types
enum AdPlacement: String {
    case reviveReward       = "revive_reward"
    case doubleCoins        = "double_coins"
    case freeSpinReward     = "free_spin_reward"
    case seasonPassUnlock   = "season_pass_unlock"
    case interstitialPost   = "interstitial_post"
}

// MARK: - Ad Unit IDs
// Automatically uses test ads in DEBUG builds, production ads in RELEASE.
// No manual switching needed — just build for App Store and it works.
private enum AdConfig {
    // Automatic: DEBUG = test ads, RELEASE = real ads
    static var useTestAds: Bool {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }

    // Production IDs (your AdMob console)
    static let productionRewardedID    = "ca-app-pub-5350899688701342/3893434236"
    static let productionInterstitialID = "ca-app-pub-5350899688701342/6398701661"

    // Google's official test ad unit IDs (always work, never serve real ads)
    static let testRewardedID          = "ca-app-pub-3940256099942544/1712485313"
    static let testInterstitialID      = "ca-app-pub-3940256099942544/4411468910"

    static var rewardedAdUnitID: String {
        useTestAds ? testRewardedID : productionRewardedID
    }

    static var interstitialAdUnitID: String {
        useTestAds ? testInterstitialID : productionInterstitialID
    }

    /// Whether interstitial ads are configured for the current build.
    static var isInterstitialConfigured: Bool {
        !interstitialAdUnitID.isEmpty
    }
}

private enum InterstitialPacingConfig {
    static let runThresholdRange = 3...4
    static let cooldownRangeSeconds = 90.0...120.0
    static let rewardedSuppressionSeconds = 120.0
}

private enum AdPacingKeys {
    static let hasLaunchedBefore = "perfecttap_ads_has_launched_before"
    static let runsSinceLastInterstitial = "perfecttap_ads_runs_since_last_interstitial"
    static let runThreshold = "perfecttap_ads_interstitial_run_threshold"
    static let cooldownSeconds = "perfecttap_ads_interstitial_cooldown_seconds"
    static let lastInterstitialTimestamp = "perfecttap_ads_last_interstitial_timestamp"
    static let lastRewardedCompletionTimestamp = "perfecttap_ads_last_rewarded_completion_timestamp"
    static let debugForcePostGameInterstitial = "perfecttap_ads_debug_force_post_game_interstitial"
}

// MARK: - AdManager
// Manages Google AdMob rewarded and interstitial ads.
// - Preloads ads so they're ready when needed.
// - Presents rewarded ads via async/await returning a Bool.
// - Revive logic is controlled by game state (GameViewModel.hasUsedReviveRef),
//   NOT by AdMob frequency capping.

@MainActor
final class AdManager: ObservableObject {

    static let shared = AdManager()

    // MARK: - Published State
    @Published private(set) var isRewardedAdReady: Bool = false
    @Published private(set) var isInterstitialReady: Bool = false
    @Published private(set) var isLoadingAd: Bool = false

    // Cached ad objects
    private var rewardedAd: RewardedAd?
    private var interstitialAd: InterstitialAd?
    private var _adDismissDelegate: AdDismissDelegate?
    private let defaults = UserDefaults.standard
    private let isFirstLaunchSession: Bool

    /// Whether the user purchased the no-ads IAP
    var noAdsPurchased: Bool {
        (PlayerProfile.load() ?? PlayerProfile()).noAds
    }

    private var runsSinceLastInterstitialCounter: Int {
        defaults.integer(forKey: AdPacingKeys.runsSinceLastInterstitial)
    }

    private var debugForcePostGameInterstitialAttempt: Bool {
        #if DEBUG
        defaults.bool(forKey: AdPacingKeys.debugForcePostGameInterstitial)
            || ProcessInfo.processInfo.environment["PT_FORCE_POSTGAME_INTERSTITIAL"] == "1"
        #else
        false
        #endif
    }

    private init() {
        let hasLaunchedBefore = defaults.bool(forKey: AdPacingKeys.hasLaunchedBefore)
        self.isFirstLaunchSession = !hasLaunchedBefore
        if !hasLaunchedBefore {
            defaults.set(true, forKey: AdPacingKeys.hasLaunchedBefore)
        }
        if defaults.object(forKey: AdPacingKeys.runThreshold) == nil {
            defaults.set(Int.random(in: InterstitialPacingConfig.runThresholdRange), forKey: AdPacingKeys.runThreshold)
        }
        if defaults.object(forKey: AdPacingKeys.cooldownSeconds) == nil {
            defaults.set(Double.random(in: InterstitialPacingConfig.cooldownRangeSeconds), forKey: AdPacingKeys.cooldownSeconds)
        }
        adLog(
            """
            init complete: isFirstLaunchSession=\(isFirstLaunchSession), useTestAds=\(AdConfig.useTestAds), \
            interstitialConfigured=\(AdConfig.isInterstitialConfigured), interstitialAdUnitID=\(AdConfig.interstitialAdUnitID), \
            runsSinceLastInterstitial=\(runsSinceLastInterstitialCounter), runThreshold=\(interstitialRunThreshold), cooldownSeconds=\(String(format: "%.1f", interstitialCooldownSeconds)), \
            debugForcePostGameInterstitial=\(debugForcePostGameInterstitialAttempt)
            """
        )
    }

    // MARK: - SDK Initialization (driven by ConsentManager)
    private var sdkStarted = false

    /// Called by ConsentManager after Google UMP + Apple ATT. The SDK is never started and
    /// no ad is requested before this. Personalized (IDFA) ads only with ATT `.authorized`.
    func applyPrivacy(_ decision: AdPrivacyDecision) {
        MobileAds.shared.requestConfiguration.publisherPrivacyPersonalizationState =
            decision.personalizedAds ? .default : .disabled
        adLog("applyPrivacy: canRequestAds=\(decision.canRequestAds) personalized=\(decision.personalizedAds)")
        guard decision.canRequestAds, !sdkStarted else { return }
        sdkStarted = true
        initializeSDK()
    }

    private func initializeSDK() {
        adLog(
            """
            initializeSDK: useTestAds=\(AdConfig.useTestAds), interstitialAdUnitID=\(AdConfig.interstitialAdUnitID), \
            rewardedAdUnitID=\(AdConfig.rewardedAdUnitID), interstitialConfigured=\(AdConfig.isInterstitialConfigured), noAdsPurchased=\(noAdsPurchased)
            """
        )
        MobileAds.shared.start { [weak self] status in
            adLog("SDK initialized. Adapter statuses: \(status.adapterStatusesByClassName)")
            Task { @MainActor in
                self?.preloadAds()
            }
        }
    }

    // MARK: - Preload Ads
    /// Preload both rewarded and interstitial ads so they're ready instantly.
    func preloadAds() {
        guard sdkStarted else { return }
        guard !noAdsPurchased else {
            adLog("preloadAds skipped: noAdsPurchased=true")
            return
        }
        adLog(
            """
            preloadAds start: interstitialConfigured=\(AdConfig.isInterstitialConfigured), useTestAds=\(AdConfig.useTestAds), \
            interstitialAdUnitID=\(AdConfig.interstitialAdUnitID), currentInterstitialReady=\(isInterstitialReady)
            """
        )
        loadRewardedAd()
        if AdConfig.isInterstitialConfigured {
            loadInterstitialAd(reason: "preload_ads_startup")
        } else {
            adLog("preloadAds: interstitial not configured")
        }
    }

    private func loadRewardedAd() {
        guard sdkStarted else { return } // consent flow has not allowed ads yet
        guard !isLoadingAd else {
            adLog("loadRewardedAd skipped: isLoadingAd=true")
            return
        }

        let adUnitID = AdConfig.rewardedAdUnitID
        guard !adUnitID.isEmpty else {
            adLog("loadRewardedAd skipped: rewardedAdUnitID empty")
            return
        }
        adLog("Requesting rewarded ad: adUnitID=\(adUnitID), useTestAds=\(AdConfig.useTestAds)")

        RewardedAd.load(with: adUnitID, request: Request()) { [weak self] ad, error in
            Task { @MainActor in
                guard let self else { return }
                if let error {
                    adLog("Failed to load rewarded ad: \(adErrorDetails(error))")
                    self.rewardedAd = nil
                    self.isRewardedAdReady = false
                } else {
                    adLog("Rewarded ad loaded successfully")
                    self.rewardedAd = ad
                    self.isRewardedAdReady = true
                }
            }
        }
    }

    private func loadInterstitialAd(reason: String) {
        guard sdkStarted else { return } // consent flow has not allowed ads yet
        let adUnitID = AdConfig.interstitialAdUnitID
        guard !adUnitID.isEmpty else {
            adLog("Interstitial load skipped (\(reason)): ad unit ID empty / not configured")
            return
        }
        adLog(
            """
            Requesting interstitial (\(reason)): adUnitID=\(adUnitID), useTestAds=\(AdConfig.useTestAds), \
            interstitialConfigured=\(AdConfig.isInterstitialConfigured), isInterstitialReady(before)=\(isInterstitialReady)
            """
        )

        InterstitialAd.load(with: adUnitID, request: Request()) { [weak self] ad, error in
            Task { @MainActor in
                guard let self else { return }
                if let error {
                    adLog("Failed to load interstitial (\(reason)): \(adErrorDetails(error))")
                    self.interstitialAd = nil
                    self.isInterstitialReady = false
                } else {
                    let responseID = ad?.responseInfo.responseIdentifier ?? "nil"
                    adLog("Interstitial loaded successfully (\(reason)). responseIdentifier=\(responseID)")
                    self.interstitialAd = ad
                    self.isInterstitialReady = true
                }
            }
        }
    }

    // MARK: - Show Rewarded Ad
    /// Shows a rewarded ad and returns `true` if the user earned the reward
    /// (watched to completion). Returns `false` if the ad couldn't be shown
    /// or was dismissed early.
    ///
    /// Usage:
    /// ```swift
    /// let success = await AdManager.shared.showRewardedAd(placement: .reviveReward)
    /// if success { gameVM.acceptRevive() }
    /// ```
    func showRewardedAd(placement: AdPlacement) async -> Bool {
        if Self.uiTestAdsDisabled { return false }
        // No-ads users get the reward for free
        guard !noAdsPurchased else {
            adLog("showRewardedAd shortcut: noAdsPurchased=true placement=\(placement.rawValue)")
            return true
        }

        guard let rewardedAd, isRewardedAdReady else {
            adLog("Rewarded ad not ready for placement: \(placement.rawValue)")
            return false
        }

        guard let rootVC = getRootViewController() else {
            adLog("showRewardedAd blocked: root view controller unavailable placement=\(placement.rawValue)")
            return false
        }
        adLog("Presenting rewarded ad for placement=\(placement.rawValue) fromVC=\(String(describing: type(of: rootVC)))")

        // Use a continuation to bridge the callback-based API to async/await.
        // The reward callback fires ONLY if the user watches to completion.
        // We also set a fullScreenContentDelegate to detect dismissal without reward.
        let didEarnReward: Bool = await withCheckedContinuation { continuation in
            var hasResumed = false

            // Set delegate to detect ad dismissal (catches early-close / no reward)
            var earnedReward = false
            // Resume only when the ad is gone, so gameplay never restarts behind it.
            let delegate = AdDismissDelegate(label: "rewarded:\(placement.rawValue)") {
                if !hasResumed {
                    hasResumed = true
                    adLog("Ad dismissed for placement: \(placement.rawValue) earned=\(earnedReward)")
                    continuation.resume(returning: earnedReward)
                }
            } onFail: { error in
                if !hasResumed {
                    hasResumed = true
                    adLog("Rewarded ad failed to present for placement=\(placement.rawValue): \(adErrorDetails(error))")
                    continuation.resume(returning: false)
                }
            }
            rewardedAd.fullScreenContentDelegate = delegate
            // Keep delegate alive until ad is dismissed
            self._adDismissDelegate = delegate

            rewardedAd.present(from: rootVC) {
                // Fires when the reward is earned; the ad may still be on screen.
                // Remember it and resume on dismissal (delegate above).
                guard !earnedReward else { return }
                earnedReward = true
                self.recordRewardedCompletion()
                adLog("User earned reward for placement: \(placement.rawValue)")
            }
        }

        // Ad was consumed — clear it and preload the next one
        self.rewardedAd = nil
        self.isRewardedAdReady = false
        loadRewardedAd()

        return didEarnReward
    }

    // MARK: - Show Interstitial Ad
    /// Shows an interstitial ad and waits for dismiss/fail.
    /// DEBUG-only: UI tests launch with `-PTUITestNoAds` because XCUITest cannot
    /// watch or close a real full-screen ad (the run would stall behind it).
    /// Ads then behave as "no inventory" (revive fails open). Never active in Release.
    static var uiTestAdsDisabled: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("-PTUITestNoAds")
        #else
        return false
        #endif
    }

    /// Shows an interstitial ad and waits for dismiss/fail.
    /// Returns true only if it was presented and dismissed normally.
    @discardableResult
    func showInterstitialAd(placement: AdPlacement) async -> Bool {
        if Self.uiTestAdsDisabled { return false }
        guard !noAdsPurchased else {
            adLog("showInterstitialAd blocked: noAdsPurchased=true placement=\(placement.rawValue)")
            return false
        }
        guard let interstitialAd, isInterstitialReady else {
            adLog(
                """
                showInterstitialAd blocked: not ready placement=\(placement.rawValue), \
                isInterstitialReady=\(isInterstitialReady), hasAdObject=\(self.interstitialAd != nil)
                """
            )
            return false
        }

        guard let rootVC = getRootViewController() else {
            adLog("showInterstitialAd blocked: root view controller unavailable placement=\(placement.rawValue)")
            return false
        }
        adLog("Presenting interstitial placement=\(placement.rawValue) fromVC=\(String(describing: type(of: rootVC)))")

        let didShow: Bool = await withCheckedContinuation { continuation in
            var hasResumed = false

            let delegate = AdDismissDelegate(
                label: "interstitial:\(placement.rawValue)",
                onDismiss: {
                    if !hasResumed {
                        hasResumed = true
                        adLog("Interstitial dismissed placement=\(placement.rawValue)")
                        continuation.resume(returning: true)
                    }
                },
                onFail: { error in
                    if !hasResumed {
                        hasResumed = true
                        adLog("Interstitial failed to present placement=\(placement.rawValue): \(adErrorDetails(error))")
                        continuation.resume(returning: false)
                    }
                }
            )
            interstitialAd.fullScreenContentDelegate = delegate
            self._adDismissDelegate = delegate
            interstitialAd.present(from: rootVC)
        }

        // Ad object consumed — clear and preload
        self.interstitialAd = nil
        self.isInterstitialReady = false
        if AdConfig.isInterstitialConfigured {
            loadInterstitialAd(reason: "post_interstitial_consumed")
        }
        adLog("showInterstitialAd completed placement=\(placement.rawValue) didShow=\(didShow)")
        return didShow
    }

    @discardableResult
    func maybeShowPostGameInterstitial(isDuelSession: Bool) async -> Bool {
        let forceAttempt = debugForcePostGameInterstitialAttempt
        let preRuns = runsSinceLastInterstitialCounter
        let threshold = interstitialRunThreshold
        let cooldownSeconds = interstitialCooldownSeconds
        let now = Date()
        let timeSinceLastInterstitial = lastInterstitialShownAt.map { now.timeIntervalSince($0) }
        let timeSinceLastRewarded = lastRewardedCompletionAt.map { now.timeIntervalSince($0) }

        adLog(
            """
            maybeShowPostGameInterstitial called: isDuelSession=\(isDuelSession), isInterstitialReady=\(isInterstitialReady), \
            noAdsPurchased=\(noAdsPurchased), isFirstLaunchSession=\(isFirstLaunchSession), interstitialConfigured=\(AdConfig.isInterstitialConfigured), \
            runsSinceLastInterstitial=\(preRuns), runThreshold=\(threshold), cooldownSeconds=\(String(format: "%.1f", cooldownSeconds)), \
            timeSinceLastInterstitial=\(formatIntervalForLog(timeSinceLastInterstitial)), \
            timeSinceLastRewardedCompletion=\(formatIntervalForLog(timeSinceLastRewarded)), debugForceAttempt=\(forceAttempt)
            """
        )

        guard !noAdsPurchased else {
            adLog("Interstitial blocked: noAdsPurchased=true")
            return false
        }
        guard AdConfig.isInterstitialConfigured else {
            adLog(
                """
                Interstitial blocked: AdConfig.isInterstitialConfigured=false useTestAds=\(AdConfig.useTestAds) \
                interstitialAdUnitID=\(AdConfig.interstitialAdUnitID)
                """
            )
            return false
        }
        if isDuelSession && !forceAttempt {
            adLog("Interstitial blocked: duel session suppression active")
            return false
        }
        if isDuelSession && forceAttempt {
            adLog("Debug override bypass: duel session suppression")
        }

        let runs = incrementCompletedRuns()
        adLog("Post-game run recorded: runsSinceLastInterstitial=\(runs)")

        if isFirstLaunchSession && !forceAttempt {
            adLog("Skipping interstitial: first launch session")
            return false
        }
        if isFirstLaunchSession && forceAttempt {
            adLog("Debug override bypass: first-launch session suppression")
        }

        if runs < threshold && !forceAttempt {
            adLog("Interstitial blocked: run threshold not reached (\(runs)/\(threshold))")
            return false
        }
        if runs < threshold && forceAttempt {
            adLog("Debug override bypass: run threshold (\(runs)/\(threshold))")
        }

        if let lastRewardedAt = lastRewardedCompletionAt,
           Date().timeIntervalSince(lastRewardedAt) < InterstitialPacingConfig.rewardedSuppressionSeconds,
           !forceAttempt {
            adLog(
                """
                Interstitial blocked: rewarded suppression window active \
                (\(String(format: "%.1f", Date().timeIntervalSince(lastRewardedAt)))s < \(InterstitialPacingConfig.rewardedSuppressionSeconds)s)
                """
            )
            return false
        }
        if let lastRewardedAt = lastRewardedCompletionAt,
           Date().timeIntervalSince(lastRewardedAt) < InterstitialPacingConfig.rewardedSuppressionSeconds,
           forceAttempt {
            adLog("Debug override bypass: rewarded suppression window")
        }

        if let lastShownAt = lastInterstitialShownAt,
           Date().timeIntervalSince(lastShownAt) < cooldownSeconds,
           !forceAttempt {
            adLog(
                """
                Interstitial blocked: cooldown active \
                (\(String(format: "%.1f", Date().timeIntervalSince(lastShownAt)))s < \(String(format: "%.1f", cooldownSeconds))s)
                """
            )
            return false
        }
        if let lastShownAt = lastInterstitialShownAt,
           Date().timeIntervalSince(lastShownAt) < cooldownSeconds,
           forceAttempt {
            adLog("Debug override bypass: cooldown gate")
        }

        guard isInterstitialReady else {
            adLog("Interstitial blocked: not ready at show-time. Triggering load now.")
            loadInterstitialAd(reason: "post_game_not_ready")
            return false
        }

        let didShow = await showInterstitialAd(placement: .interstitialPost)
        if didShow {
            resetInterstitialPacingAfterShow()
        } else {
            adLog("Interstitial attempt finished with didShow=false")
        }
        adLog("maybeShowPostGameInterstitial finished didShow=\(didShow)")
        return didShow
    }

    // MARK: - Convenience Checks
    func isAdReady(for placement: AdPlacement) -> Bool {
        if noAdsPurchased { return true }
        if Self.uiTestAdsDisabled { return false }
        switch placement {
        case .reviveReward, .doubleCoins, .freeSpinReward, .seasonPassUnlock:
            return isRewardedAdReady
        case .interstitialPost:
            return isInterstitialReady
        }
    }

    // MARK: - Root ViewController Helper
    private func getRootViewController() -> UIViewController? {
        let connectedScenes = UIApplication.shared.connectedScenes
        guard let scene = connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first,
              let rootVC = scene.windows.first(where: { $0.isKeyWindow })?.rootViewController
        else {
            adLog("getRootViewController failed: connectedScenes=\(connectedScenes.count)")
            return nil
        }

        // Walk the presentation chain to find the topmost VC
        var topVC = rootVC
        while let presented = topVC.presentedViewController {
            topVC = presented
        }
        adLog("getRootViewController resolved: root=\(String(describing: type(of: rootVC))) top=\(String(describing: type(of: topVC)))")
        return topVC
    }

    private var interstitialRunThreshold: Int {
        let value = defaults.integer(forKey: AdPacingKeys.runThreshold)
        return InterstitialPacingConfig.runThresholdRange.contains(value)
            ? value
            : Int.random(in: InterstitialPacingConfig.runThresholdRange)
    }

    private var interstitialCooldownSeconds: TimeInterval {
        let value = defaults.double(forKey: AdPacingKeys.cooldownSeconds)
        return value > 0 ? value : Double.random(in: InterstitialPacingConfig.cooldownRangeSeconds)
    }

    private var lastInterstitialShownAt: Date? {
        let timestamp = defaults.double(forKey: AdPacingKeys.lastInterstitialTimestamp)
        guard timestamp > 0 else { return nil }
        return Date(timeIntervalSince1970: timestamp)
    }

    private var lastRewardedCompletionAt: Date? {
        let timestamp = defaults.double(forKey: AdPacingKeys.lastRewardedCompletionTimestamp)
        guard timestamp > 0 else { return nil }
        return Date(timeIntervalSince1970: timestamp)
    }

    private func incrementCompletedRuns() -> Int {
        let next = defaults.integer(forKey: AdPacingKeys.runsSinceLastInterstitial) + 1
        defaults.set(next, forKey: AdPacingKeys.runsSinceLastInterstitial)
        return next
    }

    private func resetInterstitialPacingAfterShow() {
        defaults.set(0, forKey: AdPacingKeys.runsSinceLastInterstitial)
        defaults.set(Int.random(in: InterstitialPacingConfig.runThresholdRange), forKey: AdPacingKeys.runThreshold)
        defaults.set(Double.random(in: InterstitialPacingConfig.cooldownRangeSeconds), forKey: AdPacingKeys.cooldownSeconds)
        defaults.set(Date().timeIntervalSince1970, forKey: AdPacingKeys.lastInterstitialTimestamp)
        adLog(
            """
            Interstitial pacing reset after show: runsSinceLastInterstitial=0, runThreshold=\(interstitialRunThreshold), \
            cooldownSeconds=\(String(format: "%.1f", interstitialCooldownSeconds))
            """
        )
    }

    private func recordRewardedCompletion() {
        defaults.set(Date().timeIntervalSince1970, forKey: AdPacingKeys.lastRewardedCompletionTimestamp)
        adLog("Recorded rewarded completion timestamp=\(String(format: "%.0f", Date().timeIntervalSince1970))")
    }

    private func formatIntervalForLog(_ seconds: TimeInterval?) -> String {
        guard let seconds else { return "nil" }
        return String(format: "%.1fs", seconds)
    }
}

// MARK: - Ad Dismiss Delegate
// Detects when user closes the ad early (without earning reward).
// Without this, withCheckedContinuation would hang forever.
private class AdDismissDelegate: NSObject, FullScreenContentDelegate {
    private let label: String
    private let onDismiss: () -> Void
    private let onFail: ((Error) -> Void)?

    init(label: String, onDismiss: @escaping () -> Void, onFail: ((Error) -> Void)? = nil) {
        self.label = label
        self.onDismiss = onDismiss
        self.onFail = onFail
    }

    func adWillPresentFullScreenContent(_ ad: FullScreenPresentingAd) {
        adLog("fullScreenContentDelegate[\(label)]: willPresent")
    }

    func adDidRecordImpression(_ ad: FullScreenPresentingAd) {
        adLog("fullScreenContentDelegate[\(label)]: didRecordImpression")
    }

    func adDidRecordClick(_ ad: FullScreenPresentingAd) {
        adLog("fullScreenContentDelegate[\(label)]: didRecordClick")
    }

    func adWillDismissFullScreenContent(_ ad: FullScreenPresentingAd) {
        adLog("fullScreenContentDelegate[\(label)]: willDismiss")
    }

    func adDidDismissFullScreenContent(_ ad: FullScreenPresentingAd) {
        adLog("fullScreenContentDelegate[\(label)]: didDismiss")
        onDismiss()
    }

    nonisolated func ad(_ ad: FullScreenPresentingAd, didFailToPresentFullScreenContentWithError error: Error) {
        Task { @MainActor in
            adLog("fullScreenContentDelegate[\(self.label)]: failToPresent \(adErrorDetails(error))")
            if let onFail = self.onFail {
                onFail(error)
            } else {
                self.onDismiss()
            }
        }
    }
}
