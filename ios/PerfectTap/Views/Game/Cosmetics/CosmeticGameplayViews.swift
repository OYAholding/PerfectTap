import SwiftUI

// MARK: - Gameplay cosmetic views (contract stubs — owned by Agent A)
//
// Used by GameView and by the Preview Studio, so the preview is the real thing.

/// Visual of the wide TAP button. Never sets its own hit area: the caller keeps
/// `TouchDownTapArea` and the 80 pt height / full width unchanged. The TAP label
/// is native text, not part of the artwork.
struct CosmeticTapButtonSkin: View {
    let item: CosmeticItem
    /// Colours of the pre-Studio button (mode gradient) — used by the default skin.
    let fallbackColors: [Color]
    var isPressed: Bool = false
    var label: String = "TAP!"
    var height: CGFloat = 80

    var body: some View {
        RoundedRectangle(cornerRadius: 20)
            .fill(LinearGradient(colors: fallbackColors, startPoint: .leading, endPoint: .trailing))
            .frame(height: height)
            .overlay(Text(label).font(.system(size: 24, weight: .black)).tracking(4).foregroundColor(.white))
    }
}

/// Lives indicator for the HUD (upper right).
struct CosmeticLivesView: View {
    let item: CosmeticItem
    let maxLives: Int
    let lives: Int

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<maxLives, id: \.self) { i in
                Circle()
                    .frame(width: 10, height: 10)
                    .foregroundColor(i < lives ? Color(red: 0.92, green: 0.27, blue: 0.27) : Color.white.opacity(0.15))
            }
        }
    }
}
