import Foundation

// MARK: - Cosmetic effects: per-frame geometry (pure)
//
// `CosmeticEffectFrames.primitives(for:progress:)` returns what one burst looks
// like at normalised progress t ∈ [0, 1). Coordinates are in burst-radius units
// (R = CosmeticEffectBounds.radius(for: layerSize)), relative to the origin,
// y pointing down. The painter multiplies by R; tests check the bounds here.

struct CosmeticPrimitive: Equatable {
    enum Kind: Equatable {
        case glow       // soft radial disk (size = radius)
        case ring       // ellipse stroke (size = radius, aspect = h/w)
        case droplet    // teardrop along `rotation` (size = width)
        case streak     // tapered line along `rotation` (size = length)
        case star       // five-point star (size = outer radius)
        case twinkle    // four-point twinkle (size = outer radius)
        case sprite     // bitmap sprite (size = width, aspect = h/w)
        case puff       // three-lobe cloud (size = radius)
        case slash      // claw slash revealed by `reveal` (size = length)
        case drop       // short rain streak (size = length)
        case burst      // jagged cartoon explosion (size = outer radius)
        case dot        // filled circle (size = radius)
    }

    var kind: Kind
    var x: Double
    var y: Double
    var size: Double
    var aspect: Double = 1
    var rotation: Double = 0
    var opacity: Double
    var colorIndex: Int = 0
    /// Stroke width (ring/streak/slash/drop), R units.
    var lineWidth: Double = 0
    /// Draw with an additive (plus-lighter) blend.
    var additive: Bool = false
    /// Reveal fraction for slashes.
    var reveal: Double = 1
    /// Stable identity of this primitive across frames of one burst (particle
    /// index, or 100+ for fixed primitives). Lets a renderer animate one layer
    /// per track instead of redrawing every frame (CosmeticEffectTimeline).
    var track: Int = 0

    func tracked(_ id: Int) -> CosmeticPrimitive { var c = self; c.track = id; return c }

    /// Farthest point from the origin, in R units (conservative).
    var extent: Double {
        let d = (x * x + y * y).squareRoot()
        switch kind {
        case .glow, .puff, .star, .twinkle, .burst, .dot:
            return d + size * (kind == .puff ? 1.45 : 1)
        case .ring:
            return d + size * max(1, aspect) + lineWidth / 2
        case .droplet:
            return d + size * 0.8
        case .streak, .slash, .drop:
            return d + size / 2 + lineWidth / 2
        case .sprite:
            return d + size * max(1, aspect) / 2
        }
    }
}

enum CosmeticEffectFrames {

    // MARK: Easing

    static func clamp01(_ x: Double) -> Double { min(1, max(0, x)) }
    /// Local progress of a sub-animation starting at `delay` and lasting `duration` (in t units).
    static func local(_ t: Double, _ delay: Double, _ duration: Double) -> Double { clamp01((t - delay) / duration) }
    static func easeOut(_ x: Double) -> Double { let u = 1 - clamp01(x); return 1 - u * u * u }
    static func easeOutBack(_ x: Double) -> Double {
        let c1 = 1.70158, c3 = c1 + 1, u = clamp01(x) - 1
        return 1 + c3 * u * u * u + c1 * u * u
    }
    /// 1 until `start`, then linear to 0 at 1.
    static func fadeOut(_ x: Double, from start: Double) -> Double {
        x <= start ? 1 : clamp01(1 - (x - start) / (1 - start))
    }
    static func bell(_ x: Double) -> Double { sin(.pi * clamp01(x)) }

    // MARK: Frames

