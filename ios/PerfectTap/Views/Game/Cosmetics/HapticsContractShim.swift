import UIKit

// LEAD: delete at integration; Agent C owns the real one
// (Services/HapticsEngine.swift: `playTapOutcome(_:)` + `setActiveHapticStyle(_:)`).
//
// Temporary stand-in so GameViewModel can dispatch by outcome on this branch.
// It reproduces the pre-Studio mapping exactly, in the same priority order as
// the old if/else chain in GameViewModel.handleTap.

extension HapticsEngine {
    func playTapOutcome(_ outcome: TapSoundOutcome) {
        if outcome.comboBroken {
            impact(.heavy)
        } else if outcome.accuracy == .miss {
            impact(.rigid)
        } else if outcome.milestone {
            impact(.medium)
        } else {
            impact(outcome.accuracy == .perfect ? .light : .soft)
        }
    }

    /// Shim: only the default style exists on this branch.
    func setActiveHapticStyle(_ id: String) {}
}
