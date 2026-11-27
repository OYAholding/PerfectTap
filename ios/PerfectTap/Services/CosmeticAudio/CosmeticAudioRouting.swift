import Foundation

// MARK: - Cosmetic audio routing
//
// Gameplay asks for *what happened*; the active sound pack decides what plays.
// Exactly one primary voice per tap outcome (docs/cosmetics/AUDIO_POLICY.md).
// The default pack reproduces the pre-Studio sounds exactly.
//
// The policy below is a pure function so it can be unit-tested without audio
// hardware. The playback API (`playTapOutcome`, `setActiveSoundPack`,
// `previewSound`, `stopPreview`, `playGameOverCosmetic`) lives in
// SoundEngine.swift because it needs the engine's private queue state.

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

/// What the engine should play for one gameplay moment.
enum SoundCue: Equatable {
    /// One of SoundEngine's built-in procedural sounds (default pack, fallbacks).
    case tone(SoundType)
    /// One event of the active themed pack.
    case pack(CosmeticEvent)
    case silent
}

enum CosmeticAudioPolicy {

    /// Primary voice for a scored tap.
    ///
    /// Default pack — byte-for-byte the pre-Studio GameViewModel dispatch:
    /// comboBroken → comboBreak, miss → miss, milestone → comboMilestone,
    /// else perfect / great / good (`lostLife` is not distinguished, as before).
    ///
    /// Themed packs — one sound per tap, chosen by importance:
    /// lostLife → lifeLost (supersedes miss/comboBroken: it is the more
    /// consequential news), comboBroken → the pack's miss sound (a Hardcore
    /// break can happen on a GOOD tap; it must still sound like a failure),
    /// miss → miss, otherwise the accuracy sound. Milestones do not layer the
    /// default arpeggio over the pack: mixing two timbres sounds like a glitch,
    /// and the combo counter animation already marks the milestone.
    static func cue(for outcome: TapSoundOutcome, packID: String) -> SoundCue {
        let pack = SoundPackCatalog.pack(id: packID)
        guard let pack, !pack.isBuiltIn else { return .tone(defaultTone(for: outcome)) }
        if outcome.lostLife { return .pack(.lifeLost) }
        if outcome.comboBroken || outcome.accuracy == .miss { return .pack(.miss) }
        return .pack(CosmeticEvent(accuracy: outcome.accuracy))
    }

    /// The pre-Studio mapping. Also the fallback while a themed pack is still
    /// loading, so a tap is never silent.
    static func defaultTone(for outcome: TapSoundOutcome) -> SoundType {
        if outcome.comboBroken { return .comboBreak }
        if outcome.accuracy == .miss { return .miss }
        if outcome.milestone { return .comboMilestone }
        switch outcome.accuracy {
        case .perfect: return .perfect
        case .great:   return .great
        default:       return .good
        }
    }

    /// Round end. The default pack has never played anything here.
    static func gameOverCue(packID: String) -> SoundCue {
        guard let pack = SoundPackCatalog.pack(id: packID), !pack.isBuiltIn else { return .silent }
        return .pack(.gameOver)
    }

    /// What previewing an event of the *default* pack plays (Studio). `tap` has
    /// no dedicated classic sound — a plain tap always produced the GOOD tone —
    /// and game over is silent in the classic pack.
    static func defaultPreviewTone(for event: CosmeticEvent) -> SoundType? {
        switch event {
        case .tap, .good: return .good
        case .great:      return .great
        case .perfect:    return .perfect
        case .miss:       return .miss
        case .lifeLost:   return .miss
        case .gameOver:   return nil
        }
    }

    /// Events whose voice must not be cut by a later tap's sound while it is
    /// still ringing (see SoundEngine voice allocation).
    static func isHighPriority(_ event: CosmeticEvent) -> Bool {
        switch event {
        case .perfect, .miss, .lifeLost, .gameOver: return true
        case .tap, .good, .great:                   return false
        }
    }
}
