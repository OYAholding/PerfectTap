import Foundation
import UIKit
import AppTrackingTransparency
import UserMessagingPlatform
import FirebaseAnalytics

// MARK: - Privacy consent (Google UMP + Apple App Tracking Transparency)
//
// Order on every launch, before ANY ad request:
//   1. Google UMP: refresh consent info and show the consent form where the law requires it
//      (EEA / UK / Switzerland and other regulated regions). Elsewhere UMP reports "not required".
//   2. Apple ATT: if the user has never been asked, show the system prompt
//      (NSUserTrackingUsageDescription). Asked once; later changes happen in iOS Settings.
//   3. Apply the result:
//        - Ads start only when UMP says ads may be requested.
//        - Personalized ads (IDFA) and Firebase Analytics ad signals are enabled ONLY when
//          ATT is `.authorized`. Denied / restricted / not determined -> non-personalized ads,
//          no ad signals. Gameplay is identical in every case.
//
// No fingerprinting or alternative identifiers are used to work around a denial.

/// ATT status, decoupled from the framework so the decision logic is unit-testable.
enum TrackingAuthorization: Equatable {
    case notDetermined, restricted, denied, authorized

    init(_ status: ATTrackingManager.AuthorizationStatus) {
        switch status {
        case .authorized: self = .authorized
        case .denied: self = .denied
        case .restricted: self = .restricted
        case .notDetermined: self = .notDetermined
        @unknown default: self = .denied
        }
    }
}

/// What the app is allowed to do with ads and analytics after consent.
struct AdPrivacyDecision: Equatable {
    /// UMP allows ad requests (consent obtained, or not required in this region).
    let canRequestAds: Bool
    /// IDFA-based personalized ads. Requires ATT `.authorized`.
    let personalizedAds: Bool
    /// Firebase Analytics ad_storage / ad_user_data / ad_personalization.
    /// Requires ATT `.authorized` and a region where UMP consent is not required
    /// (in regulated regions Google's SDKs take the user's choice from the UMP/TCF signal).
    let analyticsAdSignals: Bool
    /// Firebase Analytics analytics_storage (first-party usage analytics, never tracking).
    /// Off by default (Info.plist) until this decision. Outside regulated regions: on.
    /// In regulated regions (EEA/UK/CH): only with TCF Purpose 1 consent ("store and/or
    /// access information on a device") from the UMP form.
    let analyticsStorage: Bool

    static func make(canRequestAds: Bool, consentRequiredRegion: Bool, tracking: TrackingAuthorization,
                     storageConsent: Bool = false) -> AdPrivacyDecision {
        let tracked = tracking == .authorized
        return AdPrivacyDecision(
            canRequestAds: canRequestAds,
            personalizedAds: canRequestAds && tracked,
            analyticsAdSignals: tracked && !consentRequiredRegion,
            analyticsStorage: !consentRequiredRegion || storageConsent
        )
    }
}

/// Side effects of the consent flow, injectable for tests.
@MainActor
protocol ConsentEnvironment: AnyObject {
    func updateConsentInfo() async throws
    func presentConsentFormIfRequired() async throws
    var canRequestAds: Bool { get }
    var consentRequiredRegion: Bool { get }
    /// TCF Purpose 1 consent from the UMP form (only meaningful in regulated regions).
    var storageConsent: Bool { get }
    var privacyOptionsRequired: Bool { get }
    var trackingStatus: TrackingAuthorization { get }
    var isAppActive: Bool { get }
    func requestTrackingAuthorization() async -> TrackingAuthorization
    func apply(_ decision: AdPrivacyDecision)
    func presentPrivacyOptionsForm() async
}

@MainActor
final class ConsentManager: ObservableObject {
    static let shared = ConsentManager(environment: LiveConsentEnvironment())

    @Published private(set) var decision: AdPrivacyDecision?
    @Published private(set) var privacyOptionsRequired = false
    @Published private(set) var trackingStatus: TrackingAuthorization = .notDetermined

