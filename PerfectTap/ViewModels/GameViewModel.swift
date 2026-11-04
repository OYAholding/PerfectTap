import Foundation
import QuartzCore
import Combine

// TapAccuracy lives in Utils/TimingEngine.swift (pure, unit-tested).

// MARK: - Game phase
enum GamePhase {
    case countdown(Int)   // 3, 2, 1
    case playing
    case paused           // revive modal showing
    case finished
}

// MARK: - Result passed to GameOverView
struct GameResult {
    let id = UUID()   // unique ID for NavigationStack hashing
    var score: Int
    var maxCombo: Int
    var mode: GameMode
    var coinsEarned: Int
    var xpEarned: Int
    var leveledUp: Int?           // new level number if leveled up
    var newAchievements: [Achievement]
    var isNewBest: Bool
    var isDuelSession: Bool = false
}

// MARK: - Indicator relay (separate ObservableObject for 60fps updates)
// Only TapBarView observes this, so only the tap bar re-renders at 60fps.
// GameView does NOT observe this, preventing full-view re-renders every frame.
final class IndicatorRelay: ObservableObject {
    @Published var position: Double = 0.0
}

// MARK: - GameViewModel (core game state machine)
@MainActor
final class GameViewModel: ObservableObject {

    // MARK: Published state (drives SwiftUI views — updated sparingly)
    @Published var phase: GamePhase = .countdown(3)
    @Published var score: Int = 0
    @Published var combo: Int = 0
    @Published var lives: Int = 3
    @Published var timeLeft: Double = GameConfig.timedDuration
    @Published var lastTapAccuracy: TapAccuracy? = nil
    @Published var lastTapPoints: Int = 0
    /// Increments on every scored tap — drives feedback even when the
    /// accuracy repeats (onChange(of: lastTapAccuracy) misses PERFECT→PERFECT).
    @Published private(set) var tapSequence: Int = 0
    @Published var showReviveModal: Bool = false
    @Published var zenPerfects: Int = 0
    @Published var zenGreats: Int = 0
    @Published var zenTotal: Int = 0
    @Published var speedLevel: Int = 1
    @Published var tapBarPerfectZoneScale: Double = 1.0

    // MARK: Indicator position — separate observable
    // Updated at 60fps by CADisplayLink. Uses a separate IndicatorRelay object
    // so only TapBarView re-renders each frame, not the entire GameView.
    let indicatorRelay = IndicatorRelay()
    var indicatorPosition: Double { indicatorRelay.position }

    // MARK: Private state (refs for use inside CADisplayLink — no re-renders)
    private var positionRef: Double = 0.0
    private var directionRef: Double = 1.0
    private var speedRef: Double = 1.2
    private var livesRef: Int = 3
    private var scoreRef: Int = 0
    private var comboRef: Int = 0
    private var maxComboRef: Int = 0
    private var tapsRef: Int = 0
    private var perfectStreakRef: Int = 0
    private var missCountRef: Int = 0
    private var totalTapsRef: Int = 0
    private var perfectCountRef: Int = 0
    private var gameOverRef: Bool = false
    private var pausedRef: Bool = false
    private var hasUsedReviveRef: Bool = false
    private var perfectsInFirst20Ref: Int = 0
    private var didFinalizeRef: Bool = false  // guard against double finalize

    // Timing — use a proxy object to break retain cycle
    private var displayLink: CADisplayLink?
    private var displayLinkProxy: DisplayLinkProxy?
    private var lastTimestamp: CFTimeInterval = 0
    private var lastFrameDuration: CFTimeInterval = 1.0 / 60.0
    private var gameStartTime: CFTimeInterval = 0
    private var timedStartTime: CFTimeInterval = 0
    private var lifecyclePauseStart: CFTimeInterval? = nil
    private var lifecyclePausedRef: Bool = false

    // Mode
    private(set) var mode: GameMode = .classic
    private var scoreMultiplier: Double = 1.0
    private var activeChallenge: Challenge? = nil
    private var duelContext: DuelContext? = nil

    // Completion callback — set by GameView before starting
    var onGameFinished: ((GameResult) -> Void)?

    // Sound & haptics (injected)
    var soundEngine: SoundEngine?
    var hapticsEngine: HapticsEngine?

    // Chaos mode: next tap count at which speed randomizes
    private var chaosNextSpeedChange: Int = 0

