import XCTest
#if canImport(PerfectTap)
@testable import PerfectTap
#endif

/// Consent order and decisions for Guideline 5.1.2(i): UMP first, then ATT, and ads start
/// only after both. Personalization / ad signals only with ATT `.authorized`.
@MainActor
final class ConsentFlowTests: XCTestCase {

    // MARK: Decision table

    func testAuthorizedOutsideRegulatedRegionEnablesPersonalization() {
        let d = AdPrivacyDecision.make(canRequestAds: true, consentRequiredRegion: false, tracking: .authorized)
        XCTAssertEqual(d, AdPrivacyDecision(canRequestAds: true, personalizedAds: true, analyticsAdSignals: true, analyticsStorage: true))
    }

    func testDeniedRestrictedAndNotDeterminedNeverPersonalize() {
        for status in [TrackingAuthorization.denied, .restricted, .notDetermined] {
            let d = AdPrivacyDecision.make(canRequestAds: true, consentRequiredRegion: false, tracking: status)
            XCTAssertTrue(d.canRequestAds, "non-personalized ads still allowed (\(status))")
            XCTAssertFalse(d.personalizedAds, "\(status)")
            XCTAssertFalse(d.analyticsAdSignals, "\(status)")
        }
    }

    func testRegulatedRegionKeepsAnalyticsAdSignalsOffEvenWhenAuthorized() {
        let d = AdPrivacyDecision.make(canRequestAds: true, consentRequiredRegion: true, tracking: .authorized)
        XCTAssertTrue(d.personalizedAds)        // AdMob applies the UMP/TCF choice itself
        XCTAssertFalse(d.analyticsAdSignals)
    }

    // MARK: GDPR analytics storage (regression: usage analytics must not run before consent in the EEA)

    func testOutsideRegulatedRegionAnalyticsStorageOnWhateverATT() {
        for status in [TrackingAuthorization.denied, .authorized, .restricted, .notDetermined] {
            XCTAssertTrue(AdPrivacyDecision.make(canRequestAds: true, consentRequiredRegion: false, tracking: status).analyticsStorage)
        }
    }

    func testRegulatedRegionAnalyticsStorageNeedsTCFPurpose1() {
        XCTAssertFalse(AdPrivacyDecision.make(canRequestAds: true, consentRequiredRegion: true, tracking: .authorized, storageConsent: false).analyticsStorage)
        XCTAssertTrue(AdPrivacyDecision.make(canRequestAds: true, consentRequiredRegion: true, tracking: .denied, storageConsent: true).analyticsStorage)
    }

    func testRegulatedRegionFlowWithoutStorageConsentKeepsAnalyticsOff() async {
        let env = FakeConsentEnvironment(tracking: .notDetermined, answer: .authorized)
        env.consentRequiredRegion = true
        env.storageConsent = false
        let manager = ConsentManager(environment: env)
        await manager.gatherConsentIfNeeded()
        XCTAssertEqual(env.applied.last?.analyticsStorage, false)
        XCTAssertEqual(env.applied.last?.analyticsAdSignals, false)
        XCTAssertEqual(env.applied.last?.personalizedAds, true, "AdMob applies the TCF choice itself")
    }

    func testUMPTimeoutStillReachesATT() async {
        let env = FakeConsentEnvironment(tracking: .notDetermined, answer: .denied)
        env.umpHangs = true
        let manager = ConsentManager(environment: env, umpTimeout: 0.2)
        await manager.gatherConsentIfNeeded()
        XCTAssertTrue(env.calls.contains("requestATT"), "a stalled UMP request must not block the ATT prompt")
        XCTAssertFalse(env.calls.contains("presentForm"))
    }

    func testNoUMPConsentMeansNoAds() {
        let d = AdPrivacyDecision.make(canRequestAds: false, consentRequiredRegion: true, tracking: .authorized)
        XCTAssertFalse(d.canRequestAds)
        XCTAssertFalse(d.personalizedAds)
    }

    // MARK: Flow

    func testOrderIsUMPThenATTThenApply() async {
        let env = FakeConsentEnvironment(tracking: .notDetermined, answer: .denied)
        let manager = ConsentManager(environment: env)
        await manager.gatherConsentIfNeeded()
        XCTAssertEqual(env.calls, ["updateConsentInfo", "presentForm", "requestATT", "apply"])
        XCTAssertEqual(env.applied.last, AdPrivacyDecision(canRequestAds: true, personalizedAds: false, analyticsAdSignals: false, analyticsStorage: true))
        XCTAssertEqual(manager.trackingStatus, .denied)
    }

