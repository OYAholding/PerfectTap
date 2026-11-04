import SwiftUI

// MARK: - ThemeManager (@EnvironmentObject injected at root)
final class ThemeManager: ObservableObject {
    @Published var current: AppTheme = .default

    init() {
        let saved = UserDefaults.standard.string(forKey: "perfecttap_theme") ?? "default"
        current = AppTheme.named(saved)
    }

    func apply(_ theme: AppTheme) {
        current = theme
        UserDefaults.standard.set(theme.name, forKey: "perfecttap_theme")
    }
}