    static func primitives(for spec: CosmeticBurstSpec, progress t: Double) -> [CosmeticPrimitive] {
        guard t >= 0, t < 1 else { return [] }
        if spec.mode == .reduced { return reduced(spec, t) }
        switch spec.style {
        case .none, .legacyParticles: return []
        case .splash:    return splash(spec, t)
        case .ripple:    return ripple(spec, t)
        case .sparks:    return sparks(spec, t)
        case .starBurst: return starBurst(spec, t)
        case .sparkle:   return sparkle(spec, t)
        case .shockwave: return shockwave(spec, t)
        case .feathers:  return feathers(spec, t)
        case .fluff:     return fluff(spec, t)
        case .scratch:   return scratch(spec, t)
        case .smokePuff: return smokePuff(spec, t)
        case .explosion: return explosion(spec, t)
        case .rainDroop: return rainDroop(spec, t)
        }
    }

    /// Reduced motion / reduced effects: one static primitive that fades in and out. No movement, no scaling.
    private static func reduced(_ s: CosmeticBurstSpec, _ t: Double) -> [CosmeticPrimitive] {
        let o = clamp01(t / 0.2) * fadeOut(t, from: 0.55)
        let sprite: Bool
        switch s.style {
        case .feathers, .rainDroop: sprite = s.spriteName != nil
        case .explosion: sprite = s.spriteName != nil && s.event == .gameOver
        default: sprite = false
        }
        if sprite {
            let width = s.event == .gameOver ? 1.5 : 0.5
            return [CosmeticPrimitive(kind: .sprite, x: 0, y: 0, size: width, opacity: o).tracked(100)]
        }
        return [CosmeticPrimitive(kind: .glow, x: 0, y: 0, size: 0.42, opacity: 0.7 * o, colorIndex: 0, additive: true).tracked(101)]
    }

    private static func splash(_ s: CosmeticBurstSpec, _ t: Double) -> [CosmeticPrimitive] {
        var out: [CosmeticPrimitive] = []
        out.append(CosmeticPrimitive(kind: .ring, x: 0, y: 0.12, size: 0.15 + 0.6 * easeOut(t), aspect: 0.34,
                                     opacity: pow(1 - t, 1.4), colorIndex: 0, lineWidth: 0.05 * (1 - t) + 0.012, additive: true).tracked(100))
        let l2 = local(t, 0.15, 0.7)
        if l2 > 0 && l2 < 1 {
            out.append(CosmeticPrimitive(kind: .ring, x: 0, y: 0.12, size: 0.1 + 0.42 * easeOut(l2), aspect: 0.34,
                                         opacity: 0.7 * (1 - l2), colorIndex: 1, lineWidth: 0.03, additive: true).tracked(101))
        }
        for (i, p) in s.particles.enumerated() {
            let l = local(t, p.delay, 0.85)
            guard l > 0, l < 1 else { continue }
            let reach = p.speed * 0.82
            let dist = reach * easeOut(l)
            let x = cos(p.angle) * dist
            let y = sin(p.angle) * dist + 0.75 * l * l
            let du = 3 * (1 - l) * (1 - l) * reach
            let vx = cos(p.angle) * du, vy = sin(p.angle) * du + 1.5 * l
            out.append(CosmeticPrimitive(kind: .droplet, x: x, y: y, size: p.size * (1 - 0.45 * l),
                                         rotation: atan2(vy, vx), opacity: fadeOut(l, from: 0.6), colorIndex: p.colorIndex).tracked(i))
        }
        return out
    }

    private static func ripple(_ s: CosmeticBurstSpec, _ t: Double) -> [CosmeticPrimitive] {
        var out: [CosmeticPrimitive] = [
            CosmeticPrimitive(kind: .glow, x: 0, y: 0, size: 0.38, aspect: 0.6, opacity: 0.4 * pow(1 - t, 2), colorIndex: 0, additive: true).tracked(100)
        ]
        for i in 0..<3 {
            let l = local(t, Double(i) * 0.14, 0.72)
            guard l > 0, l < 1 else { continue }
            out.append(CosmeticPrimitive(kind: .ring, x: 0, y: 0, size: 0.12 + 0.76 * easeOut(l), aspect: 0.5,
                                         opacity: pow(1 - l, 1.3), colorIndex: i % 2, lineWidth: 0.06 * (1 - l) + 0.014, additive: true).tracked(101 + i))
        }
        for (i, p) in s.particles.enumerated() {
            let l = local(t, 0.08 + p.delay * 2, 0.6)
            guard l > 0, l < 1 else { continue }
            let r = 0.35 + 0.35 * easeOut(l)
            out.append(CosmeticPrimitive(kind: .twinkle, x: cos(p.angle) * r, y: sin(p.angle) * r * 0.5,
                                         size: 0.05 * p.size * bell(l), rotation: p.phase, opacity: bell(l), colorIndex: -1, additive: true).tracked(i))
        }
        return out
    }

