# Cosmetic Audio Manifest

Machine-readable version: `ios/PerfectTap/Resources/Sounds/audio_manifest.json`. The generator writes it alongside the sounds; it lists sha256, peak, RMS, loudness, DC offset and onset for every file.

## Origin and rights (applies to every file below)

- **Origin.** Original procedural synthesis by `scripts/audio/generate_sound_packs.py` (v1). It uses only the Python stdlib. The master seed is 20261127, and each sound has its own seed (column *seed*).
- **What was not used.** No samples, no recordings, nothing downloaded, ripped or AI-generated, and no paid tools.
- **Animal sounds.** The "duck" and "cat" sounds are **synthesized approximations**: a formant-filtered buzz source. They are not animal recordings.
- **Rights.** These are original works created for and owned by the PerfectTap project. Commercial use is permitted, and no third-party licence applies.
- **Reproducibility.** `python3 scripts/audio/generate_sound_packs.py --check` regenerates everything in a temp dir and verifies the output is byte-identical to the committed files. This passes on macOS with Python 3.14 and `afconvert`.

## Format choice

**CAF, 16-bit little-endian linear PCM, 44.1 kHz, mono** (`afconvert -f caff -d LEI16@44100 -c 1`).

- **Why LPCM.** It is the same rate and channel count as the engine's player format, so loading is a straight int16 → float read with no codec and no resampling.
- **Why not IMA4.** IMA4 would be about 4× smaller (roughly 220 KB instead of 855 KB). But its 4-bit ADPCM quantisation audibly smears the sharp click and crackle transients (Boom Mode), and it saves only about 0.6 MB.
- **Why not AAC/MP3.** Not chosen because of decoder priming / padding at the start of the file, which would break the onset at sample 0 that tap sounds need.
- **Padding.** Each file carries a 4 KB `free` chunk that `afconvert` adds. That is about 132 KB of the total, and harmless.

## Mastering (all files)

1. A DC / infrasound high-pass at 35 Hz.
2. Peak-normalise to −3 dBFS through a soft (tanh-knee) limiter.
3. **Loudness-match** to the pre-Studio default tone for the same event (amplitude 0.18 sines).
   - Metric: the average of a phone-speaker weighting (high-pass 300 Hz) and a headphone weighting (high-pass 60 Hz), each followed by a +4 dB high shelf at 1.5 kHz, taken as the max over 100 ms windows.
   - Why two weightings: a pure K-weighting would let sub-bass "booms" that are inaudible on an iPhone speaker count as loud.
4. Soft-limit to the event ceiling: −9 dBFS for tap/good/great (overlap headroom), −3 dBFS for the rest.
5. A 2.5 ms raised-cosine fade-in and a 10 ms fade-out.

Validation (the script fails on any violation):

| Check | Limit |
|---|---|
| Duration, tap / good / great | 70–220 ms |
| Duration, perfect | ≤ 400 ms |
| Duration, miss | ≤ 300 ms |
| Duration, life lost | ≤ 500 ms |
| Duration, game over | ≤ 900 ms |
| NaN | none |
| Clipped samples | none |
| DC offset | \|DC\| ≤ 0.002 |
| Peak | ≤ the event ceiling |
| Onset, every event except game over (first sample above −40 dB re peak) | ≤ 2 ms; measured worst case 0.77 ms |

Default-tone loudness targets (dB, relative metric):

| perfect | great | good | miss | comboBreak |
|---|---|---|---|---|
| −18.20 | −21.03 | −22.29 | −22.80 | −22.30 |

Offsets applied:
- tap: −1 dB vs good
- miss: −1 dB vs miss
- lifeLost and gameOver: matched to comboBreak

Loudness Δ is the matched loudness minus the target. Boom Mode tap/good come out about 1 dB under target because their click transients hit the −9 dBFS ceiling first. That is acceptable: impulsive sounds read louder than their RMS suggests.

## Sounds

Status key:
- **needs designer.** Provisional. A synthesized animal-like voice that I expect a sound designer to replace or refine.
- **owner listen.** Provisional. An abstract sound that may be final once the owner has listened to it.

Nothing is marked final, because nobody has listened to any of it yet (generation and validation were numeric only).

### Default — Classic Tones (`default`)

These are built-in procedural tones, synthesized at launch by `SoundEngine.soundConfigs`. There are no files and they are unchanged.

| Event | Sound |
|---|---|
| perfect | 880 + 1100 Hz |
| great | 660 Hz |
| good | 440 Hz |
| miss | 180 Hz saw |
| comboBreak | — |
| comboMilestone | — |
| game over | silent |

### Quack Attack (`quack_attack`) — 299,072 bytes

Method: a band-limited (PolyBLEP) saw + pulse source at about 180–390 Hz with a fast exponential pitch bend. It runs through 3 parallel resonant band-passes at about 800, 1500 and 2500 Hz, with F1 opening 560 → 820 Hz over the first 25 ms (the closed "q" turning into an open "ack"). An amplitude notch at about 16 ms adds the "q-ack" break.

