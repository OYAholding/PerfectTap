import XCTest
@testable import PerfectTap

/// After claim-legacy-account, the server owns username + friend code. Keeping the
/// Firebase-era local values would make every later save_profile fail.
final class LegacyClaimIdentityTests: XCTestCase {

    private func profile(username: String, code: String, coins: Int) -> PlayerProfile {
        var p = PlayerProfile()
        p.uid = "legacyFirebaseUid"
        p.username = username
        p.friendCode = code
        p.coins = coins
        return p
    }

    func testUsernameConflictClearsLocalUsernameAndKeepsProgress() {
        let local = profile(username: "GG", code: "AY8RFU", coins: 1560)
        let server = profile(username: "", code: "", coins: 1560)   // claim dropped both (taken)
        let out = SupabaseService.reconcileIdentity(local: local, server: server, newCode: { "NEW234" })
        XCTAssertEqual(out.username, "", "empty username → onboarding asks for a new one")
        XCTAssertEqual(out.friendCode, "NEW234", "taken legacy code must not be re-sent")
        XCTAssertEqual(out.coins, 1560, "local progress is untouched")
        XCTAssertEqual(out.uid, local.uid)
    }

    func testCleanClaimKeepsIdentity() {
        let local = profile(username: "Ohav", code: "V9YPN5", coins: 1203)
        let server = profile(username: "Ohav", code: "V9YPN5", coins: 1203)
        let out = SupabaseService.reconcileIdentity(local: local, server: server, newCode: { XCTFail("no new code"); return "" })
        XCTAssertEqual(out.username, "Ohav")
        XCTAssertEqual(out.friendCode, "V9YPN5")
    }

    func testGeneratedFriendCodeFormat() {
        let code = SupabaseService.generateFriendCode()
        XCTAssertEqual(code.count, 6)
        XCTAssertNil(code.range(of: "[^A-HJ-NP-Z2-9]", options: .regularExpression))
    }

    func testCloudBackupGateDefaultsOffForSupabase() {
        // Test host Info.plist has no PT_EMAIL_OTP_ENABLED → sign-up must not be offered on Supabase.
        let raw = Bundle.main.object(forInfoDictionaryKey: "PT_EMAIL_OTP_ENABLED") as? String
        XCTAssertNotEqual(raw?.uppercased(), "YES")
    }
}
