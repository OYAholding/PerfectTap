import SwiftUI

// MARK: - Cosmetic effect layer
//
// Draws the visual effect of the resolved cosmetics for one event. Placed by
// GameView / Preview Studio as a non-hit-testable overlay. Guarantees:
//  * nothing for `.none`, `.legacyParticles` (GameView keeps ParticleEffectView
//    for it) and EffectsLevel.off;
//  * EffectsLevel.reduced (incl. Reduce Motion): one static primitive that
//    fades — no movement, no scaling;
//  * bounded: ≤ 24 primitives per burst, ≤ 1.2 s (game over ≤ 1.8 s), ≤ 2
//    overlapping bursts (oldest dropped), flashes ≤ 3/s, burst diameter ≤ 45 %
//    of the layer width (CosmeticEffectBounds);
//  * rendered by Core Animation (Effects/CosmeticEffectPainter.swift,
//    CosmeticEffectCARenderer): a burst is sampled once when it fires and the
//    render server animates it — no TimelineView, no per-frame SwiftUI update or
//    main-thread rasterisation while it plays (QA-02). Layers are removed when
//    their burst ends; the ≤ 2-burst queue below is the only state.
//
// Fires on *changes* of `trigger` (a new `sequence`), not on appear.
// Geometry: Effects/CosmeticEffectFrames.swift; drawing: Effects/CosmeticEffectPainter.swift.

struct CosmeticEffectTrigger: Equatable {
    let event: CosmeticEvent
    /// Changes for every occurrence (repeated PERFECT → PERFECT still fires).
    let sequence: Int
}

struct CosmeticEffectLayer: View {
    let resolved: ResolvedCosmetics
    let trigger: CosmeticEffectTrigger?
    /// Where the burst originates, in the layer's unit space (0…1).
    var origin: UnitPoint = UnitPoint(x: 0.5, y: 0.45)

    @Environment(\.effectsLevel) private var effects
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var queue = CosmeticBurstQueue()

    /// Effective level (the environment value normally already includes Reduce Motion).
    private var level: EffectsLevel { effects.effective(reduceMotion: reduceMotion) }

    var body: some View {
        // Performance (QA-02, docs/cosmetics/PERF_QA02.md). The previous
        // TimelineView + Canvas re-evaluated SwiftUI and rasterised radial
        // gradients on the main thread every frame while a burst was alive; the
        // Core Animation renderer does that work once per burst instead.
        CosmeticEffectCAView(bursts: queue.bursts, origin: origin)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .onChange(of: trigger) { fire($0) }
            .onChange(of: effects) { if $0 == .off { queue.removeAll() } }
    }

    private func fire(_ trigger: CosmeticEffectTrigger?) {
        guard let trigger,
              let spec = CosmeticEffectPlanner.spec(resolved: resolved, trigger: trigger, level: level) else { return }
        queue.push(spec, id: trigger.sequence, at: Date().timeIntervalSinceReferenceDate)
    }
}

// MARK: - Previews

#if DEBUG
/// Re-fires one collection's effect for `event` every 1.6 s (2.2 s for game over) on a game-like background.
private struct CosmeticEffectPreviewHarness: View {
    let collectionID: CosmeticCollectionID
    let event: CosmeticEvent
    var level: EffectsLevel = .full

    @State private var sequence = 0
    private var trigger: CosmeticEffectTrigger? { sequence == 0 ? nil : CosmeticEffectTrigger(event: event, sequence: sequence) }

    private var resolved: ResolvedCosmetics {
        var loadout = CosmeticLoadout()
        if let c = CosmeticCatalog.collection(id: collectionID) { loadout.apply(collection: c) }
        return .resolve(loadout, isOwned: { _ in true })
    }

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.07, green: 0.06, blue: 0.14), Color(red: 0.13, green: 0.08, blue: 0.22)],
                           startPoint: .top, endPoint: .bottom)
            RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.12)).frame(height: 28).padding(.horizontal, 24)
                .offset(y: -40)
            CosmeticEffectLayer(resolved: resolved, trigger: trigger)
            VStack {
                Spacer()
                Text("\(collectionID) · \(event.rawValue) · \(level.rawValue)").font(.caption).foregroundColor(.white.opacity(0.7))
            }.padding()
        }
        .environment(\.effectsLevel, level)
        .onReceive(Timer.publish(every: event == .gameOver ? 2.2 : 1.6, on: .main, in: .common).autoconnect()) { _ in sequence += 1 }
        .onAppear { sequence = 1 }
    }
}

#Preview("Quack · splash (tap)") { CosmeticEffectPreviewHarness(collectionID: "quack_attack", event: .tap) }
#Preview("Quack · starBurst (perfect)") { CosmeticEffectPreviewHarness(collectionID: "quack_attack", event: .perfect) }
#Preview("Quack · splash (miss)") { CosmeticEffectPreviewHarness(collectionID: "quack_attack", event: .miss) }
#Preview("Quack · feathers (life lost)") { CosmeticEffectPreviewHarness(collectionID: "quack_attack", event: .lifeLost) }
#Preview("Quack · rainDroop (game over)") { CosmeticEffectPreviewHarness(collectionID: "quack_attack", event: .gameOver) }
#Preview("Paw · ripple (tap)") { CosmeticEffectPreviewHarness(collectionID: "purrfect_tap", event: .great) }
#Preview("Paw · sparkle (perfect)") { CosmeticEffectPreviewHarness(collectionID: "purrfect_tap", event: .perfect) }
#Preview("Paw · scratch (miss)") { CosmeticEffectPreviewHarness(collectionID: "purrfect_tap", event: .miss) }
#Preview("Paw · fluff (life lost)") { CosmeticEffectPreviewHarness(collectionID: "purrfect_tap", event: .lifeLost) }
#Preview("Paw · rainDroop (game over)") { CosmeticEffectPreviewHarness(collectionID: "purrfect_tap", event: .gameOver) }
#Preview("Boom · sparks (tap)") { CosmeticEffectPreviewHarness(collectionID: "boom_mode", event: .good) }
#Preview("Boom · shockwave (perfect)") { CosmeticEffectPreviewHarness(collectionID: "boom_mode", event: .perfect) }
#Preview("Boom · smokePuff (miss)") { CosmeticEffectPreviewHarness(collectionID: "boom_mode", event: .miss) }
#Preview("Boom · explosion (life lost)") { CosmeticEffectPreviewHarness(collectionID: "boom_mode", event: .lifeLost) }
#Preview("Boom · explosion + sprite (game over)") { CosmeticEffectPreviewHarness(collectionID: "boom_mode", event: .gameOver) }
#Preview("Reduced · Boom game over") { CosmeticEffectPreviewHarness(collectionID: "boom_mode", event: .gameOver, level: .reduced) }
#endif
