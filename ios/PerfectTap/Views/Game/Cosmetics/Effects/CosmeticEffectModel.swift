import Foundation
import CoreGraphics

// MARK: - Cosmetic effects: pure model
//
// Everything here is value-type math with no SwiftUI/UIKit dependency, so the
// bounds the game relies on (primitive count, lifetime, overlap, extent, flash
// rate) are unit-testable. CosmeticEffectFrames turns a burst + progress into
// drawable primitives; CosmeticEffectPainter only rasterises them.

/// Hard limits every cosmetic burst obeys (asserted by CosmeticEffectsTests).
enum CosmeticEffectBounds {
    /// Drawable primitives (particles, rings, sprites, glows) in one frame of one burst.
    static let maxPrimitivesPerBurst = 24
    /// Lifetime cap for every event except game over.
    static let maxLifetime: TimeInterval = 1.2
    /// Lifetime cap for the game-over burst.
    static let maxGameOverLifetime: TimeInterval = 1.8
    /// Bursts alive at the same time; pushing one more drops the oldest.
    static let maxConcurrentBursts = 2
    /// Burst radius R as a fraction of the layer width (diameter ≤ 45 %).
    static let radiusWidthFraction: CGFloat = 0.225
    /// Absolute cap on R (large iPads / Studio previews).
    static let maxRadius: CGFloat = 110
    /// Every primitive stays inside this many R from the origin.
    static let maxExtent: Double = 1.0
    /// Flash-type glows are rate limited to ≤ 3 per second (no strobing).
    static let minFlashInterval: TimeInterval = 1.0 / 3.0
    /// EffectsLevel.reduced: one static primitive, short fade.
    static let reducedLifetime: TimeInterval = 0.5
    static let reducedGameOverLifetime: TimeInterval = 0.9

    static func lifetimeCap(for event: CosmeticEvent) -> TimeInterval {
        event == .gameOver ? maxGameOverLifetime : maxLifetime
    }

    static func radius(for size: CGSize) -> CGFloat {
        max(0, min(size.width * radiusWidthFraction, maxRadius))
    }
}

/// How much of an effect to draw. `EffectsLevel.off` maps to no burst at all.
enum CosmeticEffectMode: Equatable {
    case full
    case reduced
}

/// Small deterministic PRNG (SplitMix64) so a trigger always draws the same burst.
struct CosmeticRNG {
    private var state: UInt64
    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// Uniform in [0, 1).
    mutating func unit() -> Double { Double(next() >> 11) / Double(UInt64(1) << 53) }

    mutating func range(_ lo: Double, _ hi: Double) -> Double { lo + (hi - lo) * unit() }
}

/// Seeded per-particle parameters; their meaning is defined per style in CosmeticEffectFrames.
struct CosmeticParticle: Equatable {
    var angle: Double
    var speed: Double
    var size: Double
    var delay: Double
    var spin: Double
    var phase: Double
    var colorIndex: Int
}

/// Everything needed to draw one burst, decided once when the event fires.
struct CosmeticBurstSpec: Equatable {
    let style: CosmeticEffectStyle
    let event: CosmeticEvent
    let mode: CosmeticEffectMode
    let palette: [CosmeticRGBA]
    /// Sprite asset (feathers, game-over character). nil = native shapes only.
    let spriteName: String?
    let seed: UInt64
    let lifetime: TimeInterval
    let particles: [CosmeticParticle]
    /// Cleared by CosmeticBurstQueue when a flash would exceed 3 flashes/s.
    var allowsFlash: Bool = true

    /// Palette colour by index (wraps; -1 = white).
    func rgba(_ index: Int) -> CosmeticRGBA {
        if index < 0 || palette.isEmpty { return CosmeticRGBA(r: 1, g: 1, b: 1) }
        return palette[index % palette.count]
    }
}

enum CosmeticEffectPlanner {

    static func mode(for level: EffectsLevel) -> CosmeticEffectMode? {
        switch level {
        case .full:    return .full
        case .reduced: return .reduced
        case .off:     return nil
        }
    }

    /// The burst for `trigger`, or nil when nothing must be drawn
    /// (EffectsLevel.off, no effect slot, `.none`, `.legacyParticles`).
    static func spec(resolved: ResolvedCosmetics, trigger: CosmeticEffectTrigger, level: EffectsLevel) -> CosmeticBurstSpec? {
        guard let mode = mode(for: level), let slot = trigger.event.effectSlot else { return nil }
        let item = resolved.item(for: slot)
        guard let style = item.assets.effectStyle else { return nil }
        return spec(style: style, event: trigger.event, palette: item.assets.palette,
                    spriteName: item.assets.imageName, mode: mode, sequence: trigger.sequence)
    }

