# Cosmetic Audio & Haptics Policy

Owner: Agent C (audio & haptics). Code: `Services/CosmeticAudio/CosmeticAudioRouting.swift`
(`CosmeticAudioPolicy`, pure), `Services/SoundEngine.swift` (scheduling),
`Services/HapticsEngine.swift` (`CosmeticHapticPolicy`, pure). Tests: `PerfectTapTests/CosmeticAudioTests.swift`.

## 1. One primary voice per tap

Each scored tap triggers **exactly one** sound. Nothing is layered under or over it.
Gameplay passes a `TapSoundOutcome` (accuracy, lostLife, comboBroken, milestone).
The active pack then picks the sound by precedence, top row first:

| Outcome (precedence ↓) | Default pack (`default`) — unchanged | Themed packs (`quack_attack`, `purrfect_tap`, `boom_mode`) |
|---|---|---|
| `lostLife` (a miss that cost a life) | *not distinguished*: falls through to the rows below | **lifeLost** |
| `comboBroken` (combo ≥ 3 broken on a miss, or a Hardcore break, which can happen on a GOOD) | `comboBreak` tone (2 saw tones) | **miss** |
| accuracy == miss | `miss` tone | **miss** |
| `milestone` (combo 5 / 10 / 20) | `comboMilestone` arpeggio (3 tones) | the accuracy sound (**perfect** / **great**) |
| PERFECT | `perfect` (880 + 1100 Hz) | **perfect** |
| GREAT | `great` (660 Hz) | **great** (round-robin of 3 variants) |
| GOOD | `good` (440 Hz) | **good** (round-robin of 3 variants) |
| Round end (`playGameOverCosmetic()`) | silent (as before) | **gameOver** |

Why themed packs use this policy:
- **lifeLost supersedes miss / comboBroken.** Losing a life is the more consequential news. Playing both a miss and a splash/explosion would stack two failure sounds on one tap.
- **comboBroken → miss.** A Hardcore break can happen on a GOOD tap. It still has to sound like a failure, and the pack's miss sound is its failure sound.
- **No milestone arpeggio on themed packs.** Mixing the classic sine arpeggio with a quack or boom sounds like a glitch. The combo counter animation already marks the milestone.
- **`tap` event — unused.** Every scored tap has a grade, so in gameplay v1 the policy never selects the pack's neutral `tap` sound (a test enforces this). Since QA-08 the Preview Studio doesn't play it either (see §1a). The three `<pack>_tap.caf` files (`quack_attack_tap`, `purrfect_tap_tap`, `boom_mode_tap`, 35,220 bytes together) still ship but are never heard. Status: **unused — candidate for removal or for a future deliberate tap layer (owner decision)**. They are not deleted, because their ids are stable, and removing them is a catalog + manifest change.

### 1a. Preview Studio = gameplay (QA-08)

The Preview Studio plays exactly what gameplay would play for the moment it imitates. `CosmeticPreviewModel.soundEvent(forPreview:packID:)` builds the gameplay `TapSoundOutcome` and asks **the same `CosmeticAudioPolicy.cue`**, so a policy change automatically changes the preview too. It then plays the result through `SoundEngine.previewSound(_:packID:)` on the preview node.