    func testAuthorizedAnswerEnablesPersonalizedAds() async {
        let env = FakeConsentEnvironment(tracking: .notDetermined, answer: .authorized)
        let manager = ConsentManager(environment: env)
        await manager.gatherConsentIfNeeded()
        XCTAssertEqual(env.applied.last?.personalizedAds, true)
    }

    func testAlreadyAnsweredDoesNotPromptAgain() async {
        let env = FakeConsentEnvironment(tracking: .denied, answer: .authorized)
        let manager = ConsentManager(environment: env)
        await manager.gatherConsentIfNeeded()
        XCTAssertFalse(env.calls.contains("requestATT"))
        XCTAssertEqual(env.applied.last?.personalizedAds, false)
    }

    func testRunsOncePerLaunch() async {
        let env = FakeConsentEnvironment(tracking: .notDetermined, answer: .denied)
        let manager = ConsentManager(environment: env)
        await manager.gatherConsentIfNeeded()
        await manager.gatherConsentIfNeeded()
        XCTAssertEqual(env.calls.filter { $0 == "requestATT" }.count, 1)
        XCTAssertEqual(env.applied.count, 1)
    }

    func testPromptSuppressedWhileInactiveIsRetried() async {
        // iOS returns notDetermined without a prompt if the app is not active yet.
        let env = FakeConsentEnvironment(tracking: .notDetermined, answer: .notDetermined)
        let manager = ConsentManager(environment: env)
        await manager.gatherConsentIfNeeded()
        env.answer = .authorized
        await manager.gatherConsentIfNeeded()
        XCTAssertEqual(env.calls.filter { $0 == "requestATT" }.count, 2)
        XCTAssertEqual(env.applied.last?.personalizedAds, true)
    }

    func testNotActiveDoesNothing() async {
        let env = FakeConsentEnvironment(tracking: .notDetermined, answer: .authorized)
        env.isAppActive = false
        let manager = ConsentManager(environment: env)
        await manager.gatherConsentIfNeeded()
        XCTAssertTrue(env.calls.isEmpty)
    }

    func testUMPErrorStillAsksATTAndUsesCachedConsent() async {
        let env = FakeConsentEnvironment(tracking: .notDetermined, answer: .denied)
        env.umpError = URLError(.notConnectedToInternet)
        env.canRequestAds = false
        let manager = ConsentManager(environment: env)
        await manager.gatherConsentIfNeeded()
        XCTAssertTrue(env.calls.contains("requestATT"))
        XCTAssertEqual(env.applied.last?.canRequestAds, false, "no ads until consent is known")
    }

    func testTrackingChangedInSettingsIsReapplied() async {
        let env = FakeConsentEnvironment(tracking: .authorized, answer: .authorized)
        let manager = ConsentManager(environment: env)
        await manager.gatherConsentIfNeeded()
        env.tracking = .denied
        manager.refreshTrackingStatus()
        XCTAssertEqual(env.applied.last?.personalizedAds, false)
        XCTAssertEqual(manager.trackingStatus, .denied)
    }

    func testPrivacyOptionsWithdrawalIsReapplied() async {
        let env = FakeConsentEnvironment(tracking: .authorized, answer: .authorized)
        env.privacyOptionsRequired = true
        let manager = ConsentManager(environment: env)
        await manager.gatherConsentIfNeeded()
        XCTAssertTrue(manager.privacyOptionsRequired)
        env.canRequestAds = false               // user withdrew consent in the form
        await manager.presentPrivacyOptions()
        XCTAssertEqual(env.calls.last, "apply")
        XCTAssertEqual(env.applied.last?.canRequestAds, false)
    }
}

@MainActor
private final class FakeConsentEnvironment: ConsentEnvironment {
    var calls: [String] = []
    var applied: [AdPrivacyDecision] = []
    var tracking: TrackingAuthorization
    var answer: TrackingAuthorization
    var umpError: Error?
    var canRequestAds = true
    var consentRequiredRegion = false
    var storageConsent = false
    var umpHangs = false
    var privacyOptionsRequired = false
    var isAppActive = true

    init(tracking: TrackingAuthorization, answer: TrackingAuthorization) {
        self.tracking = tracking
        self.answer = answer
    }

    var trackingStatus: TrackingAuthorization { tracking }

    func updateConsentInfo() async throws {
        calls.append("updateConsentInfo")
        if umpHangs { try await Task.sleep(nanoseconds: 5_000_000_000) }
        if let umpError { throw umpError }
    }
    func presentConsentFormIfRequired() async throws { calls.append("presentForm") }
    func requestTrackingAuthorization() async -> TrackingAuthorization {
        calls.append("requestATT")
        tracking = answer
        return answer
    }
    func apply(_ decision: AdPrivacyDecision) {
        calls.append("apply")
        applied.append(decision)
    }
    func presentPrivacyOptionsForm() async { calls.append("privacyOptions") }
}