    private static func sparks(_ s: CosmeticBurstSpec, _ t: Double) -> [CosmeticPrimitive] {
        var out: [CosmeticPrimitive] = []
        if s.allowsFlash {
            let f = 1 - local(t, 0, 0.35)
            if f > 0 { out.append(CosmeticPrimitive(kind: .glow, x: 0, y: 0, size: 0.34, opacity: 0.45 * f * f, colorIndex: 0, additive: true).tracked(100)) }
        }
        for (i, p) in s.particles.enumerated() {
            let l = local(t, p.delay, 0.9)
            guard l > 0, l < 1 else { continue }
            let head = 0.16 + p.speed * 0.74 * easeOut(l)
            let length = 0.28 * (1 - l) + 0.04
            let c = head - length / 2
            out.append(CosmeticPrimitive(kind: .streak, x: cos(p.angle) * c, y: sin(p.angle) * c, size: length,
                                         rotation: p.angle, opacity: fadeOut(l, from: 0.45), colorIndex: p.colorIndex,
                                         lineWidth: 0.06 * (1 - 0.5 * l), additive: true).tracked(i))
        }
        return out
    }

    private static func starBurst(_ s: CosmeticBurstSpec, _ t: Double) -> [CosmeticPrimitive] {
        var out: [CosmeticPrimitive] = [
            CosmeticPrimitive(kind: .glow, x: 0, y: 0, size: 0.45 * easeOutBack(min(1, t / 0.3)), opacity: 0.5 * (1 - t), colorIndex: 0, additive: true).tracked(100),
            CosmeticPrimitive(kind: .ring, x: 0, y: 0.25, size: 0.22 + 0.45 * easeOut(t), aspect: 0.32,
                              opacity: 0.95 * fadeOut(t, from: 0.45), colorIndex: 0, lineWidth: 0.05, additive: true).tracked(101),
        ]
        for (i, p) in s.particles.enumerated() {
            if i < 6 {
                let l = local(t, p.delay, 0.88)
                guard l > 0, l < 1 else { continue }
                let dist = (0.25 + 0.5 * easeOut(l)) * p.speed
                let pop = easeOutBack(min(1, l / 0.35))
                out.append(CosmeticPrimitive(kind: .star, x: cos(p.angle) * dist, y: sin(p.angle) * dist,
                                             size: p.size * pop, rotation: p.spin * l, opacity: fadeOut(l, from: 0.62),
                                             colorIndex: p.colorIndex).tracked(i))
            } else {
                let l = local(t, p.delay, 0.45)
                guard l > 0, l < 1 else { continue }
                let r = p.speed
                out.append(CosmeticPrimitive(kind: .twinkle, x: cos(p.angle) * r, y: sin(p.angle) * r * 0.8,
                                             size: p.size * bell(l), opacity: bell(l), colorIndex: 2, additive: true).tracked(i))
            }
        }
        return out
    }

