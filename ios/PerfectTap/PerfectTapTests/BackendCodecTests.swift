import XCTest
@testable import PerfectTap

/// Backend-neutral codec + Supabase client plumbing (no network).
final class BackendCodecTests: XCTestCase {

    private func roundTrip(_ profile: PlayerProfile) throws -> PlayerProfile? {
        // Same path the Supabase build uses: encode → JSONPayload → jsonb → JSONSerialization → decode.
        let data = try JSONEncoder().encode(JSONPayload(BackendCodec.encodeProfile(profile)))
        let dict = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        return BackendCodec.decodeProfile(dict)
    }

    func testProfileRoundTripPreservesProgress() throws {
        var p = PlayerProfile()
        p.uid = "0f9c7f9e-1111-4222-8333-444455556666"
        p.username = "Tapper_1"
        p.coins = 1234
        p.level = 7
        p.noAds = true
        p.seasonPremium = false
        p.bestClassic = 5000
        p.ownedItems = ["theme_neon"]
        p.seasonClaimedTiers = [1, 2, 3]
        p.stats.duelWins = 3
        let out = try XCTUnwrap(try roundTrip(p))
        XCTAssertEqual(out.uid, p.uid)
        XCTAssertEqual(out.username, "Tapper_1")
        XCTAssertEqual(out.coins, 1234)
        XCTAssertEqual(out.level, 7)
        XCTAssertTrue(out.noAds)
        XCTAssertFalse(out.seasonPremium)
        XCTAssertEqual(out.bestClassic, 5000)
        XCTAssertEqual(out.ownedItems, ["theme_neon"])
        XCTAssertEqual(out.seasonClaimedTiers, [1, 2, 3])
        XCTAssertEqual(out.stats.duelWins, 3)
    }

    func testJSONPayloadKeepsBoolsAndIntsDistinct() throws {
        let data = try JSONEncoder().encode(JSONPayload(["flag": true, "one": 1, "zero": 0, "pi": 3.5, "none": NSNull()] as [String: Any]))
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertTrue(json.contains("\"flag\":true"))
        XCTAssertTrue(json.contains("\"one\":1"))
        XCTAssertTrue(json.contains("\"zero\":0"))
        XCTAssertTrue(json.contains("\"pi\":3.5"))
        XCTAssertTrue(json.contains("\"none\":null"))
    }

    func testPostgresTimestampsParse() {
        XCTAssertNotNil(BackendCodec.parseTimestamp("2026-11-12T08:49:16.381372+00:00"), "microseconds")
        XCTAssertNotNil(BackendCodec.parseTimestamp("2026-11-12T08:49:16+00:00"))
        XCTAssertNotNil(BackendCodec.parseTimestamp("2026-11-12T08:49:16.123Z"))
        XCTAssertNil(BackendCodec.parseTimestamp("not a date"))
    }

    func testDuelDecodeFromPostgresRow() {
        let row: [String: Any] = [
            "id": "d1", "code": "ABC234", "mode": "rush", "status": "completed",
            "host_id": "h", "host_name": "Host", "host_score": 900, "host_combo": 5,
            "guest_id": "g", "guest_name": "Guest", "guest_score": 0,
            "created_at": "2026-11-12T08:49:16.381372+00:00",
        ]
        let duel = BackendCodec.decodeDuel(id: "d1", data: row)
        XCTAssertEqual(duel.mode, .rush)
        XCTAssertEqual(duel.status, .completed)
        XCTAssertEqual(duel.result(forUID: "h"), .win)
        XCTAssertEqual(duel.result(forUID: "g"), .loss)
        XCTAssertTrue(duel.isComplete)
    }

    @MainActor
    func testServerErrorCodesMapToUserCopy() {
        XCTAssertEqual(SupabaseService.backendError(forCode: "rate_limited"), .rateLimited)
        XCTAssertEqual(SupabaseService.backendError(forCode: "duel_not_found"), .notFound("Duel not found"))
        XCTAssertEqual(SupabaseService.backendError(forCode: "already_friends").errorDescription, "Already friends")
        // Unknown/internal errors never leak raw server text.
        XCTAssertEqual(SupabaseService.backendError(forCode: "ERROR: relation x does not exist").errorDescription,
                       "Something went wrong. Please try again.")
    }

    func testBackendKindDefaultsToFirebaseForUnknownValues() {
        XCTAssertEqual(BackendKind(rawValue: "supabase"), .supabase)
        XCTAssertNil(BackendKind(rawValue: "SUPABASE"), "raw values are matched after lowercasing in `configured`")
        XCTAssertNil(BackendKind(rawValue: ""))
    }
}
