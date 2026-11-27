import SwiftUI

// MARK: - GameView (ported from Game.jsx)
struct GameView: View {
    let mode: GameMode
    @EnvironmentObject var router: AppRouter
    @EnvironmentObject var themeManager: ThemeManager
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.effectsLevel) private var effects
    @StateObject private var vm = GameViewModel()

    @State private var feedbackID: UUID = UUID()
    @State private var showAccuracy: Bool = false
    @State private var hideAccuracyWork: DispatchWorkItem? = nil
    @State private var showQuitConfirm: Bool = false
    @State private var hasBootstrapped: Bool = false
    @State private var equippedTapFX: String = "fx_default"
    /// Equipped cosmetics, resolved once per round at bootstrap (never per tap).
    @State private var cosmetics: ResolvedCosmetics = .defaults
    @State private var tapEffectTrigger: CosmeticEffectTrigger? = nil
    @State private var lifeLostTrigger: CosmeticEffectTrigger? = nil
    @State private var cosmeticEffectSequence: Int = 0
    /// Lives as of the last scored tap, to detect a life lost on this tap.
    @State private var trackedLives: Int = 0

    var body: some View {
        ZStack {
            // Background (themed)
            themeManager.current.backgroundColor
                .ignoresSafeArea()

            // gameContent stays mounted under the countdown overlay. Swapping it
            // in at GO built the tap bar / HUD for the first time on the first
            // frame of play (measured: one ~620–720 ms stall right at GO in the
            // first round after launch, docs/perf). Now it is built once, behind
            // the 3-2-1, and never rebuilt at GO or after a resume countdown.
            gameContent
                .accessibilityHidden(isCountingDown)

            if case .countdown(let n) = vm.phase {
                countdownOverlay(number: n)
            }

            // Particle effects for PERFECT/GREAT (Effects setting: Full only).
            // Kept exactly as before while the Perfect Effect slot is the
            // default "Classic Particles"; a themed Perfect Effect replaces them.
            if effects.showsParticles && usesLegacyParticles {
                ParticleEffectView(accuracy: legacyParticleAccuracy, trigger: feedbackID, equippedFX: equippedTapFX,
                                   themeColors: themeManager.current.particleColors)
                    .allowsHitTesting(false)
            }

            // Themed cosmetic effects (not mounted at all for the default loadout).
            if hasThemedEffects {
                cosmeticEffectLayers
            }

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
        // The TAP button sits just above the home indicator: make the first
        // edge swipe not leave/pause the game (each pause forced a 3-2-1 that
        // felt like a freeze).
        .defersSystemGestures(on: .bottom)
        .persistentSystemOverlays(.hidden)
        .onAppear {
            guard !hasBootstrapped else {
                // Re-appeared after a full-screen cover: restart a stopped clock.
                vm.resumeAfterViewReappeared()
                if vm.phase != .finished { SoundEngine.shared.startBgMusic() }
                return
            }
            hasBootstrapped = true
            let bootstrap = Perf.begin("game.viewBootstrap")
            defer { bootstrap.end() }
            let profile = PlayerProfile.load() ?? PlayerProfile()
            equippedTapFX = profile.equippedTapFX
            // One resolve per round: picks up purchases/refunds/account switches
            // made since the last round; image lookups happen here, not on tap.
            let store = CosmeticLoadoutStore.shared
            store.refresh()
            cosmetics = store.resolved
            CosmeticImageCache.shared.preload(cosmetics)
            CosmeticSpriteCache.shared.preload(cosmetics)   // effect sprites: never loaded on the tap path
            vm.soundEngine = SoundEngine.shared
            vm.hapticsEngine = HapticsEngine.shared
            vm.onGameFinished = { [weak router] result in
                // Single stack replacement: bounded stack, Home is never re-shown.
                router?.replaceStack(with: [.gameOver(result)])
            }
            vm.setup(mode: mode, profile: profile, cosmetics: cosmetics)
            trackedLives = vm.lives
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
            withAnimation(effects.animatesFeedback ? .easeOut(duration: 0.15) : nil) {
                showAccuracy = true
            }
            feedbackID = UUID()
            // Cancel previous hide timer — prevents stacking dozens of asyncAfter timers
            hideAccuracyWork?.cancel()
            let work = DispatchWorkItem { showAccuracy = false }
            hideAccuracyWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7, execute: work)
            emitCosmeticEffects()
        }
        // Revive refills lives: re-baseline so the refill isn't seen as a change.
        .onChange(of: vm.lives) { newLives in
            if newLives > trackedLives { trackedLives = newLives }
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

    private var isCountingDown: Bool {
        if case .countdown = vm.phase { return true }
        return false
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
                        } else if mode == .practice {
                            practiceHeaderView
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
                // Minimal mode: no score/combo. Lives stay visible — they
                // were hidden before, so a run could end without warning.
                HStack(spacing: 12) {
                    Spacer()
                    if mode.usesLives { livesView }
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
                    glowStrength: effects.glowStrength,
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
                .animation(effects.animatesFeedback ? .easeOut(duration: 0.2) : nil, value: showAccuracy)
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

    private var practiceHeaderView: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("PRACTICE")
                .font(.system(size: 22, weight: .black))
                .foregroundColor(.white)
            Text("\(Int(mode.timerDuration / 60)) MIN • FIXED PACE")
                .font(.system(size: 9, weight: .bold))
                .tracking(2)
                .foregroundColor(.white.opacity(0.35))
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
        CosmeticLivesView(item: cosmetics.item(for: .lifeIcon), maxLives: mode.initialLives ?? 3, lives: vm.lives)
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
                    .transition(effects.animatesFeedback ? .scale.combined(with: .opacity) : .opacity)
                    .animation(effects.animatesFeedback ? .spring(response: 0.3, dampingFraction: 0.6) : nil, value: vm.combo)
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
            if mode == .practice, let ms = vm.lastTapErrorMs {
                // Knowledge of results: how far from centre, in milliseconds.
                Text(Self.formatError(ms))
                    .font(.system(size: 12, weight: .heavy, design: .monospaced))
                    .foregroundColor(.white.opacity(0.6))
            } else if let timing = vm.lastTapTiming {
                // Coaching hint: which way to adjust next time.
                Text(timing.rawValue)
                    .font(.system(size: 11, weight: .heavy))
                    .tracking(2)
                    .foregroundColor(.white.opacity(0.55))
            }
            if vm.lastTapPoints > 0 {
                Text("+\(vm.lastTapPoints)")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(accuracyColor(acc).opacity(0.7))
            }
        }
        .id(feedbackID)
        .transition(effects.animatesFeedback
            ? .asymmetric(insertion: .offset(y: -10).combined(with: .opacity),
                          removal: .offset(y: -20).combined(with: .opacity))
            : .opacity)
    }

    /// "12 ms LATE" / "8 ms EARLY" / "ON TIME" (|error| < 1 ms).
    static func formatError(_ ms: Double) -> String {
        let rounded = Int(abs(ms).rounded())
        if rounded == 0 { return "ON TIME" }
        return "\(rounded) ms \(ms < 0 ? "EARLY" : "LATE")"
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
        //
        // The skin only draws; the hit area is still this 80 pt full-width
        // area. The default skin keeps the generic press feedback it always
        // had, a themed skin draws its own press from the same touch state.
        let skin = cosmetics.item(for: .tapButton)
        return TouchDownTapArea(accessibilityLabel: "TAP!", appliesDefaultPressStyle: skin.isDefault,
                                onTouchDown: { timestamp in
            vm.handleTap(touchTimestamp: timestamp)
        }) { isPressed in
            CosmeticTapButtonSkin(item: skin, fallbackColors: modeColors, isPressed: isPressed)
                .shadow(color: tapButtonShadowColor(for: skin).opacity(0.3),
                        radius: skin.isDefault ? 20 : 20 * effects.glowStrength)
                .accessibilityHidden(true)
        }
    }

    private func tapButtonShadowColor(for skin: CosmeticItem) -> Color {
        guard !skin.isDefault, let first = skin.assets.palette.first else { return modeShadowColor }
        return first.color
    }

    // MARK: - Cosmetic effects

    /// Default Perfect Effect = the pre-Studio ParticleEffectView.
    private var usesLegacyParticles: Bool {
        cosmetics.item(for: .perfectEffect).assets.effectStyle == .legacyParticles
    }

    /// Accuracy fed to the legacy particles. With a themed Tap Effect, GREAT is
    /// drawn by that effect, so the legacy view only keeps PERFECT (one burst
    /// per tap, never two stacked).
    private var legacyParticleAccuracy: TapAccuracy? {
        guard hasThemedStyle(.tapEffect) else { return vm.lastTapAccuracy }
        return vm.lastTapAccuracy == .perfect ? .perfect : nil
    }

    private func hasThemedStyle(_ slot: CosmeticSlot) -> Bool {
        switch cosmetics.item(for: slot).assets.effectStyle {
        case nil, .some(CosmeticEffectStyle.none), .some(.legacyParticles): return false
        default: return true
        }
    }

    private var hasThemedEffects: Bool {
        [CosmeticSlot.tapEffect, .perfectEffect, .missEffect, .lifeLostEffect].contains(where: hasThemedStyle)
    }

    /// Accuracy events burst from the TAP button (short, low on screen, so the
    /// timing zones stay readable); a lost life bursts at the lives HUD.
    @ViewBuilder private var cosmeticEffectLayers: some View {
        CosmeticEffectLayer(resolved: cosmetics, trigger: tapEffectTrigger,
                            origin: UnitPoint(x: 0.5, y: 0.86))
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        CosmeticEffectLayer(resolved: cosmetics, trigger: lifeLostTrigger,
                            origin: mode.usesLives ? UnitPoint(x: 0.82, y: 0.08) : UnitPoint(x: 0.5, y: 0.86))
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    /// Called once per scored tap (after scoring). Emits the accuracy event and,
    /// when this tap cost a life, a separate life-lost event on its own layer.
    private func emitCosmeticEffects() {
        let lostLife = vm.lives < trackedLives
        trackedLives = vm.lives
        guard hasThemedEffects, let accuracy = vm.lastTapAccuracy else { return }
        let event = CosmeticEvent(accuracy: accuracy)
        if let slot = event.effectSlot, hasThemedStyle(slot) {
            cosmeticEffectSequence &+= 1
            tapEffectTrigger = CosmeticEffectTrigger(event: event, sequence: cosmeticEffectSequence)
        }
        if lostLife, hasThemedStyle(.lifeLostEffect) {
            cosmeticEffectSequence &+= 1
            lifeLostTrigger = CosmeticEffectTrigger(event: .lifeLost, sequence: cosmeticEffectSequence)
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
        case .practice:      return [Color(red: 0.130, green: 0.600, blue: 0.680), Color(red: 0.220, green: 0.480, blue: 0.760)]
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
                    .transition(effects.animatesFeedback
                        ? .asymmetric(insertion: .scale(scale: 2.0).combined(with: .opacity),
                                      removal: .scale(scale: 0.5).combined(with: .opacity))
                        : .opacity)
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
        case .focus:         return "NO SCORE"
        case .practice:      return "SAME PACE EVERY TIME"
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