    private let environment: ConsentEnvironment
    private var isRunning = false
    private var hasCompleted = false

    private let umpTimeout: TimeInterval

    init(environment: ConsentEnvironment, umpTimeout: TimeInterval = 8) {
        self.environment = environment
        self.umpTimeout = umpTimeout
        self.trackingStatus = environment.trackingStatus
    }

    /// Runs `operation`, returning true if it finished without error before `seconds`.
    /// On timeout the operation keeps running in the background but is no longer awaited.
    static func withTimeout(_ seconds: TimeInterval, _ operation: @escaping @MainActor () async throws -> Void) async -> Bool {
        await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            let gate = OnceGate(cont)
            Task { @MainActor in
                do { try await operation(); gate.finish(true) } catch {
                    #if DEBUG
                    print("[Consent] UMP error: \(error.localizedDescription)")
                    #endif
                    gate.finish(false)
                }
            }
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                #if DEBUG
                if !gate.isFinished { print("[Consent] UMP timed out after \(seconds)s — continuing to ATT") }
                #endif
                gate.finish(false)
            }
        }
    }

    /// UI tests launch with `-PTUITestNoAds` (DEBUG only): no system prompts, no ads —
    /// unless they also pass `-PTUITestConsentFlow` to exercise the real ATT prompt.
    /// The shared instance also stays idle while the app is only hosting unit tests.
    static var isDisabledForTests: Bool {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-PTUITestConsentFlow") { return false }
        if AdManager.uiTestAdsDisabled { return true }
        return ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        #else
        return false
        #endif
    }

    /// Runs the consent flow once per launch. Call whenever the app becomes active:
    /// ATT can only be shown while the app is active, so an attempt made too early is retried.
    func gatherConsentIfNeeded() async {
        guard !(self === Self.shared && Self.isDisabledForTests), !isRunning, !hasCompleted else { return }
        guard environment.isAppActive else { return }
        isRunning = true
        defer { isRunning = false }

        // 1. Google UMP. A network error is not fatal: UMP keeps the last known consent,
        //    and `canRequestAds` stays false until consent is known. The info update is
        //    bounded by a timeout so a slow network can never block the ATT prompt.
        let env = environment
        let updated = await Self.withTimeout(umpTimeout) {
            try await env.updateConsentInfo()
        }
        if updated {
            // Presenting a form waits for the user, so it is not time-boxed.
            do { try await env.presentConsentFormIfRequired() } catch {
                #if DEBUG
                print("[Consent] UMP form error: \(error.localizedDescription)")
                #endif
            }
        }

        // 2. Apple ATT (only if never asked). If the system did not show the prompt because
        //    the app was not active, the status stays notDetermined and we retry next time.
        var tracking = environment.trackingStatus
        if tracking == .notDetermined {
            tracking = await environment.requestTrackingAuthorization()
        }
        trackingStatus = tracking

        // 3. Apply.
        let result = AdPrivacyDecision.make(
            canRequestAds: environment.canRequestAds,
            consentRequiredRegion: environment.consentRequiredRegion,
            tracking: tracking,
            storageConsent: environment.storageConsent
        )
        environment.apply(result)
        decision = result
        privacyOptionsRequired = environment.privacyOptionsRequired
        // Ads are already configured (non-personalized). Only the ATT prompt is retried.
        hasCompleted = tracking != .notDetermined
    }

    /// Settings → Privacy Choices. Re-applies the decision afterwards so a withdrawal takes effect.
    func presentPrivacyOptions() async {
        await environment.presentPrivacyOptionsForm()
        let result = AdPrivacyDecision.make(
            canRequestAds: environment.canRequestAds,
            consentRequiredRegion: environment.consentRequiredRegion,
            tracking: environment.trackingStatus,
            storageConsent: environment.storageConsent
        )
        environment.apply(result)
        decision = result
        trackingStatus = environment.trackingStatus
        privacyOptionsRequired = environment.privacyOptionsRequired
    }

    /// Re-reads ATT (the user may have changed it in iOS Settings) and re-applies.
    func refreshTrackingStatus() {
        guard hasCompleted else { return }
        let status = environment.trackingStatus
        guard status != trackingStatus else { return }
        trackingStatus = status
        let result = AdPrivacyDecision.make(
            canRequestAds: environment.canRequestAds,
            consentRequiredRegion: environment.consentRequiredRegion,
            tracking: status,
            storageConsent: environment.storageConsent
        )
        environment.apply(result)
        decision = result
    }
}

