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
//  * the TimelineView exists only while a burst is alive; state is cleared when idle.
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
        GeometryReader { geo in
            if !queue.isEmpty {
                // Performance (QA-02): the canvas covers only the square the
                // burst can reach — R from the *full* layer width, so bursts look
                // identical — not the whole screen. drawingGroup() composites the
                // additive (plusLighter) primitives on the GPU in one pass.
                // Measured on simulator: a full-screen canvas per layer pushed
                // hitch ratio from 0.26 % to 1.3–2.4 % with themed effects.
                let R = CosmeticEffectBounds.radius(for: geo.size)
                let side = Self.canvasSide(radius: R)
                let center = CGPoint(x: geo.size.width * origin.x, y: geo.size.height * origin.y)
                TimelineView(.animation) { timeline in
                    let now = timeline.date.timeIntervalSinceReferenceDate
                    Canvas { context, _ in
                        for burst in queue.bursts {
                            CosmeticEffectPainter.draw(burst, now: now, in: &context, radius: Double(R),
                                                       center: CGPoint(x: side / 2, y: side / 2))
                        }
                    }
                    .frame(width: side, height: side)
                    .drawingGroup()
                    .position(center)
                    .onChange(of: queue.isExpired(at: now)) { expired in
                        if expired { queue.removeAll() }
                    }
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onChange(of: trigger) { fire($0) }
        .onChange(of: effects) { if $0 == .off { queue.removeAll() } }
    }

    /// Primitives stay within `maxExtent`·R of the origin; halos and sprite
    /// sizes add up to ~0.8 R more, so 2 × 1.9 R (+ edge slack) never clips.
    static func canvasSide(radius: CGFloat) -> CGFloat {
        ceil(radius * 2 * (CGFloat(CosmeticEffectBounds.maxExtent) + 0.9) + 8)
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