    // Dynamic difficulty state
    private var precisionZoneScale: Double = 1.0   // shrinks over taps (Precision mode)
    private var tinyWindowZoneScale: Double = 0.5  // shrinks further (Tiny Window mode)
    private var hardcoreBaseDrift: Double = 0.0    // cumulative base speed decay (Hardcore Combo)
    private var hardcoreBreakShock: Double = 0.0   // temporary speed shock after combo break
    private var hardcorePenaltyTapsRemaining: Int = 0 // temporary tighter perfect window
    private var focusBaseSpeed: Double = 1.1       // decays over time (Focus mode)

    #if DEBUG
    private let perfTickThresholdMs: Double = 5.0
    private let perfTapThresholdMs: Double = 5.0
    #endif

    // MARK: - Setup
    func setup(mode: GameMode, profile: PlayerProfile) {
        self.mode = mode
        self.speedRef = mode.initialSpeed
        self.livesRef = mode.initialLives ?? 999
        self.lives = livesRef
        self.score = 0
        self.scoreRef = 0
        self.combo = 0
        self.comboRef = 0
        self.maxComboRef = 0
        self.timeLeft = mode.hasTimer ? mode.timerDuration : GameConfig.timedDuration
        self.positionRef = 0.0
        self.directionRef = 1.0
        self.gameOverRef = false
        self.pausedRef = false
        self.hasUsedReviveRef = false
        self.didFinalizeRef = false
        self.chaosNextSpeedChange = Int.random(in: 3...6)
        self.precisionZoneScale = 1.0
        self.tinyWindowZoneScale = 0.5
        self.hardcoreBaseDrift = 0.0
        self.hardcoreBreakShock = 0.0
        self.hardcorePenaltyTapsRemaining = 0
        self.focusBaseSpeed = mode.initialSpeed
        self.lifecyclePauseStart = nil
        self.lifecyclePausedRef = false
        syncTapBarPerfectZoneScale()

        // Duel context hardening: only keep context if it matches this launched mode.
        // Also requires a one-shot pending-launch marker set by duel entry points.
        // This blocks stale context from hijacking normal sessions.
        let loadedContext = DuelContext.load()
        let launchedFromDuelIntent = DuelContext.consumePendingLaunchMarker()
        if let loadedContext,
           !loadedContext.duelId.isEmpty,
           loadedContext.mode == mode,
           launchedFromDuelIntent {
            duelContext = loadedContext
        } else {
            duelContext = nil
            if loadedContext != nil {
                DuelContext.clear()
            }
        }

        // Apply boost (classic only)
        if mode == .classic, let boost = profile.boost, !boost.used {
            scoreMultiplier = boost.value
        } else {
            scoreMultiplier = 1.0
        }

        phase = .countdown(3)
        startCountdown()
    }

