import Foundation

// MARK: - Fail-closed monetization activation (docs/MONETIZATION_ACTIVATION_STRATEGY.md)
//
// A purchase can start only when BOTH layers say yes:
//
//  1. Build-time capability ceiling: the PT_IAP_* Info.plist keys, filled from
//     the build configuration's xcconfig (Config/Monetization.*.xcconfig). They
//     say what this binary is *able* to sell. Absent or malformed ⇒ OFF. The
//     default Debug and Release configurations compile every ceiling to NO.
//
//  2. Runtime server gate: `get_iap_sales_status` (Supabase) says whether sales
//     are open for the StoreKit environment this binary runs in (Sandbox for
//     TestFlight / App Review, Production for the App Store) and which product
//     IDs the server will grant. Unknown, unreachable, stale or undecodable ⇒
//     sales closed.
//
// Neither layer ever blocks delivering / restoring something the player already
// paid for: Transaction.updates, Transaction.unfinished and Restore Purchases
// keep running so a paying player is never left with nothing.

enum MonetizationCategory: Equatable, CaseIterable {
    case coins
    case removeAds
    case premiumSkins

    var productIDs: [String] {
        switch self {
        case .coins:        return CoinPackID.allCases.map(\.rawValue)
        case .removeAds:    return SpecialProductID.allCases.map(\.rawValue)
        case .premiumSkins: return ShopItem.premiumProductIDs
        }
    }

    static func category(for productID: String) -> MonetizationCategory? {
        allCases.first { $0.productIDs.contains(productID) }
    }
}

enum MonetizationBlocker: Equatable {
    case catalogDisabled
    case serverVerificationDisabled
    case categoryDisabled
    /// Ceiling allows it, but the server gate is closed / unknown / unreachable.
    case salesPaused
    case invalidAccount
    case permanentAccountRequired

    var message: String {
        switch self {
        case .catalogDisabled, .serverVerificationDisabled, .categoryDisabled, .salesPaused:
            return "Purchases are not available yet."
        case .invalidAccount:
            return "Your player account is still connecting. Please try again."
        case .permanentAccountRequired:
            return "Sign in with Apple before buying coins so your balance can be recovered securely on another device."
        }
    }
}

enum MonetizationAvailability: Equatable {
    case available(accountToken: UUID)
    case blocked(MonetizationBlocker)
}

/// Build-time capability ceiling (what this binary may ever sell).
struct MonetizationConfiguration: Equatable {
    let catalog: Bool
    let serverVerification: Bool
    let coins: Bool
    let removeAds: Bool
    let premiumSkins: Bool
    /// Debug-StoreKit configuration only (compiled out of release builds):
    /// on-device verification against the local .storekit file, Xcode
    /// environment only. Never satisfies the gate in Sandbox or Production.
    let localStoreKitTesting: Bool

    init(catalog: Bool, serverVerification: Bool, coins: Bool, removeAds: Bool, premiumSkins: Bool,
         localStoreKitTesting: Bool = false) {
        self.catalog = catalog
        self.serverVerification = serverVerification
        self.coins = coins
        self.removeAds = removeAds
        self.premiumSkins = premiumSkins
        self.localStoreKitTesting = localStoreKitTesting
    }

    static let off = MonetizationConfiguration(catalog: false, serverVerification: false, coins: false,
                                               removeAds: false, premiumSkins: false)

    func allows(_ category: MonetizationCategory) -> Bool {
        switch category {
        case .coins:        return coins
        case .removeAds:    return removeAds
        case .premiumSkins: return premiumSkins
        }
    }
}

/// Where StoreKit will charge. Resolved from `AppTransaction` (iOS 16+).
enum StoreEnvironment: String, Equatable {
    case xcode        // local .storekit file (simulator / Xcode run)
    case sandbox      // TestFlight, App Review, Sandbox Apple Account
    case production   // App Store
    case unknown      // could not be determined → treated as Production (stricter gate)
}

/// Server answer of `public.get_iap_sales_status()` (see strategy doc §4).
struct ServerSalesStatus: Equatable {
    let sandboxSalesEnabled: Bool
    let productionSalesEnabled: Bool
    let enabledProductIDs: Set<String>
    let fetchedAt: Date

    /// Max age before the client re-asks and, if unreachable, closes sales.
    static let maxAge: TimeInterval = 10 * 60

