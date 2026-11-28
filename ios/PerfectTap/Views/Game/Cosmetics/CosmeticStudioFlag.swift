import Foundation

// MARK: - Cosmetic Studio flag shim
//
// Thin forwarder to `FeatureFlags.cosmeticStudioEnabled` (Info.plist
// `PT_COSMETIC_STUDIO_ENABLED`). A missing key means OFF, so a build without
// the key behaves exactly like the pre-Studio game.

enum CosmeticStudioFlag {
    static let infoPlistKey = "PT_COSMETIC_STUDIO_ENABLED"

    /// Tests set this to force the flag; nil = read Info.plist.
    static var overrideForTesting: Bool? = nil

    /// Forwards to the real flag (FeatureFlags owns the Info.plist key);
    /// kept so tests can force the flag without a custom Info.plist.
    static var isEnabled: Bool {
        overrideForTesting ?? FeatureFlags.cosmeticStudioEnabled
    }
}