    static func spec(style: CosmeticEffectStyle, event: CosmeticEvent, palette: [CosmeticRGBA],
                     spriteName: String?, mode: CosmeticEffectMode, sequence: Int) -> CosmeticBurstSpec? {
        guard rendersNatively(style) else { return nil }
        let styleIndex = UInt64(CosmeticEffectStyle.allCases.firstIndex(of: style) ?? 0)
        let eventIndex = UInt64(CosmeticEvent.allCases.firstIndex(of: event) ?? 0)
        let seed = UInt64(bitPattern: Int64(sequence)) &* 0x9E37_79B9_7F4A_7C15 ^ (styleIndex << 8 | eventIndex)
        var rng = CosmeticRNG(seed: seed)
        let count = mode == .full ? particleCount(style) : 0
        let particles = (0..<count).map { i in makeParticle(style, index: i, count: count, rng: &rng) }
        return CosmeticBurstSpec(style: style, event: event, mode: mode, palette: palette, spriteName: spriteName,
                                 seed: seed, lifetime: lifetime(style: style, event: event, mode: mode, hasSprite: spriteName != nil),
                                 particles: particles)
    }

    /// Styles drawn by this layer. `.none` draws nothing; `.legacyParticles`
    /// stays with GameView's ParticleEffectView. Exhaustive on purpose: a new
    /// style must be classified here (and drawn by the painter) to compile.
    static func rendersNatively(_ style: CosmeticEffectStyle) -> Bool {
        switch style {
        case .none, .legacyParticles:
            return false
        case .splash, .ripple, .sparks, .starBurst, .sparkle, .shockwave, .feathers,
             .fluff, .scratch, .smokePuff, .explosion, .rainDroop:
            return true
        }
    }

    /// Seeded particles per style (fixed primitives such as rings come on top;
    /// the per-frame total is bounded by CosmeticEffectBounds.maxPrimitivesPerBurst).
    static func particleCount(_ style: CosmeticEffectStyle) -> Int {
        switch style {
        case .none, .legacyParticles: return 0
        case .splash:    return 10
        case .ripple:    return 6
        case .sparks:    return 10
        case .starBurst: return 14   // 6 stars + 8 glints
        case .sparkle:   return 8
        case .shockwave: return 12
        case .feathers:  return 5
        case .fluff:     return 13   // 7 puffs + 6 bits
        case .scratch:   return 4
        case .smokePuff: return 10   // 6 puffs + 4 embers
        case .explosion: return 14   // 6 smoke + 8 sparks
        case .rainDroop: return 14
        }
    }

    static func lifetime(style: CosmeticEffectStyle, event: CosmeticEvent, mode: CosmeticEffectMode, hasSprite: Bool) -> TimeInterval {
        if mode == .reduced {
            return event == .gameOver ? CosmeticEffectBounds.reducedGameOverLifetime : CosmeticEffectBounds.reducedLifetime
        }
        let base: TimeInterval
        switch style {
        case .none, .legacyParticles: base = 0
        case .splash:    base = 0.70
        case .ripple:    base = 0.80
        case .sparks:    base = 0.55
        case .starBurst: base = 0.95
        case .sparkle:   base = 0.95
        case .shockwave: base = 0.80
        case .feathers:  base = 1.20
        case .fluff:     base = 1.00
        case .scratch:   base = 0.60
        case .smokePuff: base = 1.10
        case .explosion: base = (event == .gameOver && hasSprite) ? 1.70 : 1.10
        case .rainDroop: base = 1.75
        }
        return min(base, CosmeticEffectBounds.lifetimeCap(for: event))
    }

    /// Styles that draw a bright flash glow (rate limited).
    static func usesFlash(_ style: CosmeticEffectStyle) -> Bool {
        style == .sparks || style == .shockwave || style == .explosion
    }

    /// Evenly spread angle for the `i`-th particle of a sub-group, with jitter.
    private static func groupAngle(_ i: Int, of n: Int, rng: inout CosmeticRNG) -> Double {
        Double(i) / Double(max(n, 1)) * 2 * .pi + rng.range(-0.3, 0.3)
    }

