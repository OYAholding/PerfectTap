import SwiftUI

// MARK: - Tutorial / Onboarding (shown on first launch)
struct TutorialView: View {
    @State private var currentPage = 0
    @State private var starterItemID = "avatar_cool"
    var onDismiss: () -> Void

    private static let starterMarker = "grant_starter_v1"
    private static let starterItems = ["theme_neon", "fx_ripple", "avatar_cool"]

    private let pages: [(icon: String, title: String, body: String)] = [
        ("🎯", "Welcome to PerfectTap!",
         "Tap when the indicator is at the center of the bar to score points. The closer to center, the higher your score!"),
        ("💜", "Accuracy Zones",
         "PERFECT (±4%) = 100pts\nGREAT (±10%) = 70pts\nGOOD (±20%) = 40pts\nMISS = 0pts + lose a life"),
        ("🔗", "Build Combos",
         "Hit PERFECT or GREAT to build combos. At 3× you get 1.5× score, at 5× you get 2× score. Miss and the combo resets!"),
        ("🪙", "Earn Coins",
         "Classic and Duel earn coins, and quests, challenges and daily rewards add more. Spend them in the Shop on themes, particle effects, and avatars to customize your game."),
        ("🎮", "14 Game Modes",
         "Classic, Endless, Timed, Sudden Death, Combo Frenzy, Zen, Precision, Chaos, Mirror, Invisible Zone, Rush, Hardcore Combo, Tiny Window, and Focus. Each has unique mechanics!"),
    ]

    var body: some View {
        ZStack {
            Color(red: 0.039, green: 0.039, blue: 0.059).ignoresSafeArea()

            VStack(spacing: 0) {
                // Skip button
                HStack {
                    Spacer()
                    Button("Skip") { finish() }
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white.opacity(0.4))
                        .padding(20)
                }

                Spacer()

                // Page content
                TabView(selection: $currentPage) {
                    ForEach(0..<pages.count, id: \.self) { i in
                        VStack(spacing: 24) {
                            Text(pages[i].icon).font(.system(size: 64))
                            Text(pages[i].title)
                                .font(.system(size: 24, weight: .black))
                                .foregroundColor(.white)
                                .multilineTextAlignment(.center)
                            Text(pages[i].body)
                                .font(.system(size: 15))
                                .foregroundColor(.white.opacity(0.6))
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 32)
                        }
                        .tag(i)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .always))
                .frame(height: 340)

                if currentPage == pages.count - 1 {
                    starterPicker
                        .padding(.horizontal, 24)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }

                Spacer()

                // Next / Start button
                Button {
                    if currentPage < pages.count - 1 {
                        withAnimation { currentPage += 1 }
                    } else {
                        finish()
                    }
                } label: {
                    Text(currentPage < pages.count - 1 ? "NEXT" : "LET'S GO!")
                        .font(.system(size: 18, weight: .black))
                        .tracking(2)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .background(
                            LinearGradient(
                                colors: [Color(red: 0.47, green: 0.18, blue: 0.85), Color(red: 0.20, green: 0.55, blue: 0.96)],
                                startPoint: .leading, endPoint: .trailing
                            )
                        )
                        .cornerRadius(20)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
            }
        }
    }

    private func finish() {
        _ = EconomyManager.shared.updateProfile { profile in
            guard !profile.ownedItems.contains(Self.starterMarker) else { return }
            profile.ownedItems.append(Self.starterMarker)
            if !profile.ownedItems.contains(starterItemID) {
                profile.ownedItems.append(starterItemID)
            }
        }
        UserDefaults.standard.set(true, forKey: "perfecttap_tutorial_done")
        onDismiss()
    }

    private var starterPicker: some View {
        VStack(spacing: 10) {
            Text("CHOOSE A FREE STARTER COSMETIC")
                .font(.system(size: 11, weight: .black))
                .tracking(1.5)
                .foregroundColor(.white.opacity(0.65))
            HStack(spacing: 10) {
                ForEach(Self.starterItems, id: \.self) { id in
                    if let item = ShopItem.item(id: id) {
                        Button {
                            starterItemID = id
                        } label: {
                            VStack(spacing: 5) {
                                Text(item.icon).font(.system(size: 24))
                                Text(item.name)
                                    .font(.system(size: 10, weight: .bold))
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(starterItemID == id ? Color.purple.opacity(0.45) : Color.white.opacity(0.06))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(starterItemID == id ? Color.purple : Color.white.opacity(0.1), lineWidth: 1)
                            )
                            .cornerRadius(12)
                        }
                        .accessibilityLabel("\(item.name), free starter cosmetic")
                        .accessibilityAddTraits(starterItemID == id ? .isSelected : [])
                    }
                }
            }
        }
    }
}