    // MARK: - Countdown (3 → 2 → 1 → GO)
    private func startCountdown() {
        var count = 3
        soundEngine?.play(.countdown)

        func tick() {
            guard !gameOverRef else { return }
            if count > 0 {
                phase = .countdown(count)
                count -= 1
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                    guard let self, !self.gameOverRef else { return }
                    if count == 0 {
                        self.soundEngine?.play(.countdownGo)
                        self.phase = .playing
                        self.startGameLoop()
                        self.gameStartTime = CACurrentMediaTime()
                        self.timedStartTime = self.gameStartTime
                        AnalyticsService.logGameStart(mode: self.mode.rawValue)
                    } else {
                        self.soundEngine?.play(.countdown)
                        tick()
                    }
                }
            }
        }
        tick()
    }

    // MARK: - CADisplayLink game loop (60fps)
    // Uses DisplayLinkProxy to avoid retain cycle: RunLoop → CADisplayLink → Proxy (weak→ self)
    private func startGameLoop() {
        displayLink?.invalidate()
        lastTimestamp = 0

        let proxy = DisplayLinkProxy { [weak self] link in
            self?.gameLoopTick(link)
        }
        displayLinkProxy = proxy
        let link = CADisplayLink(target: proxy, selector: #selector(DisplayLinkProxy.tick(_:)))
        if #available(iOS 15.0, *) {
            link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 60, preferred: 60)
        } else {
            link.preferredFramesPerSecond = 60
        }
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    private func gameLoopTick(_ link: CADisplayLink) {
        #if DEBUG
        let tickStartedAt = CACurrentMediaTime()
        defer {
            let tickElapsedMs = (CACurrentMediaTime() - tickStartedAt) * 1000
            if tickElapsedMs >= perfTickThresholdMs {
                print("[Perf][GameLoop] \(String(format: "%.2f", tickElapsedMs))ms mode=\(mode.rawValue)")
            }
        }
        #endif

        guard !gameOverRef, !pausedRef else { return }

        let now = link.timestamp
        let frame = link.targetTimestamp - link.timestamp
        if frame > 0, frame < 0.1 { lastFrameDuration = frame }
        if lastTimestamp == 0 { lastTimestamp = now }
        let delta = now - lastTimestamp
        lastTimestamp = now

        // Move indicator (reflects off edges, carrying overshoot)
        let moved = TimingEngine.advance(position: positionRef, direction: directionRef,
                                         dt: delta, speed: speedRef)
        positionRef = moved.position
        directionRef = moved.direction

        // Update position via relay — only TapBarView observes this,
        // so only the tap bar re-renders, not the entire GameView.
        indicatorRelay.position = positionRef

        // Endless: speed ramps over time
        if mode == .endless {
            let elapsed = now - gameStartTime
            speedRef = max(GameConfig.endlessMinSpeed, 1.2 - elapsed * 0.005)
        }

        // Mirror: direction flips increase over time + speed ramp
        if mode == .mirror {
            let elapsed = now - gameStartTime
            let flipChance = min(GameConfig.mirrorFlipCap,
                                 GameConfig.mirrorBaseFlipChance + elapsed * GameConfig.mirrorFlipGrowth)
            if Double.random(in: 0...1) < flipChance {
                directionRef *= -1
            }
            speedRef = max(GameConfig.mirrorSpeedFloor,
                           mode.initialSpeed - elapsed * GameConfig.mirrorSpeedRamp)
        }

        // Focus: oscillating speed (wave pattern)
        if mode == .focus {
            let elapsed = now - gameStartTime
            focusBaseSpeed = max(GameConfig.focusBaseFloor,
                                 mode.initialSpeed - elapsed * GameConfig.focusBaseDecay)
            speedRef = focusBaseSpeed + sin(elapsed * GameConfig.focusOscillationFreq) * GameConfig.focusOscillationAmp
            if speedRef < 0.2 { speedRef = 0.2 }
        }

        // Timed / Rush: count down
        if mode.hasTimer {
            let elapsed = now - timedStartTime
            let duration = mode.timerDuration
            let remaining = max(0, duration - elapsed)
            // Only publish when it changes visually (every ~0.1s) to reduce re-renders
            if abs(timeLeft - remaining) >= 0.09 || remaining <= 0 {
                timeLeft = remaining
            }

            // Timed: speed ramps as time runs out ("Pressure Cooker")
            if mode == .timed {
                let progress = elapsed / duration  // 0→1 over full duration
                speedRef = max(GameConfig.timedSpeedFloor,
                               mode.initialSpeed - progress * GameConfig.timedSpeedRange)
            }

            // Rush: final sprint acceleration in last 10s
            if mode == .rush && remaining <= GameConfig.rushSprintSeconds {
                speedRef = max(GameConfig.rushSprintFloor,
                               mode.initialSpeed - (GameConfig.rushSprintSeconds - remaining) * GameConfig.rushSprintAccel)
            }

            if remaining <= 0 {
                handleTimedEnd()
            }
        }
    }

    // MARK: - Tap handler
    /// - Parameter touchTimestamp: the UITouch timestamp (same clock as
    ///   CADisplayLink: CACurrentMediaTime). When provided, the tap is scored at
    ///   the indicator position the player was actually SEEING when the finger
    ///   landed: touch time minus one frame of display latency, extrapolated
    ///   from the last simulated frame. This removes the random 0–16 ms error
    ///   of "whatever the last tick was" and makes scoring deterministic.
    func handleTap(touchTimestamp: CFTimeInterval? = nil) {
        #if DEBUG
        let tapStartedAt = CACurrentMediaTime()
        defer {
            let tapElapsedMs = (CACurrentMediaTime() - tapStartedAt) * 1000
            if tapElapsedMs >= perfTapThresholdMs {
                print("[Perf][Tap] \(String(format: "%.2f", tapElapsedMs))ms mode=\(mode.rawValue)")
            }
        }
        #endif

        guard case .playing = phase, !gameOverRef, !pausedRef else { return }

        var pos = positionRef
        if let touchTimestamp, lastTimestamp > 0 {
            let seenAt = touchTimestamp - lastFrameDuration * TimingEngine.displayLatencyFrames
            let dt = seenAt - lastTimestamp
            if abs(dt) <= TimingEngine.maxTouchExtrapolation {
                pos = TimingEngine.advance(position: positionRef, direction: directionRef,
                                           dt: dt, speed: speedRef).position
            }
        }

        // Dynamic zone scaling for Precision and Tiny Window modes
        let dynamicPerfectScale: Double
        if mode == .precision {
            dynamicPerfectScale = precisionZoneScale
        } else if mode == .tinyWindow {
            dynamicPerfectScale = tinyWindowZoneScale
        } else if mode == .hardcoreCombo, hardcorePenaltyTapsRemaining > 0 {
            dynamicPerfectScale = GameConfig.hardcorePenaltyPerfectScale
        } else {
            dynamicPerfectScale = mode.perfectZoneScale
        }
        // Zones are fractions of the full bar width from center — the same
        // geometry TapBarView draws (fixes the port bug that halved every window).
        let accuracy = TimingEngine.accuracy(at: pos,
                                             perfectScale: dynamicPerfectScale,
                                             strictPerfectOnly: mode == .precision)
        let points = TimingEngine.basePoints(for: accuracy)

        // Combo
        let prevCombo = comboRef
        if mode == .zen {
            comboRef = 0
        } else if mode == .comboFrenzy {
            comboRef = (accuracy != .miss) ? comboRef + 1 : 0
        } else if mode == .hardcoreCombo {
            comboRef = (accuracy == .perfect || accuracy == .great) ? comboRef + 1 : 0
        } else {
            comboRef = (accuracy == .perfect || accuracy == .great) ? comboRef + 1 : 0
        }
        if comboRef > maxComboRef { maxComboRef = comboRef }
        combo = comboRef
        let didHardcoreBreak = mode == .hardcoreCombo
            && prevCombo >= GameConfig.hardcoreBreakThresholdCombo
            && comboRef == 0

        // Scoring
        let multiplier = GameConfig.comboMultiplier(combo: comboRef, isComboFrenzy: mode == .comboFrenzy)
        let finalPoints = mode.trackScore ? Int(Double(points) * multiplier * scoreMultiplier) : 0
        scoreRef += finalPoints
        if mode.trackScore { score = scoreRef }

        // Zen stats
        if mode == .zen {
            zenTotal += 1
            if accuracy == .perfect { zenPerfects += 1 }
            else if accuracy == .great { zenGreats += 1 }
        }

        // Tracking
        if accuracy == .perfect { perfectStreakRef += 1 } else { perfectStreakRef = 0 }
        if accuracy == .miss    { missCountRef += 1 }
        totalTapsRef += 1
        if accuracy == .perfect { perfectCountRef += 1 }
        if totalTapsRef <= 20 && accuracy == .perfect { perfectsInFirst20Ref += 1 }

        // Speed
        if mode.trackScore {
            tapsRef += 1

            switch mode {
            case .suddenDeath:
                if tapsRef % GameConfig.suddenSpeedEvery == 0 {
                    speedRef = max(GameConfig.minSpeed, speedRef - GameConfig.suddenSpeedStep)
                }

            case .classic, .duel:
                if tapsRef % GameConfig.classicSpeedEvery == 0 {
                    speedRef = max(GameConfig.minSpeed + 0.15, speedRef - GameConfig.classicSpeedStep)
                }

            case .chaos:
                if tapsRef >= chaosNextSpeedChange {
                    speedRef = Double.random(in: 0.35...1.4)
                    chaosNextSpeedChange = tapsRef + Int.random(in: 3...6)
                }

            case .comboFrenzy:
                // Speed tied to combo — higher combo = faster
                speedRef = max(GameConfig.comboFrenzySpeedFloor,
                               mode.initialSpeed - Double(comboRef) * GameConfig.comboFrenzySpeedPerCombo)

            case .precision:
                // Zone shrinks every N taps
                if tapsRef % GameConfig.precisionShrinkEvery == 0 {
                    precisionZoneScale = max(GameConfig.precisionShrinkFloor,
                                             precisionZoneScale - GameConfig.precisionShrinkStep)
                }
                // Gentle speed increase
                if tapsRef % GameConfig.precisionSpeedEvery == 0 {
                    speedRef = max(GameConfig.precisionSpeedFloor,
                                   speedRef - GameConfig.precisionSpeedStep)
                }

            case .invisibleZone:
                // Classic-like speed ramp (hidden zones + speed = brutal)
                if tapsRef % GameConfig.invisibleSpeedEvery == 0 {
                    speedRef = max(GameConfig.invisibleSpeedFloor,
                                   speedRef - GameConfig.invisibleSpeedStep)
                }

            case .hardcoreCombo:
                // Combo break punishment: immediate speed shock + temporary tighter PERFECT window.
                if didHardcoreBreak {
                    hardcoreBreakShock = min(0.45, hardcoreBreakShock + GameConfig.hardcoreBreakShockStep)
                    hardcorePenaltyTapsRemaining = GameConfig.hardcorePenaltyTaps
                } else if hardcorePenaltyTapsRemaining > 0 {
                    hardcorePenaltyTapsRemaining -= 1
                }

                // Base speed slowly decays
                if tapsRef % GameConfig.hardcoreBaseDecayEvery == 0 {
                    hardcoreBaseDrift += GameConfig.hardcoreBaseDecayStep
                }
                // Speed from combo + base drift + break shock.
                let baseSpeed = mode.initialSpeed - hardcoreBaseDrift
                speedRef = max(GameConfig.hardcoreSpeedFloor,
                               baseSpeed
                               - Double(comboRef) * GameConfig.hardcoreSpeedPerCombo
                               - hardcoreBreakShock)
                if hardcoreBreakShock > 0, !didHardcoreBreak {
                    hardcoreBreakShock = max(0, hardcoreBreakShock - GameConfig.hardcoreBreakShockDecay)
                }

            case .tinyWindow:
                // Zone keeps shrinking
                if tapsRef % GameConfig.tinyWindowShrinkEvery == 0 {
                    tinyWindowZoneScale = max(GameConfig.tinyWindowShrinkFloor,
                                              tinyWindowZoneScale - GameConfig.tinyWindowShrinkStep)
                }
                // Speed ramps
                if tapsRef % GameConfig.tinyWindowSpeedEvery == 0 {
                    speedRef = max(GameConfig.tinyWindowSpeedFloor,
                                   speedRef - GameConfig.tinyWindowSpeedStep)
                }

            default:
                break  // Timed, Rush, Mirror, Focus, Endless handled in gameLoopTick
            }

            let newLevel = min(20, (tapsRef / GameConfig.classicSpeedEvery) + 1)
            if newLevel != speedLevel { speedLevel = newLevel }
        }
        syncTapBarPerfectZoneScale()

        // Lives
        if accuracy == .miss && mode.usesLives {
            livesRef -= 1
            lives = livesRef
            if livesRef <= 0 { handleOutOfLives() }
        }

        // Sound + haptics
        if didHardcoreBreak {
            soundEngine?.play(.comboBreak)
            hapticsEngine?.impact(.heavy)
        } else if accuracy == .miss && prevCombo >= 3 {
            soundEngine?.play(.comboBreak)
            hapticsEngine?.impact(.heavy)
        } else if accuracy == .miss {
            soundEngine?.play(.miss)
            hapticsEngine?.impact(.rigid)
        } else if comboRef == 5 || comboRef == 10 || comboRef == 20 {
            soundEngine?.play(.comboMilestone)
            hapticsEngine?.impact(.medium)
        } else {
            soundEngine?.play(accuracy == .perfect ? .perfect : accuracy == .great ? .great : .good)
            hapticsEngine?.impact(accuracy == .perfect ? .light : .soft)
        }

        lastTapAccuracy = accuracy
        lastTapPoints = finalPoints
        tapSequence &+= 1
    }

    // MARK: - Out of lives
    private func handleOutOfLives() {
        if !hasUsedReviveRef && mode.supportsRevive {
            pausedRef = true
            showReviveModal = true
        } else {
            finalizeGameOver()
        }
    }

    func acceptRevive() {
        hasUsedReviveRef = true
        showReviveModal = false
        AnalyticsService.logReviveUsed(mode: mode.rawValue)
        livesRef = mode.initialLives ?? livesRef
        lives = livesRef
        if mode == .timed {
            timedStartTime += GameConfig.reviveBonusSeconds
            timeLeft += GameConfig.reviveBonusSeconds
        }
        pausedRef = false
        lastTimestamp = 0
    }

    func declineRevive() {
        showReviveModal = false
        hasUsedReviveRef = true
        pausedRef = false
        finalizeGameOver()
    }

    // MARK: - Timed end
    private func handleTimedEnd() {
        guard !didFinalizeRef else { return }
        gameOverRef = true
        displayLink?.invalidate()
        finalizeAndReport()
    }

    // MARK: - Quit
    func quit() {
        guard !didFinalizeRef else { return }
        gameOverRef = true
        displayLink?.invalidate()
        finalizeAndReport()
    }

    // MARK: - Final game over
    private func finalizeGameOver() {
        guard !didFinalizeRef else { return }
        gameOverRef = true
        displayLink?.invalidate()
        phase = .finished
        finalizeAndReport()
    }

    private func finalizeAndReport() {
        guard !didFinalizeRef else { return }
        didFinalizeRef = true
        phase = .finished

        var profile = PlayerProfile.load() ?? PlayerProfile()

        let isNewBest = scoreRef > profile.bestScore(for: mode) && scoreRef > 0
        profile.updateBestScore(scoreRef, for: mode)

        var coinsEarned = 0
        coinsEarned = GameConfig.calcGameCoins(score: scoreRef, maxCombo: maxComboRef, mode: mode)
        if coinsEarned > 0 { profile.coins += coinsEarned }

        profile.stats.totalGames += 1
        if maxComboRef > profile.stats.highestCombo { profile.stats.highestCombo = maxComboRef }
        profile.stats.totalCoinsEarned += coinsEarned
        profile.stats.perfectTaps += perfectCountRef

        var xpEarned = 0
        var leveledUp: Int? = nil
        if mode.earnXP {
            xpEarned = GameConfig.calcGameXP(score: scoreRef, maxCombo: maxComboRef, mode: mode)
            var xp = profile.xp + xpEarned
            var level = profile.level
            var didLevelUp = false
            while xp >= GameConfig.xpForLevel(level) {
                xp -= GameConfig.xpForLevel(level)
                level += 1
                didLevelUp = true
            }
            profile.xp = xp
            profile.level = level
            if didLevelUp { leveledUp = level }
        }

        if mode.earnXP {
            let sxp = GameConfig.calcSeasonXP(score: scoreRef, maxCombo: maxComboRef, mode: mode)
            profile.seasonXP += sxp
            let newTier = min(GameConfig.seasonMaxTiers, profile.seasonXP / GameConfig.seasonXPPerTier)
            profile.seasonTier = newTier
        }

        if scoreRef > 0 && mode != .zen {
            let entry = ScoreEntry(score: scoreRef, date: ISO8601DateFormatter().string(from: Date()))
            profile.scoreHistory.insert(entry, at: 0)
            if profile.scoreHistory.count > 10 {
                profile.scoreHistory = Array(profile.scoreHistory.prefix(10))
            }
        }

        let gameData = GameData(score: scoreRef, maxCombo: maxComboRef, mode: mode)
        let newAchievements = Achievement.check(gameData: gameData, profile: profile)
        for ach in newAchievements {
            profile.achievements.append(ach.id)
            profile.coins += ach.reward
        }

        if !profile.activeChallenge.isEmpty,
           let challenge = Challenge.all.first(where: { $0.id == profile.activeChallenge }),
           !profile.completedChallenges.contains(challenge.id) {
            let elapsed = CACurrentMediaTime() - gameStartTime
            let currentSpeedLevel = min(20, (tapsRef / GameConfig.classicSpeedEvery) + 1)
            if Challenge.checkCompletion(
                challenge: challenge, score: scoreRef, maxCombo: maxComboRef,
                mode: mode, missCount: missCountRef, perfectsInFirst20: perfectsInFirst20Ref,
                speedLevel: currentSpeedLevel, elapsedSeconds: elapsed
            ) {
                profile.completedChallenges.append(challenge.id)
                let reward = Challenge.parseReward(challenge.rewardLabel)
                profile.coins += reward.coins
                profile.stats.totalCoinsEarned += reward.coins
                if let theme = reward.theme, !profile.ownedItems.contains(theme) {
                    profile.ownedItems.append(theme)
                }
                profile.activeChallenge = ""
            }
        }

        var quests = DailyQuest.loadSaved() ?? DailyQuest.generateForToday()
        DailyQuest.updateProgress(quests: &quests, score: scoreRef, maxCombo: maxComboRef,
                                  mode: mode, coinsEarned: coinsEarned, perfects: perfectCountRef)
        for i in quests.indices where quests[i].completed && !quests[i].rewardClaimed {
            profile.coins += quests[i].reward
            quests[i].rewardClaimed = true
        }
        DailyQuest.save(quests: quests)

        EconomyManager.shared.persistProfile(profile, syncCloud: false)

        // Analytics
        AnalyticsService.logGameEnd(mode: mode.rawValue, score: scoreRef, maxCombo: maxComboRef, coinsEarned: coinsEarned)
        if let lvl = leveledUp { AnalyticsService.logLevelUp(newLevel: lvl) }
        for ach in newAchievements { AnalyticsService.logAchievementUnlocked(achievementId: ach.id) }

        let hasValidDuelContext = duelContext?.mode == mode && !(duelContext?.duelId.isEmpty ?? true)
        let isDuelSession = hasValidDuelContext
        let result = GameResult(
            score: scoreRef, maxCombo: maxComboRef, mode: mode,
            coinsEarned: coinsEarned, xpEarned: xpEarned,
            leveledUp: leveledUp, newAchievements: newAchievements, isNewBest: isNewBest,
            isDuelSession: isDuelSession
        )

        Task {
            await FirebaseService.shared.saveProfile(profile)
            await FirebaseService.shared.submitScore(mode: mode, score: scoreRef, maxCombo: maxComboRef, profile: profile)
            if hasValidDuelContext, let ctx = duelContext {
                await FirebaseService.shared.submitDuelScore(duelId: ctx.duelId, role: ctx.role.rawValue, score: scoreRef, maxCombo: maxComboRef)
                // NOTE: Do NOT clear DuelContext here — DuelResultsView reads it on appear.
                // Context is overwritten on the next duel and cleaned up on account deletion.
            }
        }

        onGameFinished?(result)
    }

    // MARK: - Cleanup
    func cleanup() {
        gameOverRef = true
        displayLink?.invalidate()
        displayLink = nil
        displayLinkProxy = nil
        lifecyclePauseStart = nil
        lifecyclePausedRef = false
    }

    // MARK: - App lifecycle
    func appDidMoveToBackground() {
        guard !gameOverRef else { return }
        guard case .playing = phase else { return }
        guard !lifecyclePausedRef else { return }
        lifecyclePausedRef = true
        lifecyclePauseStart = CACurrentMediaTime()
        pausedRef = true
    }

    func appDidBecomeActive() {
        guard lifecyclePausedRef else { return }
        lifecyclePausedRef = false

        if let pausedAt = lifecyclePauseStart {
            let delta = max(0, CACurrentMediaTime() - pausedAt)
            gameStartTime += delta
            if mode.hasTimer { timedStartTime += delta }
        }
        lifecyclePauseStart = nil

        // Keep gameplay paused only if revive modal is currently open.
        pausedRef = showReviveModal
        lastTimestamp = 0
    }

    deinit {
        displayLink?.invalidate()
    }

    private func currentTapBarPerfectZoneScale() -> Double {
        if mode == .precision {
            return precisionZoneScale
        }
        if mode == .tinyWindow {
            return tinyWindowZoneScale
        }
        if mode == .hardcoreCombo, hardcorePenaltyTapsRemaining > 0 {
            return GameConfig.hardcorePenaltyPerfectScale
        }
        return mode.perfectZoneScale
    }

    private func syncTapBarPerfectZoneScale() {
        let newScale = currentTapBarPerfectZoneScale()
        if abs(tapBarPerfectZoneScale - newScale) > 0.0001 {
            tapBarPerfectZoneScale = newScale
        }
    }
}

// MARK: - DisplayLinkProxy (breaks RunLoop → CADisplayLink → ViewModel retain cycle)
private class DisplayLinkProxy {
    private let callback: (CADisplayLink) -> Void

    init(callback: @escaping (CADisplayLink) -> Void) {
        self.callback = callback
    }

    @objc func tick(_ link: CADisplayLink) {
        callback(link)
    }
}