    private static func sparkle(_ s: CosmeticBurstSpec, _ t: Double) -> [CosmeticPrimitive] {
        var out: [CosmeticPrimitive] = [
            CosmeticPrimitive(kind: .glow, x: 0, y: 0, size: 0.55 * easeOut(min(1, t / 0.4)), opacity: 0.55 * pow(1 - t, 1.5), colorIndex: 0, additive: true).tracked(100),
            CosmeticPrimitive(kind: .ring, x: 0, y: 0.25, size: 0.2 + 0.45 * easeOut(t), aspect: 0.32,
                              opacity: 1 - t, colorIndex: 0, lineWidth: 0.04, additive: true).tracked(101),
            CosmeticPrimitive(kind: .twinkle, x: 0, y: 0, size: 0.42 * easeOutBack(min(1, t / 0.3)), rotation: 0.3 * t,
                              opacity: fadeOut(t, from: 0.55), colorIndex: 2).tracked(102),
        ]
        for (i, p) in s.particles.enumerated() {
            let l = local(t, p.delay, 0.55)
            guard l > 0, l < 1 else { continue }
            let r = (0.32 + 0.45 * easeOut(l)) * p.speed
            out.append(CosmeticPrimitive(kind: .twinkle, x: cos(p.angle) * r, y: sin(p.angle) * r,
                                         size: p.size * (0.4 + 0.6 * bell(l)), rotation: p.phase, opacity: bell(l),
                                         colorIndex: p.colorIndex, additive: true).tracked(i))
        }
        return out
    }

    private static func shockwave(_ s: CosmeticBurstSpec, _ t: Double) -> [CosmeticPrimitive] {
        var out: [CosmeticPrimitive] = []
        if s.allowsFlash {
            let f = 1 - local(t, 0, 0.3)
            if f > 0 { out.append(CosmeticPrimitive(kind: .glow, x: 0, y: 0, size: 0.5, opacity: 0.7 * f * f, colorIndex: 2, additive: true).tracked(100)) }
        }
        out.append(CosmeticPrimitive(kind: .ring, x: 0, y: 0, size: 0.15 + 0.8 * easeOut(t), opacity: pow(1 - t, 1.2),
                                     colorIndex: 0, lineWidth: 0.07 * (1 - t) + 0.012, additive: true).tracked(101))
        let l2 = local(t, 0.12, 0.8)
        if l2 > 0 && l2 < 1 {
            out.append(CosmeticPrimitive(kind: .ring, x: 0, y: 0, size: 0.1 + 0.6 * easeOut(l2), opacity: 0.8 * (1 - l2),
                                         colorIndex: 1, lineWidth: 0.035, additive: true).tracked(102))
        }
        for (i, p) in s.particles.enumerated() {
            let l = local(t, p.delay, 0.8)
            guard l > 0, l < 1 else { continue }
            let inner = 0.3 + 0.5 * easeOut(l)
            let length = 0.22 * (1 - l) + 0.03
            let c = inner + length / 2
            out.append(CosmeticPrimitive(kind: .streak, x: cos(p.angle) * c, y: sin(p.angle) * c, size: length,
                                         rotation: p.angle, opacity: fadeOut(l, from: 0.4), colorIndex: p.colorIndex,
                                         lineWidth: 0.035, additive: true).tracked(i))
        }
        return out
    }

    private static func feathers(_ s: CosmeticBurstSpec, _ t: Double) -> [CosmeticPrimitive] {
        var out: [CosmeticPrimitive] = []
        let g = 1 - local(t, 0, 0.4)
        if g > 0 { out.append(CosmeticPrimitive(kind: .glow, x: 0, y: 0, size: 0.35, opacity: 0.4 * g, colorIndex: 0, additive: true).tracked(100)) }
        for (i, p) in s.particles.enumerated() {
            let l = local(t, p.delay, 0.86)
            guard l > 0, l < 1 else { continue }
            let pop = easeOut(min(1, l * 2.2))
            let sway = sin(l * 2 * .pi * 0.9 + p.phase)
            let x = cos(p.angle) * p.speed * 0.45 * pop + sway * 0.12
            let y = sin(p.angle) * p.speed * 0.35 * pop + 0.5 * pow(l, 1.6)
            out.append(CosmeticPrimitive(kind: .sprite, x: x, y: y, size: p.size, rotation: p.spin + sway * 0.55,
                                         opacity: clamp01(l / 0.08) * fadeOut(l, from: 0.6), colorIndex: p.colorIndex).tracked(i))
        }
        return out
    }