    func salesEnabled(in environment: StoreEnvironment) -> Bool {
        switch environment {
        case .sandbox:              return sandboxSalesEnabled
        case .production, .unknown: return productionSalesEnabled
        case .xcode:                return false   // local testing never relies on the live server
        }
    }

    func isFresh(now: Date = Date()) -> Bool {
        fetchedAt <= now.addingTimeInterval(60) && now.timeIntervalSince(fetchedAt) <= Self.maxAge
    }

    /// Strict decoder: any missing / mistyped field ⇒ nil ⇒ sales closed.
    static func decode(_ data: Data, fetchedAt: Date = Date()) -> ServerSalesStatus? {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              (root["schemaVersion"] as? Int) == 1,
              let sandbox = (root["sandbox"] as? [String: Any])?["salesEnabled"] as? Bool,
              let production = (root["production"] as? [String: Any])?["salesEnabled"] as? Bool,
              let products = root["enabledProducts"] as? [String]
        else { return nil }
        return ServerSalesStatus(sandboxSalesEnabled: sandbox, productionSalesEnabled: production,
                                 enabledProductIDs: Set(products), fetchedAt: fetchedAt)
    }
}

/// Runtime gate snapshot used by the policy.
struct SalesGate: Equatable {
    var environment: StoreEnvironment
    var status: ServerSalesStatus?

    static let closed = SalesGate(environment: .unknown, status: nil)

    func allows(productID: String?, category: MonetizationCategory,
                configuration: MonetizationConfiguration, now: Date = Date()) -> Bool {
        if environment == .xcode {
            // Only the Debug-StoreKit configuration may sell in the Xcode
            // environment, and it never needs (or trusts) the live server.
            return configuration.localStoreKitTesting
        }
        guard let status, status.isFresh(now: now), status.salesEnabled(in: environment) else { return false }
        if let productID { return status.enabledProductIDs.contains(productID) }
        return category.productIDs.contains { status.enabledProductIDs.contains($0) }
    }
}

enum MonetizationPolicy {
    static func availability(
        for category: MonetizationCategory,
        productID: String? = nil,
        configuration: MonetizationConfiguration,
        gate: SalesGate,
        accountToken: UUID?,
        isPermanentAccount: Bool,
        now: Date = Date()
    ) -> MonetizationAvailability {
        guard configuration.catalog || configuration.localStoreKitTesting else { return .blocked(.catalogDisabled) }
        let localTesting = configuration.localStoreKitTesting && gate.environment == .xcode
        guard configuration.serverVerification || localTesting else { return .blocked(.serverVerificationDisabled) }
        guard configuration.allows(category) else { return .blocked(.categoryDisabled) }
        guard gate.allows(productID: productID, category: category, configuration: configuration, now: now) else {
            return .blocked(.salesPaused)
        }
        guard let accountToken else { return .blocked(.invalidAccount) }
        // Non-consumables are recoverable from Apple's signed StoreKit history.
        // Consumable balances are not in currentEntitlements, so they require a
        // recoverable Supabase identity (Apple or verified email) before sale.
        if category == .coins && !isPermanentAccount {
            return .blocked(.permanentAccountRequired)
        }
        return .available(accountToken: accountToken)
    }

    /// Ceiling + account rules only, with the server gate treated as open.
    /// Kept for the 1.2.0 unit tests of the account rules; production code
    /// always goes through `FeatureFlags.monetizationAvailability`.
    static func availability(
        for category: MonetizationCategory,
        configuration: MonetizationConfiguration,
        accountToken: UUID?,
        isPermanentAccount: Bool
    ) -> MonetizationAvailability {
        let open = SalesGate(environment: .sandbox, status: ServerSalesStatus(
            sandboxSalesEnabled: true, productionSalesEnabled: false,
            enabledProductIDs: Set(MonetizationCategory.allCases.flatMap(\.productIDs)), fetchedAt: Date()))
        return availability(for: category, configuration: configuration, gate: open,
                            accountToken: accountToken, isPermanentAccount: isPermanentAccount)
    }
}

/// Thread-safe holder of the runtime gate (read by nonisolated view helpers,
/// written by PurchaseManager on the main actor). Starts closed.
final class MonetizationRuntime: @unchecked Sendable {
    static let shared = MonetizationRuntime()
    private let lock = NSLock()
    private var _gate = SalesGate.closed