/// Resumes a continuation exactly once (main actor only).
@MainActor
private final class OnceGate {
    private var continuation: CheckedContinuation<Bool, Never>?
    init(_ continuation: CheckedContinuation<Bool, Never>) { self.continuation = continuation }
    var isFinished: Bool { continuation == nil }
    func finish(_ value: Bool) {
        continuation?.resume(returning: value)
        continuation = nil
    }
}

// MARK: - Live environment

@MainActor
final class LiveConsentEnvironment: ConsentEnvironment {
    private var info: ConsentInformation { ConsentInformation.shared }

    func updateConsentInfo() async throws {
        let parameters = RequestParameters()
        #if DEBUG
        // QA only: `-PTUMPDebugEEA` makes UMP treat this simulator/test device as being in
        // the EEA, to check the published GDPR message without travelling. Never in Release.
        if ProcessInfo.processInfo.arguments.contains("-PTUMPDebugEEA") {
            let debug = DebugSettings()
            debug.geography = .EEA
            if ProcessInfo.processInfo.arguments.contains("-PTUMPReset") { info.reset() }
            parameters.debugSettings = debug
        }
        #endif
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            info.requestConsentInfoUpdate(with: parameters) { error in
                if let error { cont.resume(throwing: error) } else { cont.resume() }
            }
        }
    }

    func presentConsentFormIfRequired() async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            ConsentForm.loadAndPresentIfRequired(from: Self.topViewController()) { error in
                if let error { cont.resume(throwing: error) } else { cont.resume() }
            }
        }
    }

    var canRequestAds: Bool { info.canRequestAds }
    var consentRequiredRegion: Bool {
        switch info.consentStatus {
        case .required, .obtained: return true
        default: return false
        }
    }
    var privacyOptionsRequired: Bool { info.privacyOptionsRequirementStatus == .required }
    /// IAB TCF v2 string written by UMP: position 1 = Purpose 1 (store/access info on device).
    var storageConsent: Bool {
        (UserDefaults.standard.string(forKey: "IABTCF_PurposeConsents") ?? "").first == "1"
    }
    var trackingStatus: TrackingAuthorization { TrackingAuthorization(ATTrackingManager.trackingAuthorizationStatus) }
    var isAppActive: Bool { UIApplication.shared.applicationState == .active }

    func requestTrackingAuthorization() async -> TrackingAuthorization {
        TrackingAuthorization(await ATTrackingManager.requestTrackingAuthorization())
    }

    func apply(_ decision: AdPrivacyDecision) {
        let ads: ConsentStatusValue = decision.analyticsAdSignals ? .granted : .denied
        Analytics.setConsent([
            .analyticsStorage: decision.analyticsStorage ? .granted : .denied,
            .adStorage: ads,
            .adUserData: ads,
            .adPersonalization: ads,
        ])
        AdManager.shared.applyPrivacy(decision)
    }

    func presentPrivacyOptionsForm() async {
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            ConsentForm.presentPrivacyOptionsForm(from: Self.topViewController()) { _ in cont.resume() }
        }
    }

    static func topViewController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive } ?? UIApplication.shared.connectedScenes.first as? UIWindowScene
        var top = scene?.windows.first { $0.isKeyWindow }?.rootViewController ?? scene?.windows.first?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }
}

private typealias ConsentStatusValue = FirebaseAnalytics.ConsentStatus