    private static func fluff(_ s: CosmeticBurstSpec, _ t: Double) -> [CosmeticPrimitive] {
        var out: [CosmeticPrimitive] = []
        let g = 1 - local(t, 0, 0.35)
        if g > 0 { out.append(CosmeticPrimitive(kind: .glow, x: 0, y: 0, size: 0.4, opacity: 0.35 * g, colorIndex: 1, additive: true).tracked(100)) }
        for (i, p) in s.particles.enumerated() {
            let l = local(t, p.delay, 0.9)
            guard l > 0, l < 1 else { continue }
            if i < 7 {
                let d = 0.1 + 0.42 * p.speed * easeOut(l)
                out.append(CosmeticPrimitive(kind: .puff, x: cos(p.angle) * d, y: sin(p.angle) * d - 0.08 * l,
                                             size: (0.12 + 0.08 * easeOut(l)) * p.size, rotation: p.spin,
                                             opacity: 0.95 * fadeOut(l, from: 0.45), colorIndex: 0).tracked(i))
            } else {
                let d = 0.2 + 0.6 * p.speed * easeOut(l)
                out.append(CosmeticPrimitive(kind: .dot, x: cos(p.angle) * d, y: sin(p.angle) * d,
                                             size: 0.03 * (1 - 0.6 * l), opacity: fadeOut(l, from: 0.4), colorIndex: 1).tracked(i))
            }
        }
        return out
    }

    private static func scratch(_ s: CosmeticBurstSpec, _ t: Double) -> [CosmeticPrimitive] {
        var out: [CosmeticPrimitive] = []
        let angle = -Double.pi / 3          // "/" direction, top-right to bottom-left
        let perp = (cos(angle + .pi / 2), sin(angle + .pi / 2))
        for i in 0..<3 {
            let l = local(t, Double(i) * 0.06, 0.9)
            guard l > 0, l < 1 else { continue }
            let off = Double(i - 1) * 0.22
            let length = i == 1 ? 0.9 : 0.75
            out.append(CosmeticPrimitive(kind: .slash, x: perp.0 * off, y: perp.1 * off, size: length, rotation: angle,
                                         opacity: fadeOut(l, from: 0.5), colorIndex: 0, lineWidth: 0.075, additive: true,
                                         reveal: easeOut(min(1, l / 0.35))).tracked(100 + i))
        }
        for (i, p) in s.particles.enumerated() {
            let l = local(t, 0.12 + p.delay, 0.6)
            guard l > 0, l < 1 else { continue }
            let d = 0.45 + p.speed * easeOut(l)
            out.append(CosmeticPrimitive(kind: .dot, x: cos(p.angle + .pi) * min(d, 0.9) * 0.9, y: sin(p.angle + .pi) * min(d, 0.9) * 0.9,
                                         size: 0.025 * (1 - l), opacity: fadeOut(l, from: 0.3), colorIndex: 1, additive: true).tracked(i))
        }
        return out
    }

    private static func smokePuff(_ s: CosmeticBurstSpec, _ t: Double) -> [CosmeticPrimitive] {
        var out: [CosmeticPrimitive] = []
        for (i, p) in s.particles.enumerated() {
            if i < 6 {
                let l = local(t, p.delay, 0.75)
                guard l > 0, l < 1 else { continue }
                let x = cos(p.angle) * 0.25 * p.speed * easeOut(l) + sin(l * 3 + p.phase) * 0.05
                let y = 0.1 - 0.6 * p.speed * easeOut(l)
                out.append(CosmeticPrimitive(kind: .puff, x: x, y: y, size: 0.1 + 0.15 * easeOut(l), rotation: p.spin,
                                             opacity: 0.75 * clamp01(l * 5) * fadeOut(l, from: 0.35), colorIndex: i % 2).tracked(i))
            } else {
                let l = local(t, p.delay, 0.5)
                guard l > 0, l < 1 else { continue }
                let d = 0.15 + 0.5 * p.speed * easeOut(l)
                out.append(CosmeticPrimitive(kind: .dot, x: cos(p.angle) * d * 0.6, y: sin(p.angle) * d,
                                             size: 0.022 * (1 - l), opacity: 0.8 * fadeOut(l, from: 0.3), colorIndex: -1, additive: true).tracked(i))
            }
        }
        return out
    }