    var gate: SalesGate {
        lock.lock(); defer { lock.unlock() }
        return _gate
    }

    func update(_ gate: SalesGate) {
        lock.lock(); _gate = gate; lock.unlock()
    }
}

enum FeatureFlags {
    private static func enabled(_ key: String) -> Bool {
        let raw = (Bundle.main.object(forInfoDictionaryKey: key) as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
        return raw == "YES" || raw == "TRUE" || raw == "1"
    }

    // Build-time capability ceilings (not "sales are on": see SalesGate).
    static var iapEnabled: Bool { enabled("PT_IAP_CATALOG_ENABLED") }
    static var serverPurchaseVerification: Bool { enabled("PT_IAP_SERVER_VERIFICATION_ENABLED") }
    static var coinPacksEnabled: Bool { enabled("PT_IAP_COIN_PACKS_ENABLED") }
    static var removeAdsEnabled: Bool { enabled("PT_IAP_REMOVE_ADS_ENABLED") }
    static var premiumSkinsEnabled: Bool { enabled("PT_IAP_PREMIUM_SKINS_ENABLED") }
    static var authoritativeEconomyEnabled: Bool { enabled("PT_AUTHORITATIVE_ECONOMY_ENABLED") }

    /// Debug-StoreKit configuration only; always false in release builds.
    static var localStoreKitTesting: Bool {
        #if DEBUG
        return enabled("PT_IAP_LOCAL_STOREKIT_TESTING")
        #else
        return false
        #endif
    }

    /// Name of the xcconfig profile compiled into this binary (diagnostics).
    static var monetizationProfile: String {
        (Bundle.main.object(forInfoDictionaryKey: "PT_MONETIZATION_PROFILE") as? String).flatMap {
            $0.isEmpty || $0.hasPrefix("$(") ? nil : $0
        } ?? "Off"
    }

    /// The binary may sell real-money products at all (ceiling only).
    static var realMoneyPurchasesEnabled: Bool { iapEnabled && serverPurchaseVerification }

    static var iapPreview: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("-PTIAPPreview")
        #else
        return false
        #endif
    }

    static var monetizationConfiguration: MonetizationConfiguration {
        MonetizationConfiguration(
            catalog: iapEnabled,
            serverVerification: serverPurchaseVerification,
            coins: coinPacksEnabled,
            removeAds: removeAdsEnabled,
            premiumSkins: premiumSkinsEnabled,
            localStoreKitTesting: localStoreKitTesting
        )
    }

    /// The ceiling allows this category at all (decides whether StoreKit
    /// products are loaded and the server gate is queried).
    static var anyCategoryWithinCeiling: Bool {
        let config = monetizationConfiguration
        return (config.catalog || config.localStoreKitTesting) && MonetizationCategory.allCases.contains(where: config.allows)
    }

    private static func sellable(_ category: MonetizationCategory) -> Bool {
        let config = monetizationConfiguration
        let gate = MonetizationRuntime.shared.gate
        guard config.allows(category), config.catalog || config.localStoreKitTesting else { return false }
        guard config.serverVerification || (config.localStoreKitTesting && gate.environment == .xcode) else { return false }
        return gate.allows(productID: nil, category: category, configuration: config)
    }

    /// DEBUG preview arguments affect visibility only, never purchase authority.
    static var premiumSkinsVisible: Bool {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-PTPremiumPreview") || iapPreview { return true }
        #endif
        return sellable(.premiumSkins)
    }

    static var coinPacksVisible: Bool {
        #if DEBUG
        if iapPreview { return true }
        #endif
        return sellable(.coins)
    }

    static var removeAdsVisible: Bool {
        #if DEBUG
        if iapPreview { return true }
        #endif
        return sellable(.removeAds)
    }

    @MainActor
    static func monetizationAvailability(for category: MonetizationCategory,
                                         productID: String? = nil) -> MonetizationAvailability {
        let accountToken = Backend.shared.currentUID.flatMap(UUID.init(uuidString:))
        return MonetizationPolicy.availability(
            for: category,
            productID: productID,
            configuration: monetizationConfiguration,
            gate: MonetizationRuntime.shared.gate,
            accountToken: accountToken,
            isPermanentAccount: Backend.shared.isPermanentAccount
        )
    }
}
