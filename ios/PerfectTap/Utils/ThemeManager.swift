import SwiftUI

// MARK: - ThemeManager (@EnvironmentObject injected at root)
final class ThemeManager: ObservableObject {
    @Published var current: AppTheme = .default

    private static let legacyKey = "perfecttap_theme"

    /// `profile.equippedTheme` is the source of truth; the old separate
    /// UserDefaults key is only a fallback for profiles that predate it.
    init() {
        let profile = PlayerProfile.load()
        let saved = profile?.equippedTheme ?? UserDefaults.standard.string(forKey: Self.legacyKey) ?? "default"
        current = Self.resolve(saved, profile: profile)
        #if DEBUG
        // Perf runs with a premium skin (scripts/perf-run.sh PT_PERF_THEME=…).
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-PTForceTheme"), i + 1 < args.count {
            current = AppTheme.named(args[i + 1])
            isForced = true
        }
        #endif
    }

    /// DEBUG perf override active: profile changes do not replace the theme.
    private var isForced = false

    func apply(_ theme: AppTheme) {
        if current.name != theme.name { current = theme }
        UserDefaults.standard.set(theme.name, forKey: Self.legacyKey)
    }

    /// Applies the profile's equipped theme (falls back to default when the
    /// theme is no longer owned, e.g. after a refunded premium skin).
    func apply(profile: PlayerProfile) {
        guard !isForced else { return }
        apply(Self.resolve(profile.equippedTheme, profile: profile))
    }

    static func resolve(_ name: String, profile: PlayerProfile?) -> AppTheme {
        let theme = AppTheme.named(name)
        guard theme.name != "default" else { return theme }
        let owned = profile?.ownedItems.contains(ShopItem.themeID(forName: theme.name)) ?? true
        return owned ? theme : .default
    }
}
