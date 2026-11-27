import Foundation

// MARK: - Cosmetic audio routing (contract stub — owned by Agent C)
//
// Gameplay asks for *what happened*; the active sound pack decides what plays.
// Exactly one primary voice per tap outcome (see docs/cosmetics/AUDIO_POLICY.md).
// The default pack must reproduce the pre-Studio sounds exactly.

/// What a scored tap produced, as far as feedback is concerned.
struct TapSoundOutcome: Equatable {
    let accuracy: TapAccuracy
    /// The miss cost a life (lives modes only).
    var lostLife: Bool = false
    /// A combo of ≥3 was broken, or a Hardcore break happened.
    var comboBroken: Bool = false
    /// Combo just reached a milestone (5 / 10 / 20).
    var milestone: Bool = false
}

extension SoundEngine {
    /// Called from the tap path after scoring. Must only enqueue work.
    /// Stub = pre-Studio behaviour (Agent C replaces with pack routing).
    func playTapOutcome(_ outcome: TapSoundOutcome) {
        if outcome.comboBroken {
            play(.comboBreak)
        } else if outcome.accuracy == .miss {
            play(.miss)
        } else if outcome.milestone {
            play(.comboMilestone)
        } else {
            play(outcome.accuracy == .perfect ? .perfect : outcome.accuracy == .great ? .great : .good)
        }
    }

    /// Round ended (Game Over screen about to show). Default pack: silent.
    func playGameOverCosmetic() {}

    /// Select and preload the pack used in gameplay. Call before a round starts
    /// (never on the tap path). Default pack needs no preload.
    func setActiveSoundPack(_ packID: String) {}

    /// Preview Studio: play one event from any pack (owned or not). Never
    /// affects gameplay state; stopped by `stopPreview()`.
    func previewSound(_ event: CosmeticEvent, packID: String) {}

    /// Stops all preview voices (leaving the Studio / starting a round).
    func stopPreview() {}
}