| id | event | ms | bytes | peak dBFS | loud Δ dB | seed | status |
|---|---|---|---|---|---|---|---|
| `quack_attack_tap` | tap (short quack) | 90 | 12,034 | −12.2 | −0.1 | 20263193 | needs designer |
| `quack_attack_good_v1..v3` | good (soft quack, ±3 % pitch / formant) | 120 | 14,680 ×3 | −12.1 | −0.1 | 20264714 / 20264723 / 20264732 | needs designer |
| `quack_attack_great_v1..v3` | great (rising, playful quack) | 150 | 17,326 ×3 | −12.6 | 0.0 | 20265671 / 20265681 / 20265691 | needs designer |
| `quack_attack_perfect` | perfect (double rising quack + sparkle pings) | 380 | 37,612 | −11.3 | 0.0 | 20266782 | needs designer |
| `quack_attack_miss` | miss (subdued low quack) | 240 | 25,264 | −14.1 | 0.0 | 20264028 | needs designer |
| `quack_attack_lifeLost` | life lost (water splash: swept band-pass noise + bubbly sine blips) | 480 | 46,432 | −15.8 | −0.1 | 20267881 | owner listen |
| `quack_attack_gameOver` | game over (descending "wah-wah" quacks, drooping final note with vibrato) | 880 | 81,712 | −14.3 | 0.0 | 20267788 | needs designer |

### Purrfect Tap (`purrfect_tap`) — 289,370 bytes

Method:
- **boop / pop:** sines with a pitch drop.
- **purr:** a 140 Hz band-limited buzz plus 900 Hz band-passed noise, amplitude-modulated at 25 Hz. The AM starts at its peak phase, so the onset isn't delayed. The buzz is kept above about 180 Hz so it is audible on a phone speaker; a real 25–50 Hz purr fundamental isn't.
- **meow:** a buzz source with a pitch arc, through formants that glide i → a → u (F1 320 → 850 → 380, F2 2300 → 1300 → 850).
- **chime:** sine bells with an inharmonic ×2.76 partial.

| id | event | ms | bytes | peak dBFS | loud Δ dB | seed | status |
|---|---|---|---|---|---|---|---|
| `purrfect_tap_tap` | tap (soft boop 760 → 480 Hz) | 90 | 12,034 | −14.9 | −0.1 | 20263230 | owner listen |
| `purrfect_tap_good_v1..v3` | good (soft pop, ±3 %) | 90 | 12,034 ×3 | −13.6 | −0.2 | 20264751 / 20264760 / 20264769 | owner listen |
| `purrfect_tap_great_v1..v3` | great (short purr, 25 Hz AM, ±3 % rate / pitch) | 200 | 21,736 ×3 | −11.2 | −0.2 | 20265708 / 20265718 / 20265728 | needs designer |
| `purrfect_tap_perfect` | perfect (chime + synthesized meow) | 380 | 37,612 | −14.3 | 0.0 | 20266819 | needs designer |
| `purrfect_tap_miss` | miss (short subdued meow a → u, low-passed) | 220 | 23,500 | −19.2 | 0.0 | 20264065 | needs designer |
| `purrfect_tap_lifeLost` | life lost (soft puff, low-pass noise 1.8 k → 250 Hz) | 360 | 35,848 | −13.7 | 0.0 | 20267918 | owner listen |
| `purrfect_tap_gameOver` | game over (fading purr into a sad descending meow) | 850 | 79,066 | −13.6 | 0.0 | 20267825 | needs designer |

### Boom Mode (`boom_mode`) — 287,606 bytes

Method: high-passed noise clicks; pitch-dropping sine thumps (mid "punch" at 130–260 Hz so it is audible on phones, plus sub 40–90 Hz for headphones); sparse seeded impulse crackle; noise through a swept low-pass.

| id | event | ms | bytes | peak dBFS | loud Δ dB | seed | status |
|---|---|---|---|---|---|---|---|
| `boom_mode_tap` | tap (mechanical click + short pop) | 80 | 11,152 | −11.5 | −0.9 | 20263202 | owner listen |
| `boom_mode_good_v1..v3` | good (tick 3 kHz, ±3 %) | 70 | 10,270 ×3 | −11.3 | −1.3 | 20264723 / 20264732 / 20264741 | owner listen |
| `boom_mode_great_v1..v3` | great (spark: bright crackle + 6 kHz burst) | 170 | 19,090 ×3 | −11.3 | −0.3 | 20265680 / 20265690 / 20265700 | owner listen |
| `boom_mode_perfect` | perfect (compact impact: click + punch + sub + short tail) | 340 | 34,084 | −6.7 | −0.4 | 20266791 | owner listen |
| `boom_mode_miss` | miss (fizzle: noise with low-pass sweep 7 k → 350 Hz) | 280 | 28,792 | −18.5 | 0.0 | 20264037 | owner listen |
| `boom_mode_lifeLost` | life lost (cartoon explosion: burst, low-pass sweep down, sub boom) | 480 | 46,432 | −13.6 | −0.1 | 20267890 | owner listen |
| `boom_mode_gameOver` | game over (final boom with rumble tail) | 850 | 79,066 | −14.3 | −0.1 | 20267797 | owner listen |

## Totals

- **Files:** 33 (11 per pack: 7 events, with 3 variants each for good and great).
- **Size on disk:** **876,048 bytes (855.5 KB)**. The manifest JSON adds 33.5 KB and is also bundled.
- **Memory at runtime:** at most 2 packs are decoded (active + preview), about 0.6 MB of float PCM each.

## Recommendations before release

1. The owner should listen to every pack on an iPhone speaker **and** on headphones.
2. Quack Attack and the Purrfect meow/purr voices are the weakest part. Formant synthesis gets "duck-like" and "cat-like" but not convincing. Budget a sound designer pass for the rows marked needs designer.
3. If any sound is replaced, keep the file names and the mastering constraints (onset, ceiling, durations). `CosmeticAudioTests` checks durations, onset and format against the bundle.
