import Foundation

// MARK: - Cosmetic Studio flag shim
//
// LEAD: replace reads of `CosmeticStudioFlag.isEnabled` with
// `FeatureFlags.cosmeticStudioEnabled` at integration (Agent D owns the real
// flag, same Info.plist key) — or keep this as a thin forwarder so the test
// override below keeps working.
//
// Same parsing as FeatureFlags: YES / TRUE / 1, case-insensitive. A missing key
// means OFF, so a build without the key behaves exactly like the pre-Studio game.

enum CosmeticStudioFlag {
    static let infoPlistKey = "PT_COSMETIC_STUDIO_ENABLED"

    /// Tests set this to force the flag; nil = read Info.plist.
    static var overrideForTesting: Bool? = nil

    static var isEnabled: Bool {
        if let forced = overrideForTesting { return forced }
        let raw = (Bundle.main.object(forInfoDictionaryKey: infoPlistKey) as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
        return raw == "YES" || raw == "TRUE" || raw == "1"
    }
}