    private static func explosion(_ s: CosmeticBurstSpec, _ t: Double) -> [CosmeticPrimitive] {
        let withSprite = s.event == .gameOver && s.spriteName != nil
        // With a sprite the burst is longer; the native boom plays in the first ~65 %.
        let k = withSprite ? 0.65 : 1.0
        let u = min(1, t / k)
        var out: [CosmeticPrimitive] = []
        // Smoke first (behind).
        for (i, p) in s.particles.enumerated() where i < 6 {
            let l = local(u, 0.05 + p.delay, 0.9)
            guard l > 0, l < 1 else { continue }
            let d = 0.2 + 0.36 * p.speed * easeOut(l)
            out.append(CosmeticPrimitive(kind: .puff, x: cos(p.angle) * d, y: sin(p.angle) * d * 0.8 - 0.12 * l,
                                         size: 0.1 + 0.1 * easeOut(l), rotation: p.spin,
                                         opacity: 0.85 * clamp01(l * 6) * fadeOut(l, from: 0.5), colorIndex: 2).tracked(i))
        }
        if s.allowsFlash {
            let f = 1 - local(u, 0, 0.3)
            if f > 0 && u < 1 { out.append(CosmeticPrimitive(kind: .glow, x: 0, y: 0, size: 0.5, opacity: 0.6 * f * f, colorIndex: 1, additive: true).tracked(100)) }
        }
        let lr = local(u, 0, 0.6)
        if lr < 1 {
            out.append(CosmeticPrimitive(kind: .ring, x: 0, y: 0, size: 0.2 + 0.72 * easeOut(lr), opacity: 1 - lr,
                                         colorIndex: 0, lineWidth: 0.05 * (1 - lr) + 0.01, additive: true).tracked(101))
        }
        let coreFade = fadeOut(local(u, 0, 0.6), from: 0.4)
        if coreFade > 0 && u < 1 {
            let size = 0.38 * easeOutBack(min(1, u / 0.2)) * (1 - 0.6 * local(u, 0.35, 0.4))
            out.append(CosmeticPrimitive(kind: .burst, x: 0, y: 0, size: size, rotation: Double(s.seed % 628) / 100,
                                         opacity: coreFade, colorIndex: 0).tracked(102))
        }
        if withSprite {
            let l = local(t, 0.12, 0.88)
            if l > 0 {
                out.append(CosmeticPrimitive(kind: .sprite, x: 0, y: -0.05, size: 1.5 * easeOutBack(min(1, l / 0.3)),
                                             opacity: clamp01(l * 6) * fadeOut(l, from: 0.78)).tracked(103))
            }
        }
        for (i, p) in s.particles.enumerated() where i >= 6 {
            let l = local(u, p.delay, 0.85)
            guard l > 0, l < 1 else { continue }
            let head = 0.2 + 0.7 * p.speed * easeOut(l)
            let length = 0.2 * (1 - l) + 0.03
            let c = head - length / 2
            out.append(CosmeticPrimitive(kind: .streak, x: cos(p.angle) * c, y: sin(p.angle) * c, size: length,
                                         rotation: p.angle, opacity: fadeOut(l, from: 0.45), colorIndex: p.colorIndex,
                                         lineWidth: 0.04, additive: true).tracked(i))
        }
        return out
    }