| Preview control | Gameplay outcome it imitates | Themed pack plays | Classic pack plays |
|---|---|---|---|
| Tap button (the skin) | a GOOD tap | **good** | `good` tone |
| Good | GOOD | **good** | `good` tone |
| Great | GREAT | **great** | `great` tone |
| Perfect | PERFECT | **perfect** | `perfect` tone |
| Miss | MISS, no life lost | **miss** | `miss` tone |
| Lose a life | MISS that costs a life | **lifeLost** | `miss` tone (classic doesn't distinguish it) |
| Game Over | round end | **gameOver** | silent |
| Picking an item | Tap Sound → PERFECT; Tap Effect → GOOD; Perfect / Miss / Life Lost / Game Over effect → that moment | as above | as above |

There are two differences from gameplay:
- **Variants.** A preview plays variant v1 of good/great. The v1 → v3 round-robin only runs in gameplay.
- **Milestones and combo breaks.** These aren't separate preview buttons. They resolve to the perfect/great and miss rows above.

Visual effects use the same events: GOOD and GREAT fire the Tap Effect, and the burst starts at the button, as in `GameView`. Haptics use the matching outcome (`HapticsEngine.previewOutcome`). `CosmeticShopTests` covers this mapping: a preview tap equals the policy's GOOD cue for every pack and never `.tap`.

**Default parity.** For every combination of the four outcome fields, the default pack returns exactly what the pre-Studio `GameViewModel` `// Sound + haptics` block played. The test is `testDefaultPackPolicyIsIdenticalToLegacyDispatch`. Unknown pack ids behave like `default`.

**Fallback.** If the themed pack's buffers aren't decoded yet (the first moments after `setActiveSoundPack`), or a file failed to decode, the engine plays the **default** tone for that outcome. It never stays silent and never blocks. Game over has no fallback, because the classic game over is silent.

## 2. Voices, priority, headroom

- **Pool.** There is a single `AVAudioEngine` and the existing 8-node `AVAudioPlayerNode` pool. Themed sounds are single buffers, so each tap uses one node.
- **Default tones.** These keep the exact pre-Studio round-robin.
- **Themed priority.** Themed voices use the same round-robin but skip any node that is still playing a *high-priority* sound (perfect, miss, lifeLost, gameOver). A burst of quick taps therefore can't cut a PERFECT tail. If all 8 nodes hold ringing priority sounds, the round-robin node is reused, so voices stay bounded. This can't happen at human tap rates with sounds ≤ 900 ms.
- **Preview node.** One extra node, separate from the pool, plays Studio previews. `stopPreview()` stops only that node.
- **Headroom.** Files are loudness-matched to the default tones (see AUDIO_MANIFEST.md). The frequent tap/good/great sounds are soft-limited to ≤ −9 dBFS (0.35), so three overlapping rapid taps sum below full scale. All other sounds peak ≤ −3 dBFS. The mixer and its volume are unchanged, so default output is identical. There is deliberately no output limiter: a look-ahead limiter would add latency to every sound, default included.

## 3. Loading, caching, lifecycle

- **`setActiveSoundPack(id)`** runs on the main thread. It sets the id, then enqueues to `audioQueue`. Files are decoded with `AVAudioFile` on `synthQueue` into the engine's player format (44.1 kHz mono float), using `AVAudioConverter` if a file ever differs. The buffers are stored back on `audioQueue`. Nothing touches disk or decodes on the tap path. Call it on round setup or when the loadout changes. It also calls `stopPreview()`.
- **Cache.** The cache holds at most the active pack plus the last previewed pack, about 0.6 MB of float PCM each. Every other pack is evicted.
- **Engine restarts.** Interruption-ended and `AVAudioEngineConfigurationChange` (route or hardware change: AirPods, Bluetooth, sample rate) restart the engine as before. Buffers are plain memory in the player format, so they survive a restart and nothing is rebuilt. No `routeChangeNotification` observer was added: a route change that matters already posts a configuration change, and one that doesn't leaves the engine running.
- **Unchanged.** The session category (`.ambient` + `.mixWithOthers`, which respects the silent switch) and music are unchanged. No network.

## 4. Settings

- **`perfecttap_sound` off.** `playTapOutcome`, `playGameOverCosmetic` and `previewSound` all return before enqueuing anything. A preview with sound off doesn't even load the pack. Previews follow the master sound setting, and no extra UI was added.
- **`perfecttap_haptics` off.** `HapticsEngine.playTapOutcome` does nothing. The setting is re-checked before the delayed second pulse of a two-beat style.
- **Settings toggle.** No separate "cosmetic sounds" toggle was added to `GameSettingsView`. The master switch covers it, and the default pack is the "off" choice for themed sounds.

## 5. Haptic styles

Precedence matches the sound policy (lostLife > comboBroken > miss > milestone > accuracy). For `default`, lostLife isn't distinguished, as before. Cells list the generator style and its intensity. A second pulse follows after the given delay (`+70 ms`). `—` means `impactOccurred()` with no intensity, exactly as today.

| Moment | `default` (unchanged) | `bouncy` (Quack) | `soft` (Purrfect) | `punchy` (Boom) |
|---|---|---|---|---|
| GOOD | soft — | soft 0.7 | soft 0.5 | rigid 0.45 |
| GREAT | soft — | soft 1.0 | soft 0.75 | rigid 0.65 |
| PERFECT | light — | light 1.0, +70 ms soft 0.55 | soft 1.0 | rigid 0.9 |
| milestone | medium — | medium 0.7, +70 ms light 0.6 | soft 1.0, +80 ms soft 0.6 | rigid 1.0, +60 ms medium 0.7 |
| miss | rigid — | rigid 0.6 | soft 0.8 | medium 0.8 |
| comboBroken | heavy — | medium 1.0, +80 ms soft 0.5 | medium 0.8 | heavy 1.0 |
| lostLife | (as miss / comboBroken) | medium 1.0, +90 ms soft 0.6 | medium 0.9 | heavy 0.9 |

Rules, enforced by tests:
- `default` is identical to the old mapping. PERFECT uses `impact(.light)`, not `perfectHit()`.
- Frequent events (good, great, perfect) use only the light, soft or rigid generators, never medium or heavy.
- There are at most 2 pulses, the first one immediate, and the second ≤ 100 ms later.
- All styles use the pre-warmed `UIImpactFeedbackGenerator`s and re-`prepare()` after each pulse.
