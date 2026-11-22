import Foundation

// MARK: - Feature flags
//
// Real-money purchases stay OFF in every build until the owner approves
// (products created in App Store Connect, server verification deployed, Paid
// Apps Agreement active — docs/PAYMENTS_READINESS.he.md).

enum FeatureFlags {
    /// Coin packs / Remove Ads / premium skins can be bought with real money.
    static let iapEnabled = false

    /// Send every StoreKit transaction to the `verify-purchase` edge function
    /// and finish it only after the server recorded it. Requires the edge
    /// function + purchase ledger migration to be deployed (owner approval).
    static let serverPurchaseVerification = false

    /// Real-money purchases are offered only when BOTH are on: with IAP on but
    /// server verification off, the hardened save_profile would strip paid
    /// skins and clamp paid coins on the server copy.
    static var realMoneyPurchasesEnabled: Bool { iapEnabled && serverPurchaseVerification }

    /// Premium skins are listed in the shop. Release: follows `iapEnabled`.
    /// DEBUG: also on with the `-PTPremiumPreview` launch argument, so the
    /// skins can be previewed and tested with the local StoreKit configuration.
    static var premiumSkinsVisible: Bool {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-PTPremiumPreview") { return true }
        #endif
        return realMoneyPurchasesEnabled
    }
}
