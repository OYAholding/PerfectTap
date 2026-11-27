import SwiftUI

// MARK: - Cosmetic effect layer (contract stub — renderers owned by Agent B)
//
// Draws the visual effect of the resolved cosmetics for one event. Placed by
// GameView / Preview Studio as a non-hit-testable overlay. Must:
//  * draw nothing for `.none` and for EffectsLevel.off,
//  * draw static/short fades only for EffectsLevel.reduced (Reduce Motion),
//  * be bounded (≤ 24 particles per burst, ≤ 1.2 s life) and stop its
//    TimelineView when idle (no continuous GPU work),
//  * never block the timing bar or obstruct the full screen; no strobing.

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

    var body: some View {
        // Stub: Agent B implements styles. `.legacyParticles` stays rendered by
        // the existing ParticleEffectView in GameView.
        Color.clear.allowsHitTesting(false)
    }
}
