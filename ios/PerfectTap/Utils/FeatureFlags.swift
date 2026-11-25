import Foundation

// MARK: - Fail-closed monetization configuration
//
// Every production switch is supplied by the build configuration and defaults
// to OFF when it is absent or malformed. A source merge therefore cannot expose
// products before App Store Connect, Supabase and agreements are ready.

enum MonetizationCategory: Equatable {
    case coins
    case removeAds
    case premiumSkins
}

enum MonetizationBlocker: Equatable {
    case catalogDisabled
    case serverVerificationDisabled
    case categoryDisabled
    case invalidAccount
    case permanentAccountRequired

    var message: String {
        switch self {
        case .catalogDisabled, .serverVerificationDisabled, .categoryDisabled:
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

struct MonetizationConfiguration: Equatable {
    let catalog: Bool
    let serverVerification: Bool
    let coins: Bool
    let removeAds: Bool
    let premiumSkins: Bool
}

enum MonetizationPolicy {
    static func availability(
        for category: MonetizationCategory,
        configuration: MonetizationConfiguration,
        accountToken: UUID?,
        isPermanentAccount: Bool
    ) -> MonetizationAvailability {
        guard configuration.catalog else { return .blocked(.catalogDisabled) }
        guard configuration.serverVerification else { return .blocked(.serverVerificationDisabled) }
        switch category {
        case .coins where !configuration.coins,
             .removeAds where !configuration.removeAds,
             .premiumSkins where !configuration.premiumSkins:
            return .blocked(.categoryDisabled)
        default:
            break
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
}

enum FeatureFlags {
    private static func enabled(_ key: String) -> Bool {
        let raw = (Bundle.main.object(forInfoDictionaryKey: key) as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
        return raw == "YES" || raw == "TRUE" || raw == "1"
    }

    static var iapEnabled: Bool { enabled("PT_IAP_CATALOG_ENABLED") }
    static var serverPurchaseVerification: Bool { enabled("PT_IAP_SERVER_VERIFICATION_ENABLED") }
    static var coinPacksEnabled: Bool { enabled("PT_IAP_COIN_PACKS_ENABLED") }
    static var removeAdsEnabled: Bool { enabled("PT_IAP_REMOVE_ADS_ENABLED") }
    static var premiumSkinsEnabled: Bool { enabled("PT_IAP_PREMIUM_SKINS_ENABLED") }
    static var authoritativeEconomyEnabled: Bool { enabled("PT_AUTHORITATIVE_ECONOMY_ENABLED") }

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
            premiumSkins: premiumSkinsEnabled
        )
    }

    /// DEBUG preview arguments affect visibility only, never purchase authority.
    static var premiumSkinsVisible: Bool {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-PTPremiumPreview") || iapPreview { return true }
        #endif
        return realMoneyPurchasesEnabled && premiumSkinsEnabled
    }

    static var coinPacksVisible: Bool {
        #if DEBUG
        if iapPreview { return true }
        #endif
        return realMoneyPurchasesEnabled && coinPacksEnabled
    }

    static var removeAdsVisible: Bool {
        #if DEBUG
        if iapPreview { return true }
        #endif
        return realMoneyPurchasesEnabled && removeAdsEnabled
    }

    @MainActor
    static func monetizationAvailability(for category: MonetizationCategory) -> MonetizationAvailability {
        let accountToken = Backend.shared.currentUID.flatMap(UUID.init(uuidString:))
        return MonetizationPolicy.availability(
            for: category,
            configuration: monetizationConfiguration,
            accountToken: accountToken,
            isPermanentAccount: Backend.shared.isPermanentAccount
        )
    }
}