    private static func makeParticle(_ style: CosmeticEffectStyle, index i: Int, count: Int, rng: inout CosmeticRNG) -> CosmeticParticle {
        let even = Double(i) / Double(max(count, 1)) * 2 * .pi
        var p = CosmeticParticle(angle: even + rng.range(-0.25, 0.25), speed: rng.range(0.7, 1.0),
                                 size: rng.range(0.8, 1.2), delay: rng.range(0, 0.08),
                                 spin: rng.range(-1.5, 1.5), phase: rng.range(0, 2 * .pi), colorIndex: i % 2)
        switch style {
        case .splash:
            // Upward fan of droplets.
            p.angle = -.pi / 2 + rng.range(-1.0, 1.0)
            p.speed = rng.range(0.6, 1.0)
            p.size = rng.range(0.08, 0.125)
            p.delay = rng.range(0, 0.06)
        case .starBurst:
            if i < 6 { // stars on the upper arc
                p.angle = -.pi + 0.35 + Double(i) / 5 * (.pi - 0.7) + rng.range(-0.12, 0.12)
                p.size = rng.range(0.12, 0.16)
                p.delay = Double(i) * 0.025
            } else {   // glints
                p.angle = groupAngle(i - 6, of: count - 6, rng: &rng)
                p.size = rng.range(0.05, 0.075)
                p.speed = rng.range(0.35, 0.85)
                p.delay = rng.range(0.05, 0.5)
            }
            p.colorIndex = i % 3
        case .sparkle:
            p.delay = rng.range(0.04, 0.35)
            p.size = rng.range(0.055, 0.085)
            p.colorIndex = i % 3
        case .shockwave:
            p.angle = Double(i) / Double(count) * 2 * .pi + rng.range(-0.1, 0.1)
            p.delay = rng.range(0, 0.06)
        case .feathers:
            p.angle = -.pi / 2 + rng.range(-1.2, 1.2)
            p.size = rng.range(0.38, 0.48)
            p.delay = Double(i) * 0.03
            p.spin = rng.range(-0.6, 0.6)
        case .fluff:
            p.delay = rng.range(0, 0.1)
            p.angle = i < 7 ? groupAngle(i, of: 7, rng: &rng) : groupAngle(i - 7, of: count - 7, rng: &rng)
            p.colorIndex = i < 7 ? 0 : 1
        case .scratch:
            p.angle = -.pi / 3 + rng.range(-0.5, 0.5)
            p.speed = rng.range(0.25, 0.45)
        case .smokePuff:
            p.angle = -.pi / 2 + rng.range(-0.9, 0.9)
            p.delay = i < 6 ? Double(i) * 0.04 : rng.range(0, 0.15)
        case .explosion:
            p.delay = i < 6 ? rng.range(0, 0.06) : rng.range(0, 0.04)
            p.angle = i < 6 ? groupAngle(i, of: 6, rng: &rng) : groupAngle(i - 6, of: count - 6, rng: &rng)
            p.colorIndex = i < 6 ? 2 : i % 2
        case .rainDroop:
            p.angle = rng.range(-0.62, 0.62)        // x position (R units)
            p.delay = rng.range(0.05, 0.55)
            p.speed = rng.range(0.85, 1.15)
            p.colorIndex = 0
        default:
            break
        }
        return p
    }
}

/// One live burst.
struct CosmeticBurst: Identifiable, Equatable {
    let id: Int
    var spec: CosmeticBurstSpec
    let startTime: TimeInterval

    func progress(at now: TimeInterval) -> Double {
        guard spec.lifetime > 0 else { return 1 }
        return (now - startTime) / spec.lifetime
    }

    func isExpired(at now: TimeInterval) -> Bool { progress(at: now) >= 1 }
}

/// Live bursts: at most `maxConcurrentBursts`, oldest dropped first, flashes
/// rate limited. Pure value type, owned by CosmeticEffectLayer's @State.
struct CosmeticBurstQueue: Equatable {
    private(set) var bursts: [CosmeticBurst] = []
    private(set) var lastFlashTime: TimeInterval = -.greatestFiniteMagnitude

    var isEmpty: Bool { bursts.isEmpty }

    mutating func push(_ spec: CosmeticBurstSpec, id: Int, at now: TimeInterval) {
        var spec = spec
        if CosmeticEffectPlanner.usesFlash(spec.style) {
            if now - lastFlashTime >= CosmeticEffectBounds.minFlashInterval {
                lastFlashTime = now
            } else {
                spec.allowsFlash = false
            }
        }
        prune(at: now)
        bursts.append(CosmeticBurst(id: id, spec: spec, startTime: now))
        if bursts.count > CosmeticEffectBounds.maxConcurrentBursts {
            bursts.removeFirst(bursts.count - CosmeticEffectBounds.maxConcurrentBursts)
        }
    }

    mutating func prune(at now: TimeInterval) {
        bursts.removeAll { $0.isExpired(at: now) }
    }

    func isExpired(at now: TimeInterval) -> Bool { bursts.allSatisfy { $0.isExpired(at: now) } }

    mutating func removeAll() { bursts.removeAll() }
}
