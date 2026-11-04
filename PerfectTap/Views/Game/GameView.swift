import SwiftUI

// MARK: - GameView (ported from Game.jsx)
struct GameView: View {
    let mode: GameMode
    @EnvironmentObject var router: AppRouter
    @EnvironmentObject var themeManager: ThemeManager
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var vm = GameViewModel()

    @State private var feedbackID: UUID = UUID()
    @State private var showAccuracy: Bool = false
    @State private var hideAccuracyWork: DispatchWorkItem? = nil
    @State private var showQuitConfirm: Bool = false
    @State private var hasBootstrapped: Bool = false
    @State private var equippedTapFX: String = "fx_default"

    var body: some View {
        ZStack {
            // Background (themed)
            themeManager.current.backgroundColor
                .ignoresSafeArea()

            if case .countdown(let n) = vm.phase {
                countdownOverlay(number: n)
            } else {
                gameContent
            }

            // Particle effects for PERFECT/GREAT
            ParticleEffectView(accuracy: vm.lastTapAccuracy, trigger: feedbackID, equippedFX: equippedTapFX)
                .allowsHitTesting(false)

            if vm.showReviveModal {
                ReviveModalView(
                    mode: mode,
                    onRevive: { vm.acceptRevive() },
                    onDecline: { vm.declineRevive() }
                )
                .transition(.opacity)
            }
        }
        .navigationBarHidden(true)
        .onAppear {
            guard !hasBootstrapped else { return }
            hasBootstrapped = true
            let profile = PlayerProfile.load() ?? PlayerProfile()
            equippedTapFX = profile.equippedTapFX
            vm.soundEngine = SoundEngine.shared
            vm.hapticsEngine = HapticsEngine.shared
            vm.onGameFinished = { [weak router] result in
                // Pop to root first, then push game over — prevents nav stack growth
                router?.popToRoot()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    router?.push(.gameOver(result))
                }
            }
            vm.setup(mode: mode, profile: profile)
            SoundEngine.shared.startBgMusic()
        }
        .onDisappear {
            // Skip cleanup when revive modal/ad flow is active — the view
            // temporarily disappears during full-screen ad presentation.
            guard !vm.showReviveModal else { return }
            vm.cleanup()
            SoundEngine.shared.stopBgMusic()
        }
        // Keyed on a per-tap counter so repeated identical results
        // (PERFECT → PERFECT) still show the popup and particles.
        .onChange(of: vm.tapSequence) { _ in
            withAnimation(.easeOut(duration: 0.15)) {
                showAccuracy = true
            }
            feedbackID = UUID()
            // Cancel previous hide timer — prevents stacking dozens of asyncAfter timers
            hideAccuracyWork?.cancel()
            let work = DispatchWorkItem { showAccuracy = false }
            hideAccuracyWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7, execute: work)
        }
        .onChange(of: scenePhase) { phase in
            switch phase {
            case .inactive, .background:
                vm.appDidMoveToBackground()
            case .active:
                vm.appDidBecomeActive()
            @unknown default:
                break
            }
        }
        // Input is handled by the TAP button only (not the whole screen)
        .alert("Quit Game?", isPresented: $showQuitConfirm) {
            Button("Cancel", role: .cancel) { }
            Button("Quit", role: .destructive) { vm.quit() }
        } message: {
            Text("Your progress will be lost.")
        }
    }

    // MARK: - Main game content
    private var gameContent: some View {
        VStack(spacing: 0) {
            // Top HUD (hidden in Focus mode)
            if !mode.hidesHUD {
                VStack(spacing: 8) {
                    if mode != .classic {
                        modeLabelView
                    }
                    HStack(alignment: .top) {
                        if mode == .zen {
                            zenStatsView
                        } else {
                            scoreView
                        }
                        Spacer()
                        if mode.usesLives { livesView }
                        if mode.hasTimer { timerView }
                        if mode.hasQuitButton { quitButton }
                        if mode == .zen { exitButton }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)
            } else {
                // Focus mode: minimal — just a quit button
                HStack {
                    Spacer()
                    quitButton
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)
            }

            Spacer()

            // Center: combo + level + tap bar + feedback
            VStack(spacing: 24) {
                if !mode.hidesHUD && mode != .zen { comboView }

                // TapBarView observes vm.indicatorRelay (separate from GameViewModel)
                // so only the tap bar re-renders at 60fps, not the full GameView
                TapBarView(
                    indicatorRelay: vm.indicatorRelay,
                    theme: themeManager.current,
                    hideZones: mode.hidesZones,
                    perfectZoneScale: vm.tapBarPerfectZoneScale,
                    strictPerfectOnly: mode == .precision
                )
                .frame(maxWidth: 360)
                .padding(.horizontal, 24)

                // Accuracy feedback
                Group {
                    if mode == .focus {
                        Color.clear.frame(height: 40)
                    } else if showAccuracy, let acc = vm.lastTapAccuracy {
                        accuracyFeedback(acc)
                    } else {
                        Color.clear.frame(height: 40)
                    }
                }
                .animation(.easeOut(duration: 0.2), value: showAccuracy)
            }

            Spacer()

            // Tap button
            tapButton
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
        }
    }

    // MARK: - HUD components

    private var modeLabelView: some View {
        HStack(spacing: 6) {
            Text(mode.modeLabel + " MODE")
                .font(.system(size: 11, weight: .black))
                .tracking(3)
                .foregroundStyle(modeGradient)
        }
    }

    private var scoreView: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(vm.score)")
                .font(.system(size: 40, weight: .black, design: .monospaced))
                .foregroundColor(.white)
            HStack(spacing: 8) {
                Text("SCORE")
                    .font(.system(size: 9, weight: .bold))
                    .tracking(3)
                    .foregroundColor(.white.opacity(0.3))
                if mode == .classic || mode == .duel {
                    Text("Lv.\(vm.speedLevel)")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(.white.opacity(0.35))
                }
            }
        }
    }

    private var zenStatsView: some View {
        HStack(spacing: 16) {
            statColumn(value: "\(vm.zenPerfects)", label: "PERFECT", color: Color(red: 0.52, green: 0.98, blue: 0.71))
            statColumn(value: "\(vm.zenGreats)",   label: "GREAT",   color: Color(red: 0.36, green: 0.87, blue: 0.98))
            statColumn(value: "\(vm.zenTotal)",    label: "TOTAL",   color: Color.white.opacity(0.5))
        }
    }

    private func statColumn(value: String, label: String, color: Color) -> some View {
        VStack {
            Text(value).font(.system(size: 24, weight: .black)).foregroundColor(color)
            Text(label).font(.system(size: 9, weight: .bold)).tracking(3).foregroundColor(.white.opacity(0.3))
        }
    }

    private var livesView: some View {
        let maxLives = mode.initialLives ?? 3
        return HStack(spacing: 4) {
            ForEach(0..<maxLives, id: \.self) { i in
                Circle()
                    .frame(width: 10, height: 10)
                    .foregroundColor(i < vm.lives ? Color(red: 0.92, green: 0.27, blue: 0.27) : Color.white.opacity(0.15))
            }
        }
    }

    private var timerView: some View {
        VStack(spacing: 2) {
            Text("\(Int(ceil(vm.timeLeft)))s")
                .font(.system(size: 24, weight: .black, design: .monospaced))
                .foregroundColor(vm.timeLeft <= 10 ? .red : Color(red: 0.98, green: 0.73, blue: 0.26))
            Text("TIME")
                .font(.system(size: 9, weight: .bold)).tracking(3)
                .foregroundColor(.white.opacity(0.3))
        }
    }

    private var comboView: some View {
        VStack(spacing: 4) {
            if vm.combo >= 3 {
                Text("×\(vm.combo)")
                    .font(.system(size: 48, weight: .black))
                    .foregroundStyle(
                        LinearGradient(colors: [themeManager.current.accentColor, themeManager.current.barGradient.1], startPoint: .leading, endPoint: .trailing)
                    )
                    .transition(.scale.combined(with: .opacity))
                    .animation(.spring(response: 0.3, dampingFraction: 0.6), value: vm.combo)
            } else {
                Color.clear.frame(height: 56)
            }
        }
    }

    // MARK: - Accuracy feedback popup
    private func accuracyFeedback(_ acc: TapAccuracy) -> some View {
        VStack(spacing: 0) {
            Text(acc.rawValue)
                .font(.system(size: 22, weight: .black))
                .foregroundColor(accuracyColor(acc))
            if vm.lastTapPoints > 0 {
                Text("+\(vm.lastTapPoints)")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(accuracyColor(acc).opacity(0.7))
            }
        }
        .id(feedbackID)
        .transition(.asymmetric(
            insertion: .offset(y: -10).combined(with: .opacity),
            removal: .offset(y: -20).combined(with: .opacity)
        ))
    }

    private func accuracyColor(_ acc: TapAccuracy) -> Color {
        switch acc {
        case .perfect: return Color(red: 0.76, green: 0.55, blue: 0.99)
        case .great:   return Color(red: 0.29, green: 0.86, blue: 0.50)
        case .good:    return Color(red: 0.98, green: 0.73, blue: 0.26)
        case .miss:    return Color(red: 0.92, green: 0.27, blue: 0.27)
        }
    }

    // MARK: - Tap button (sole gameplay input)
    private var tapButton: some View {
        // Touch-DOWN input: scores the instant the finger lands, using the
        // touch's own timestamp (a SwiftUI Button only fires on release).
        TouchDownTapArea(accessibilityLabel: "TAP!", onTouchDown: { timestamp in
            vm.handleTap(touchTimestamp: timestamp)
        }) {
            RoundedRectangle(cornerRadius: 20)
                .fill(buttonGradient)
                .frame(height: 80)
                .overlay(
                    Text("TAP!")
                        .font(.system(size: 24, weight: .black))
                        .tracking(4)
                        .foregroundColor(.white)
                )
                .shadow(color: modeShadowColor.opacity(0.3), radius: 20)
                .accessibilityHidden(true)
        }
    }

    private var quitButton: some View {
        Button {
            showQuitConfirm = true
        } label: {
            Text("QUIT")
                .font(.system(size: 12, weight: .bold))
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(Color.white.opacity(0.05))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.10)))
                .foregroundColor(.white.opacity(0.4))
                .cornerRadius(10)
        }
    }

    private var exitButton: some View {
        Button { router.popToRoot() } label: {
            Text("EXIT")
                .font(.system(size: 12, weight: .bold))
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(Color.white.opacity(0.05))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.10)))
                .foregroundColor(.white.opacity(0.4))
                .cornerRadius(10)
        }
    }

    // MARK: - Gradients per mode
    private var modeGradient: LinearGradient {
        LinearGradient(colors: modeColors, startPoint: .leading, endPoint: .trailing)
    }

    private var buttonGradient: LinearGradient {
        LinearGradient(colors: modeColors, startPoint: .leading, endPoint: .trailing)
    }

    private var modeColors: [Color] {
        switch mode {
        case .duel:          return [Color(red: 0.957, green: 0.247, blue: 0.369), Color(red: 0.980, green: 0.588, blue: 0.0)]
        case .suddenDeath:   return [Color(red: 0.863, green: 0.149, blue: 0.149), Color(red: 0.957, green: 0.251, blue: 0.369)]
        case .comboFrenzy:   return [Color(red: 0.855, green: 0.275, blue: 0.937), Color(red: 0.588, green: 0.275, blue: 0.855)]
        case .timed:         return [Color(red: 0.957, green: 0.247, blue: 0.369), Color(red: 0.980, green: 0.627, blue: 0.149)]
        case .zen:           return [Color(red: 0.063, green: 0.725, blue: 0.506), Color(red: 0.161, green: 0.678, blue: 0.584)]
        case .endless:       return [Color(red: 0.980, green: 0.451, blue: 0.102), Color(red: 0.961, green: 0.322, blue: 0.624)]
        case .precision:     return [Color(red: 0.220, green: 0.400, blue: 0.980), Color(red: 0.400, green: 0.220, blue: 0.980)]
        case .chaos:         return [Color(red: 0.980, green: 0.200, blue: 0.600), Color(red: 0.980, green: 0.800, blue: 0.200)]
        case .mirror:        return [Color(red: 0.400, green: 0.800, blue: 0.980), Color(red: 0.200, green: 0.400, blue: 0.800)]
        case .invisibleZone: return [Color(red: 0.600, green: 0.600, blue: 0.600), Color(red: 0.300, green: 0.300, blue: 0.400)]
        case .rush:          return [Color(red: 0.980, green: 0.300, blue: 0.100), Color(red: 0.980, green: 0.600, blue: 0.100)]
        case .hardcoreCombo: return [Color(red: 0.980, green: 0.100, blue: 0.100), Color(red: 0.980, green: 0.500, blue: 0.100)]
        case .tinyWindow:    return [Color(red: 0.500, green: 0.100, blue: 0.800), Color(red: 0.800, green: 0.200, blue: 0.600)]
        case .focus:         return [Color(red: 0.300, green: 0.300, blue: 0.350), Color(red: 0.500, green: 0.500, blue: 0.550)]
        default:             return [themeManager.current.barGradient.0, themeManager.current.barGradient.1]
        }
    }

    private var modeShadowColor: Color { modeColors.first ?? .purple }

    // MARK: - Countdown overlay
    private func countdownOverlay(number: Int) -> some View {
        ZStack {
            Color.black.opacity(0.8).ignoresSafeArea()
            VStack(spacing: 16) {
                Text("\(number)")
                    .font(.system(size: 120, weight: .black))
                    .foregroundStyle(modeGradient)
                    .transition(.asymmetric(
                        insertion: .scale(scale: 2.0).combined(with: .opacity),
                        removal: .scale(scale: 0.5).combined(with: .opacity)
                    ))
                    .id(number)
                    .animation(.easeOut(duration: 0.25), value: number)

                Text(countdownSubtext)
                    .font(.system(size: 16))
                    .tracking(4)
                    .foregroundColor(.white.opacity(0.4))
            }
        }
    }

    private var countdownSubtext: String {
        switch mode {
        case .suddenDeath:   return "ONE MISS. NO REVIVE"
        case .comboFrenzy:   return "CHAIN IT UP"
        case .timed:         return "60-SECOND SPRINT"
        case .zen:           return "RELAX"
        case .endless:       return "SURVIVE"
        case .precision:     return "PERFECTS ONLY"
        case .chaos:         return "EXPECT ANYTHING"
        case .mirror:        return "STAY SHARP"
        case .invisibleZone: return "TRUST YOUR FEEL"
        case .rush:          return "30 SECONDS"
        case .hardcoreCombo: return "DON'T BREAK"
        case .tinyWindow:    return "TINY TARGET"
        case .focus:         return "BREATHE • NO SCORE"
        default:             return "GET READY"
        }
    }
}

// MARK: - Tap button press style (scale + opacity feedback)
struct TapButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1.0)
            .opacity(configuration.isPressed ? 0.85 : 1.0)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
    }
}