    private static func rainDroop(_ s: CosmeticBurstSpec, _ t: Double) -> [CosmeticPrimitive] {
        var out: [CosmeticPrimitive] = []
        for (i, p) in s.particles.enumerated() {
            let l = local(t, p.delay, 0.42 * p.speed)
            guard l > 0, l < 1 else { continue }
            let y = -0.6 + 0.75 * l
            out.append(CosmeticPrimitive(kind: .drop, x: p.angle - 0.08 * l, y: y, size: 0.16, rotation: .pi / 2 + 0.12,
                                         opacity: bell(l) * fadeOut(t, from: 0.8), colorIndex: p.colorIndex,
                                         lineWidth: 0.028, additive: true).tracked(i))
        }
        // Sprite drops in, then droops (gentle squash).
        let drop = 1 - easeOutBack(min(1, t / 0.3))
        let droop = easeOut(local(t, 0.35, 0.4))
        let sx = 1 + 0.04 * droop, sy = 1 - 0.06 * droop
        out.append(CosmeticPrimitive(kind: .sprite, x: 0, y: 0.05 - 0.3 * drop, size: 1.5 * sx, aspect: sy / sx,
                                     opacity: clamp01(t / 0.15) * fadeOut(t, from: 0.8)).tracked(100))
        return out
    }
}

// MARK: - Timeline (pure): a burst as per-track keyframes
//
// QA-02. Instead of re-running the frame function and rasterising on the main
// thread every display frame, the renderer samples a burst ONCE when it fires
// and hands Core Animation one keyframed layer per track; the render server
// interpolates and composites it off the main thread. Sampling is pure, so the
// bounds above stay unit-testable on exactly what the renderer animates.

/// One primitive followed across a whole burst.
struct CosmeticEffectTrack: Equatable {
    let id: Int
    let kind: CosmeticPrimitive.Kind
    let colorIndex: Int
    let additive: Bool
    /// One entry per sample time; nil = not drawn at that sample.
    var samples: [CosmeticPrimitive?]

    /// Geometry for every sample: gaps take the nearest drawn sample (so a layer
    /// never flies in from the origin); `opacity(at:)` is 0 there.
    var filledSamples: [CosmeticPrimitive] {
        var out = samples
        var last: CosmeticPrimitive?
        for i in out.indices { if let s = out[i] { last = s } else if let last { out[i] = last } }
        var next: CosmeticPrimitive?
        for i in out.indices.reversed() { if let s = out[i] { next = s } else if let next { out[i] = next } }
        return out.compactMap { $0 }
    }

    func opacity(at index: Int) -> Double { samples[index].map { min(1, max(0, $0.opacity)) } ?? 0 }
}

enum CosmeticEffectTimeline {
    /// Keyframes per second. Core Animation interpolates between them at the
    /// display rate, so motion is smoother than the old 30 Hz Canvas redraw.
    static let sampleRate: Double = 30
    /// Primitives fainter than this are not drawn (same threshold as the painter).
    static let minOpacity = 0.003

    /// Normalised progress values 0…1 (last = 1, where every burst is empty).
    static func sampleTimes(lifetime: TimeInterval) -> [Double] {
        let n = max(2, Int((lifetime * sampleRate).rounded(.up)) + 1)
        return (0..<n).map { Double($0) / Double(n - 1) }
    }

    /// Tracks in back-to-front drawing order (the order primitives are emitted in).
    static func tracks(for spec: CosmeticBurstSpec) -> (times: [Double], tracks: [CosmeticEffectTrack]) {
        let times = sampleTimes(lifetime: spec.lifetime)
        var order: [Int] = []
        var byID: [Int: CosmeticEffectTrack] = [:]
        for (k, t) in times.enumerated() {
            let prims = CosmeticEffectFrames.primitives(for: spec, progress: t).filter { $0.opacity > minOpacity }
            for (j, p) in prims.enumerated() {
                if byID[p.track] == nil {
                    byID[p.track] = CosmeticEffectTrack(id: p.track, kind: p.kind, colorIndex: p.colorIndex,
                                                        additive: p.additive,
                                                        samples: Array(repeating: nil, count: times.count))
                    // Insert before the first already-known track drawn after it in this frame.
                    let later = prims[(j + 1)...].map(\.track)
                    if let at = order.firstIndex(where: { later.contains($0) }) { order.insert(p.track, at: at) } else { order.append(p.track) }
                }
                byID[p.track]?.samples[k] = p
            }
        }
        return (times, order.compactMap { byID[$0] })
    }
}
