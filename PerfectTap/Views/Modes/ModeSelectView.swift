import SwiftUI

// MARK: - ModeSelectView
struct ModeSelectView: View {
    @EnvironmentObject var router: AppRouter
    @State private var profile: PlayerProfile = PlayerProfile.load() ?? PlayerProfile()

    var body: some View {
        ZStack {
            Color(red: 0.039, green: 0.039, blue: 0.059).ignoresSafeArea()

            VStack(spacing: 0) {
                // Header
                HStack {
                    Button { router.pop() } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.white.opacity(0.6))
                            .padding(12)
                            .background(Color.white.opacity(0.05))
                            .clipShape(Circle())
                    }
                    Spacer()
                    Text("SELECT MODE")
                        .font(.system(size: 14, weight: .black))
                        .tracking(4)
                        .foregroundColor(.white)
                    Spacer()
                    Color.clear.frame(width: 44, height: 44)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)

                ScrollView(showsIndicators: false) {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        ForEach(GameMode.selectableModes, id: \.self) { mode in
                            ModeCardView(mode: mode, bestScore: profile.bestScore(for: mode), hasPlayed: profile.bestScore(for: mode) > 0 || mode == .classic) {
                                router.push(.game(mode))
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 40)
                }
            }
        }
        .navigationBarHidden(true)
        .onAppear {
            profile = PlayerProfile.load() ?? PlayerProfile()
        }
    }
}

// MARK: - Mode card
private struct ModeCardView: View {
    let mode: GameMode
    let bestScore: Int
    let hasPlayed: Bool
    let action: () -> Void

    var body: some View {
        Button(action: {
            DuelContext.clear()
            AnalyticsService.logModeSelected(mode: mode.rawValue)
            action()
        }) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(mode.emoji)
                        .font(.system(size: 26))
                    Spacer()
                    // NEW badge for unplayed modes
                    if !hasPlayed && mode != .zen {
                        Text("NEW")
                            .font(.system(size: 8, weight: .black))
                            .tracking(1.5)
                            .foregroundColor(.green)
                            .padding(.horizontal, 6).padding(.vertical, 3)
                            .background(Color.green.opacity(0.15))
                            .clipShape(Capsule())
                    }
                    // Difficulty tag
                    if let tag = mode.difficultyTag {
                        Text(tag)
                            .font(.system(size: 8, weight: .black))
                            .tracking(1.5)
                            .foregroundColor(tagColor(tag))
                            .padding(.horizontal, 6).padding(.vertical, 3)
                            .background(tagColor(tag).opacity(0.15))
                            .clipShape(Capsule())
                    }
                }

                Text(mode.displayName.uppercased())
                    .font(.system(size: 14, weight: .black))
                    .tracking(1)
                    .foregroundColor(.white)

                Text(mode.description)
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.45))
                    .fixedSize(horizontal: false, vertical: true)
                    .lineSpacing(2)
                    .lineLimit(2)

                // Gameplay tip — explains the unique difficulty mechanic
                if let tip = mode.tip {
                    HStack(spacing: 4) {
                        Image(systemName: "lightbulb.fill")
                            .font(.system(size: 8))
                        Text(tip)
                            .font(.system(size: 9, weight: .medium))
                            .lineLimit(1)
                    }
                    .foregroundColor(accentColor.opacity(0.7))
                }

                // Coins badge for Classic mode
                if mode.earnCoins && mode != .duel {
                    HStack(spacing: 4) {
                        Image(systemName: "dollarsign.circle.fill")
                            .font(.system(size: 8))
                        Text("EARNS COINS")
                            .font(.system(size: 9, weight: .bold))
                    }
                    .foregroundColor(Color(red: 0.98, green: 0.73, blue: 0.26).opacity(0.7))
                }

                // Best score
                if bestScore > 0 && mode.trackScore {
                    HStack(spacing: 4) {
                        Image(systemName: "trophy.fill")
                            .font(.system(size: 8))
                        Text("\(bestScore)")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                    }
                    .foregroundColor(.yellow.opacity(0.6))
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(mode == .classic ? accentColor.opacity(0.06) : Color.white.opacity(0.04))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18)
                            .stroke(accentColor.opacity(mode == .classic ? 0.4 : 0.20))
                    )
            )
        }
        .buttonStyle(PressedButtonStyle())
    }

    private func tagColor(_ tag: String) -> Color {
        switch tag {
        case "HARD":    return .red
        case "INTENSE": return Color(red: 0.98, green: 0.45, blue: 0.10)
        case "TRICKY":  return Color(red: 0.40, green: 0.80, blue: 0.98)
        default:        return .white
        }
    }

    private var accentColor: Color {
        switch mode {
        case .classic:       return Color(red: 0.59, green: 0.28, blue: 0.98)
        case .endless:       return Color(red: 0.98, green: 0.45, blue: 0.10)
        case .timed:         return Color(red: 0.95, green: 0.24, blue: 0.37)
        case .suddenDeath:   return Color(red: 0.86, green: 0.15, blue: 0.15)
        case .comboFrenzy:   return Color(red: 0.85, green: 0.28, blue: 0.94)
        case .zen:           return Color(red: 0.06, green: 0.73, blue: 0.51)
        case .precision:     return Color(red: 0.22, green: 0.40, blue: 0.98)
        case .chaos:         return Color(red: 0.98, green: 0.20, blue: 0.60)
        case .mirror:        return Color(red: 0.40, green: 0.80, blue: 0.98)
        case .invisibleZone: return Color(red: 0.50, green: 0.50, blue: 0.55)
        case .rush:          return Color(red: 0.98, green: 0.40, blue: 0.10)
        case .hardcoreCombo: return Color(red: 0.98, green: 0.20, blue: 0.10)
        case .tinyWindow:    return Color(red: 0.60, green: 0.15, blue: 0.80)
        case .focus:         return Color(red: 0.40, green: 0.40, blue: 0.45)
        default:             return .purple
        }
    }
}

struct PressedButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.6), value: configuration.isPressed)
    }
}
