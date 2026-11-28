import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Cosmetic effects: rendering
//
// Two renderers draw the primitives produced by CosmeticEffectFrames:
//  * CosmeticEffectCARenderer (gameplay, Studio, Game Over) — samples a burst
//    once when it fires and animates pre-rasterised sprites / shape layers with
//    Core Animation, so no per-frame work runs on the main thread (QA-02);
//  * CosmeticEffectPainter (reference) — the original immediate-mode Canvas
//    drawing, kept for filmstrips and as the visual reference of each shape.
// No I/O on the tap path: asset sprites and shape sprites are warmed off the
// main thread (`CosmeticEffectAssets.warm`) and looked up from memory.

/// Thread-safe cache of effect sprites (asset catalog → decoded UIImage).
final class CosmeticSpriteCache {
    static let shared = CosmeticSpriteCache()

    private let lock = NSLock()
    private var images: [String: UIImage] = [:]
    private var missing: Set<String> = []

    func image(named name: String) -> UIImage? {
        lock.lock()
        if let img = images[name] { lock.unlock(); return img }
        if missing.contains(name) { lock.unlock(); return nil }
        lock.unlock()
        // Fallback only (normally warmed): look up outside the lock.
        let loaded = UIImage(named: name)
        lock.lock(); defer { lock.unlock() }
        if let img = images[name] { return img }
        if let loaded { images[name] = loaded } else { missing.insert(name) }
        return loaded
    }

    /// Lookup + decode (call off the main thread). A no-op for names already cached.
    func warm(named name: String) {
        lock.lock()
        let known = images[name] != nil || missing.contains(name)
        lock.unlock()
        guard !known else { return }
        let decoded = UIImage(named: name).map { $0.preparingForDisplay() ?? $0 }
        lock.lock(); defer { lock.unlock() }
        if images[name] != nil || missing.contains(name) { return }
        if let decoded { images[name] = decoded } else { missing.insert(name) }
    }

    /// Every sprite the resolved loadout can draw (synchronous lookup; cheap once warmed).
    func preload(_ resolved: ResolvedCosmetics) {
        for slot in CosmeticSlot.effectSlots {
            if let name = resolved.item(for: slot).assets.imageName { _ = image(named: name) }
        }
    }
}

enum CosmeticEffectPainter {

    static func draw(_ burst: CosmeticBurst, now: TimeInterval, in context: inout GraphicsContext,
                     size: CGSize, origin: UnitPoint) {
        let t = burst.progress(at: now)
        guard t >= 0, t < 1 else { return }
        draw(spec: burst.spec, progress: t, in: &context, size: size, origin: origin)
    }

    static func draw(spec: CosmeticBurstSpec, progress t: Double, in context: inout GraphicsContext,
                     size: CGSize, origin: UnitPoint) {
        draw(spec: spec, progress: t, in: &context,
             radius: Double(CosmeticEffectBounds.radius(for: size)),
             center: CGPoint(x: size.width * origin.x, y: size.height * origin.y))
    }

    /// Explicit geometry: lets the layer draw into a canvas cropped around the
    /// burst (same R as the full layer) instead of a full-screen canvas.
    static func draw(_ burst: CosmeticBurst, now: TimeInterval, in context: inout GraphicsContext,
                     radius: Double, center: CGPoint) {
        let t = burst.progress(at: now)
        guard t >= 0, t < 1 else { return }
        draw(spec: burst.spec, progress: t, in: &context, radius: radius, center: center)
    }

    static func draw(spec: CosmeticBurstSpec, progress t: Double, in context: inout GraphicsContext,
                     radius R: Double, center: CGPoint) {
        guard R > 0 else { return }
        let sprite: Image? = spec.spriteName.flatMap { CosmeticSpriteCache.shared.image(named: $0) }.map { Image(uiImage: $0) }

        for p in CosmeticEffectFrames.primitives(for: spec, progress: t) where p.opacity > 0.003 {
            var g = context
            g.opacity = min(1, p.opacity)
            if p.additive { g.blendMode = .plusLighter }
            g.translateBy(x: center.x + p.x * R, y: center.y + p.y * R)
            let color = spec.rgba(p.colorIndex).color
            let s = p.size * R
            switch p.kind {
            case .glow:
                glow(&g, radius: s, aspect: p.aspect, color: color)
            case .ring:
                let rect = CGRect(x: -s, y: -s * p.aspect, width: 2 * s, height: 2 * s * p.aspect)
                let path = Path(ellipseIn: rect)
                let lw = max(0.5, p.lineWidth * R)
                var halo = g
                halo.opacity *= 0.35
                halo.blendMode = .plusLighter
                halo.stroke(path, with: .color(color), lineWidth: lw * 3)
                g.stroke(path, with: .color(color), lineWidth: lw)
                g.opacity *= 0.6
                g.stroke(path, with: .color(.white), lineWidth: lw * 0.35)
            case .droplet:
                g.rotate(by: .radians(p.rotation))
                let body = Path(ellipseIn: CGRect(x: -s * 0.8, y: -s * 0.5, width: s * 1.6, height: s))
                g.fill(body, with: .color(color))
                g.opacity *= 0.75
                g.fill(Path(ellipseIn: CGRect(x: s * 0.05, y: -s * 0.32, width: s * 0.45, height: s * 0.3)), with: .color(.white))
            case .streak:
                g.rotate(by: .radians(p.rotation))
                var path = Path()
                path.move(to: CGPoint(x: -s / 2, y: 0))
                path.addLine(to: CGPoint(x: s / 2, y: 0))
                let lw = max(0.8, p.lineWidth * R)
                let shade = GraphicsContext.Shading.linearGradient(
                    Gradient(colors: [color.opacity(0), color]), startPoint: CGPoint(x: -s / 2, y: 0), endPoint: CGPoint(x: s / 2, y: 0))
                g.stroke(path, with: shade, style: StrokeStyle(lineWidth: lw, lineCap: .round))
                g.opacity *= 0.8
                g.stroke(path, with: .linearGradient(Gradient(colors: [.white.opacity(0), .white]),
                                                     startPoint: CGPoint(x: 0, y: 0), endPoint: CGPoint(x: s / 2, y: 0)),
                         style: StrokeStyle(lineWidth: lw * 0.4, lineCap: .round))
            case .star:
                var halo = g
                halo.blendMode = .plusLighter
                glow(&halo, radius: s * 1.7, aspect: 1, color: color.opacity(0.55))
                g.rotate(by: .radians(p.rotation))
                let path = starPath(points: 5, outer: s, inner: s * 0.46)
                g.fill(path, with: .linearGradient(Gradient(colors: [.white, color]),
                                                   startPoint: CGPoint(x: 0, y: -s), endPoint: CGPoint(x: 0, y: s)))
                g.stroke(path, with: .color(color), lineWidth: max(0.6, s * 0.08))
            case .twinkle:
                var halo = g
                halo.blendMode = .plusLighter
                glow(&halo, radius: s * 1.4, aspect: 1, color: color.opacity(0.6))
                g.rotate(by: .radians(p.rotation))
                g.fill(twinklePath(s), with: .color(color))
                g.fill(twinklePath(s * 0.55), with: .color(.white))
            case .sprite:
                g.rotate(by: .radians(p.rotation))
                let rect = CGRect(x: -s / 2, y: -s * p.aspect / 2, width: s, height: s * p.aspect)
                if let sprite {
                    g.draw(sprite, in: rect)
                } else if spec.style == .feathers {
                    g.fill(Path(ellipseIn: rect.insetBy(dx: 0, dy: s * 0.3)), with: .color(color))
                } else {
                    glow(&g, radius: s * 0.4, aspect: 1, color: color)
                }
            case .puff:
                g.rotate(by: .radians(p.rotation))
                let lobes = puffPath(s)
                g.fill(lobes, with: .color(color))
                if spec.style == .fluff {
                    g.stroke(lobes, with: .color(spec.rgba(1).color.opacity(0.55)), lineWidth: max(0.6, s * 0.08))
                }
                g.opacity *= 0.35
                g.fill(Path(ellipseIn: CGRect(x: -s * 0.55, y: -s * 0.75, width: s * 0.7, height: s * 0.45)), with: .color(.white))
            case .slash:
                g.rotate(by: .radians(p.rotation))
                let w = max(1, p.lineWidth * R)
                let path = slashPath(length: s, width: w, reveal: p.reveal)
                var halo = g
                halo.opacity *= 0.4
                halo.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: w * 1.6, lineJoin: .round))
                g.fill(path, with: .color(color))
                g.fill(slashPath(length: s, width: w * 0.35, reveal: p.reveal), with: .color(.white.opacity(0.85)))
            case .drop:
                g.rotate(by: .radians(p.rotation))
                var path = Path()
                path.move(to: CGPoint(x: -s / 2, y: 0))
                path.addLine(to: CGPoint(x: s / 2, y: 0))
                g.stroke(path, with: .linearGradient(Gradient(colors: [color.opacity(0), color]),
                                                     startPoint: CGPoint(x: -s / 2, y: 0), endPoint: CGPoint(x: s / 2, y: 0)),
                         style: StrokeStyle(lineWidth: max(1, p.lineWidth * R), lineCap: .round))
            case .burst:
                g.rotate(by: .radians(p.rotation))
                var halo = g
                halo.blendMode = .plusLighter
                glow(&halo, radius: s * 1.35, aspect: 1, color: color.opacity(0.6))
                g.fill(burstPath(s), with: .color(color))
                g.fill(burstPath(s * 0.66), with: .color(spec.rgba(1).color))
                g.fill(Path(ellipseIn: CGRect(x: -s * 0.24, y: -s * 0.24, width: s * 0.48, height: s * 0.48)),
                       with: .color(Color(red: 1, green: 0.97, blue: 0.85)))
            case .dot:
                g.fill(Path(ellipseIn: CGRect(x: -s, y: -s, width: 2 * s, height: 2 * s)), with: .color(color))
            }
        }
    }

    // MARK: Shapes

    private static func glow(_ g: inout GraphicsContext, radius: Double, aspect: Double, color: Color) {
        guard radius > 0.1 else { return }
        var e = g
        e.scaleBy(x: 1, y: aspect)
        e.fill(Path(ellipseIn: CGRect(x: -radius, y: -radius, width: 2 * radius, height: 2 * radius)),
               with: .radialGradient(Gradient(colors: [color, color.opacity(0.35), color.opacity(0)]),
                                     center: .zero, startRadius: 0, endRadius: radius))
    }

    static func starPath(points: Int, outer: Double, inner: Double) -> Path {
        var path = Path()
        for i in 0..<(points * 2) {
            let r = i % 2 == 0 ? outer : inner
            let a = Double(i) * .pi / Double(points) - .pi / 2
            let pt = CGPoint(x: cos(a) * r, y: sin(a) * r)
            if i == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
        }
        path.closeSubpath()
        return path
    }

    static func twinklePath(_ r: Double) -> Path {
        var path = Path()
        let k = r * 0.14
        path.move(to: CGPoint(x: 0, y: -r))
        path.addQuadCurve(to: CGPoint(x: r, y: 0), control: CGPoint(x: k, y: -k))
        path.addQuadCurve(to: CGPoint(x: 0, y: r), control: CGPoint(x: k, y: k))
        path.addQuadCurve(to: CGPoint(x: -r, y: 0), control: CGPoint(x: -k, y: k))
        path.addQuadCurve(to: CGPoint(x: 0, y: -r), control: CGPoint(x: -k, y: -k))
        path.closeSubpath()
        return path
    }

    static func puffPath(_ s: Double) -> Path {
        var path = Path()
        for (dx, dy, r) in [(-0.45, 0.12, 0.66), (0.45, 0.16, 0.6), (0.0, -0.2, 0.8), (0.05, 0.3, 0.55)] {
            path.addEllipse(in: CGRect(x: (dx - r) * s, y: (dy - r) * s, width: 2 * r * s, height: 2 * r * s))
        }
        return path
    }

    static func slashPath(length: Double, width: Double, reveal: Double) -> Path {
        let x0 = -length / 2, x1 = x0 + length * max(0.01, min(1, reveal))
        let mid = x0 + (x1 - x0) * 0.4
        var path = Path()
        path.move(to: CGPoint(x: x0, y: 0))
        path.addQuadCurve(to: CGPoint(x: x1, y: 0), control: CGPoint(x: mid, y: -width))
        path.addQuadCurve(to: CGPoint(x: x0, y: 0), control: CGPoint(x: mid, y: width * 0.6))
        path.closeSubpath()
        return path
    }

    static func burstPath(_ r: Double) -> Path {
        var path = Path()
        let spikes = 10
        for i in 0..<(spikes * 2) {
            let jitter = Double((i * 37) % 5) / 25
            let rr = i % 2 == 0 ? r * (0.9 + jitter) : r * (0.55 + jitter * 0.5)
            let a = Double(i) * .pi / Double(spikes)
            let pt = CGPoint(x: cos(a) * rr, y: sin(a) * rr)
            if i == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
        }
        path.closeSubpath()
        return path
    }
}

// MARK: - Shape sprites (pre-rasterised once, drawn by Core Animation)

/// A pre-rasterised primitive shape in one colour. Shapes whose look only
/// scales (glow, droplet, star, twinkle, puff, burst, dot, streak) become
/// sprites; rings and slashes change line width / reveal independently of their
/// size and stay CAShapeLayers.
struct CosmeticSpriteKey: Hashable {
    enum Shape: Hashable {
        case glow, droplet, streak, streakCore, star, twinkle, puff, puffStroked, burst, dot, featherFallback
    }
    let shape: Shape
    let color: CosmeticRGBA
    var color2: CosmeticRGBA? = nil

    /// Size of the shape's `size` parameter (s) the sprite is drawn at, in points.
    /// Streaks: x = length, y = line width (they scale non-uniformly).
    var reference: CGSize {
        switch shape {
        case .glow:                  return CGSize(width: 64, height: 64)
        case .droplet:               return CGSize(width: 16, height: 16)
        case .streak, .streakCore:   return CGSize(width: 48, height: 6)
        case .star, .twinkle:        return CGSize(width: 24, height: 24)
        case .puff, .puffStroked:    return CGSize(width: 32, height: 32)
        case .burst:                 return CGSize(width: 56, height: 56)
        case .dot:                   return CGSize(width: 8, height: 8)
        case .featherFallback:       return CGSize(width: 32, height: 32)
        }
    }

    /// Bitmap size in points (centred on the primitive's origin).
    var canvas: CGSize {
        let r = reference
        switch shape {
        case .glow, .dot:            return CGSize(width: 2 * r.width + 2, height: 2 * r.height + 2)
        case .droplet:               return CGSize(width: 1.6 * r.width + 2, height: r.width + 2)
        case .streak, .streakCore:   return CGSize(width: r.width + r.height + 2, height: r.height + 2)
        case .star, .twinkle:        return CGSize(width: 2.2 * r.width, height: 2.2 * r.width)
        case .puff, .puffStroked:    return CGSize(width: 2.4 * r.width, height: 2.4 * r.width)
        case .burst:                 return CGSize(width: 2.3 * r.width, height: 2.3 * r.width)
        case .featherFallback:       return CGSize(width: r.width + 2, height: 0.4 * r.width + 2)
        }
    }
}

/// Thread-safe cache of shape sprites. Filled off the main thread by
/// `CosmeticEffectAssets.warm`; a miss at fire time (not warmed yet) is drawn
/// synchronously once and cached — counted in `syncMisses` for tests.
final class CosmeticShapeSpriteAtlas {
    static let shared = CosmeticShapeSpriteAtlas()

    private let lock = NSLock()
    private var sprites: [CosmeticSpriteKey: CGImage] = [:]
    private(set) var syncMisses = 0

    /// Bitmap scale. Glows are soft, so 2× is enough for them.
    static func scale(for key: CosmeticSpriteKey, screenScale: CGFloat) -> CGFloat {
        key.shape == .glow ? min(2, screenScale) : screenScale
    }

    func contains(_ key: CosmeticSpriteKey) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return sprites[key] != nil
    }

    func image(for key: CosmeticSpriteKey, screenScale: CGFloat) -> CGImage? {
        lock.lock()
        if let hit = sprites[key] { lock.unlock(); return hit }
        syncMisses += 1
        lock.unlock()
        return render(key, screenScale: screenScale)
    }

    func warm(_ keys: Set<CosmeticSpriteKey>, screenScale: CGFloat) {
        for key in keys where !contains(key) { _ = render(key, screenScale: screenScale) }
    }

    func removeAll() {
        lock.lock(); sprites.removeAll(); syncMisses = 0; lock.unlock()
    }

    @discardableResult
    private func render(_ key: CosmeticSpriteKey, screenScale: CGFloat) -> CGImage? {
        let image = CosmeticShapeRasterizer.image(key, scale: Self.scale(for: key, screenScale: screenScale))
        lock.lock(); defer { lock.unlock() }
        if let existing = sprites[key] { return existing }
        sprites[key] = image
        return image
    }
}

/// Core Graphics versions of CosmeticEffectPainter's shapes (same geometry and
/// colours), drawn once per colour at the key's reference size.
enum CosmeticShapeRasterizer {
    static func cg(_ c: CosmeticRGBA, alpha: Double = 1) -> CGColor {
        UIColor(red: c.r, green: c.g, blue: c.b, alpha: c.a * alpha).cgColor
    }

    static let white = CosmeticRGBA(r: 1, g: 1, b: 1)
    static let cream = CosmeticRGBA(r: 1, g: 0.97, b: 0.85)

    static func image(_ key: CosmeticSpriteKey, scale: CGFloat) -> CGImage? {
        let size = key.canvas
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let image = renderer.image { r in
            let ctx = r.cgContext
            ctx.translateBy(x: size.width / 2, y: size.height / 2)
            draw(key, in: ctx)
        }
        return image.cgImage
    }

    private static func gradient(_ colors: [CGColor], _ locations: [CGFloat]) -> CGGradient? {
        CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors as CFArray, locations: locations)
    }

    private static func draw(_ key: CosmeticSpriteKey, in ctx: CGContext) {
        let c = key.color
        let s = key.reference.width
        switch key.shape {
        case .glow:
            if let g = gradient([cg(c), cg(c, alpha: 0.35), cg(c, alpha: 0)], [0, 0.5, 1]) {
                ctx.drawRadialGradient(g, startCenter: .zero, startRadius: 0, endCenter: .zero, endRadius: s, options: [])
            }
        case .droplet:
            ctx.setFillColor(cg(c))
            ctx.fillEllipse(in: CGRect(x: -s * 0.8, y: -s * 0.5, width: s * 1.6, height: s))
            ctx.setFillColor(cg(white, alpha: 0.75))
            ctx.fillEllipse(in: CGRect(x: s * 0.05, y: -s * 0.32, width: s * 0.45, height: s * 0.3))
        case .streak, .streakCore:
            let length = key.reference.width, width = key.reference.height
            strokeGradientLine(ctx, from: -length / 2, to: length / 2, width: width,
                               colors: [cg(c, alpha: 0), cg(c)], gradientFrom: -length / 2, gradientTo: length / 2)
            if key.shape == .streakCore {
                ctx.setAlpha(0.8)
                strokeGradientLine(ctx, from: -length / 2, to: length / 2, width: width * 0.4,
                                   colors: [cg(white, alpha: 0), cg(white)], gradientFrom: 0, gradientTo: length / 2)
                ctx.setAlpha(1)
            }
        case .star:
            let path = CosmeticEffectPainter.starPath(points: 5, outer: s, inner: s * 0.46).cgPath
            ctx.saveGState()
            ctx.addPath(path); ctx.clip()
            if let g = gradient([cg(white), cg(c)], [0, 1]) {
                ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: -s), end: CGPoint(x: 0, y: s),
                                       options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
            }
            ctx.restoreGState()
            ctx.addPath(path)
            ctx.setStrokeColor(cg(c)); ctx.setLineWidth(max(0.6, s * 0.08)); ctx.strokePath()
        case .twinkle:
            ctx.addPath(CosmeticEffectPainter.twinklePath(s).cgPath); ctx.setFillColor(cg(c)); ctx.fillPath()
            ctx.addPath(CosmeticEffectPainter.twinklePath(s * 0.55).cgPath); ctx.setFillColor(cg(white)); ctx.fillPath()
        case .puff, .puffStroked:
            let lobes = CosmeticEffectPainter.puffPath(s).cgPath
            ctx.addPath(lobes); ctx.setFillColor(cg(c)); ctx.fillPath()
            if key.shape == .puffStroked, let stroke = key.color2 {
                ctx.addPath(lobes); ctx.setStrokeColor(cg(stroke, alpha: 0.55))
                ctx.setLineWidth(max(0.6, s * 0.08)); ctx.strokePath()
            }
            ctx.setFillColor(cg(white, alpha: 0.35))
            ctx.fillEllipse(in: CGRect(x: -s * 0.55, y: -s * 0.75, width: s * 0.7, height: s * 0.45))
        case .burst:
            ctx.addPath(CosmeticEffectPainter.burstPath(s).cgPath); ctx.setFillColor(cg(c)); ctx.fillPath()
            ctx.addPath(CosmeticEffectPainter.burstPath(s * 0.66).cgPath); ctx.setFillColor(cg(key.color2 ?? c)); ctx.fillPath()
            ctx.setFillColor(cg(cream))
            ctx.fillEllipse(in: CGRect(x: -s * 0.24, y: -s * 0.24, width: s * 0.48, height: s * 0.48))
        case .dot:
            ctx.setFillColor(cg(c)); ctx.fillEllipse(in: CGRect(x: -s, y: -s, width: 2 * s, height: 2 * s))
        case .featherFallback:
            ctx.setFillColor(cg(c)); ctx.fillEllipse(in: CGRect(x: -s / 2, y: -s * 0.2, width: s, height: s * 0.4))
        }
    }

    /// Round-capped line along x filled with a horizontal gradient (SwiftUI's
    /// gradient-stroked path in the painter).
    private static func strokeGradientLine(_ ctx: CGContext, from x0: CGFloat, to x1: CGFloat, width: CGFloat,
                                           colors: [CGColor], gradientFrom g0: CGFloat, gradientTo g1: CGFloat) {
        ctx.saveGState()
        ctx.move(to: CGPoint(x: x0, y: 0)); ctx.addLine(to: CGPoint(x: x1, y: 0))
        ctx.setLineWidth(width); ctx.setLineCap(.round)
        ctx.replacePathWithStrokedPath(); ctx.clip()
        if let g = gradient(colors, [0, 1]) {
            ctx.drawLinearGradient(g, start: CGPoint(x: g0, y: 0), end: CGPoint(x: g1, y: 0),
                                   options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        }
        ctx.restoreGState()
    }
}

// MARK: - Core Animation renderer (QA-02)

/// Builds one self-animating layer tree per burst. Everything is decided when
/// the burst fires (≤ ~55 samples × ≤ 24 tracks of pure math); afterwards the
/// render server interpolates the keyframes, so a live burst costs the app's
/// main thread nothing per frame — unlike the former TimelineView + Canvas,
/// which re-evaluated SwiftUI and rasterised gradients on the main thread at 30 Hz.
enum CosmeticEffectCARenderer {

    /// What one track draws (decided from kind, style and colour; shared by the
    /// renderer and by `spriteKeys`, so warming covers exactly what fires).
    enum Visual {
        case sprite(CosmeticSpriteKey, halo: (key: CosmeticSpriteKey, radius: Double, opacity: Float)?)
        case asset(name: String)
        case ring(CosmeticRGBA)
        case slash(CosmeticRGBA)
    }

    static func visual(for track: CosmeticEffectTrack, spec: CosmeticBurstSpec, assetAvailable: (String) -> Bool) -> Visual {
        let c = spec.rgba(track.colorIndex)
        func glowHalo(_ radius: Double, _ opacity: Float) -> (key: CosmeticSpriteKey, radius: Double, opacity: Float) {
            (CosmeticSpriteKey(shape: .glow, color: c), radius, opacity)
        }
        switch track.kind {
        case .glow:    return .sprite(CosmeticSpriteKey(shape: .glow, color: c), halo: nil)
        case .ring:    return .ring(c)
        case .slash:   return .slash(c)
        case .droplet: return .sprite(CosmeticSpriteKey(shape: .droplet, color: c), halo: nil)
        case .streak:  return .sprite(CosmeticSpriteKey(shape: .streakCore, color: c), halo: nil)
        case .drop:    return .sprite(CosmeticSpriteKey(shape: .streak, color: c), halo: nil)
        case .star:    return .sprite(CosmeticSpriteKey(shape: .star, color: c), halo: glowHalo(1.7, 0.55))
        case .twinkle: return .sprite(CosmeticSpriteKey(shape: .twinkle, color: c), halo: glowHalo(1.4, 0.6))
        case .burst:   return .sprite(CosmeticSpriteKey(shape: .burst, color: c, color2: spec.rgba(1)), halo: glowHalo(1.35, 0.6))
        case .dot:     return .sprite(CosmeticSpriteKey(shape: .dot, color: c), halo: nil)
        case .puff:
            return spec.style == .fluff
                ? .sprite(CosmeticSpriteKey(shape: .puffStroked, color: c, color2: spec.rgba(1)), halo: nil)
                : .sprite(CosmeticSpriteKey(shape: .puff, color: c), halo: nil)
        case .sprite:
            if let name = spec.spriteName, assetAvailable(name) { return .asset(name: name) }
            // Same fallbacks as the painter: feathers → ellipse, others → small glow.
            return spec.style == .feathers
                ? .sprite(CosmeticSpriteKey(shape: .featherFallback, color: c), halo: nil)
                : .sprite(CosmeticSpriteKey(shape: .glow, color: c), halo: nil)
        }
    }

    /// Shape sprites a burst needs (for warming).
    static func spriteKeys(for spec: CosmeticBurstSpec, assetAvailable: (String) -> Bool) -> Set<CosmeticSpriteKey> {
        var keys = Set<CosmeticSpriteKey>()
        for track in CosmeticEffectTimeline.tracks(for: spec).tracks {
            if case let .sprite(key, halo) = visual(for: track, spec: spec, assetAvailable: assetAvailable) {
                keys.insert(key)
                if let halo { keys.insert(halo.key) }
            }
        }
        return keys
    }

    private static let additiveFilter = "plusL"   // CA's plus-lighter (SwiftUI .plusLighter)

    /// A layer tree for `spec`, centred at `center` in the host's coordinates.
    /// `elapsed` > 0 starts the burst part-way (e.g. when the host laid out late).
    static func makeLayer(spec: CosmeticBurstSpec, radius R: CGFloat, center: CGPoint, elapsed: TimeInterval,
                          screenScale: CGFloat) -> CALayer {
        let (times, tracks) = CosmeticEffectTimeline.tracks(for: spec)
        let keyTimes = times.map { NSNumber(value: $0) }
        let begin = CACurrentMediaTime() - elapsed
        let root = CALayer()
        root.bounds = .zero
        root.position = center
        root.allowsGroupOpacity = false
        let sprites = CosmeticSpriteCache.shared
        for track in tracks {
            let filled = track.filledSamples
            guard filled.count == times.count else { continue }
            let layer = CALayer()
            layer.bounds = .zero
            layer.allowsGroupOpacity = false
            layer.opacity = 0   // model value = end state (every burst ends empty)
            var transforms: [NSValue] = []
            let visual = self.visual(for: track, spec: spec, assetAvailable: { sprites.image(named: $0) != nil })
            switch visual {
            case let .sprite(key, halo):
                if let halo {
                    let s = key.reference.width
                    let h = CALayer()
                    h.contents = CosmeticShapeSpriteAtlas.shared.image(for: halo.key, screenScale: screenScale)
                    // The glow sprite is 2·ref + 2 pt wide for radius ref.
                    let side = 2 * halo.radius * Double(s) * Double(halo.key.canvas.width) / Double(2 * halo.key.reference.width)
                    h.bounds = CGRect(x: 0, y: 0, width: side, height: side)
                    h.opacity = halo.opacity
                    h.compositingFilter = additiveFilter
                    layer.addSublayer(h)
                }
                let main = CALayer()
                main.contents = CosmeticShapeSpriteAtlas.shared.image(for: key, screenScale: screenScale)
                main.bounds = CGRect(origin: .zero, size: key.canvas)
                if track.additive { main.compositingFilter = additiveFilter }
                layer.addSublayer(main)
                transforms = filled.map { NSValue(caTransform3D: spriteTransform($0, kind: track.kind, key: key, R: R)) }
            case let .asset(name):
                let main = CALayer()
                if let image = sprites.image(named: name) {
                    main.contents = image.cgImage
                    main.contentsScale = image.scale
                }
                main.bounds = CGRect(x: 0, y: 0, width: 64, height: 64)
                if track.additive { main.compositingFilter = additiveFilter }
                layer.addSublayer(main)
                transforms = filled.map { p in
                    let s = CGFloat(p.size) * R / 64
                    return NSValue(caTransform3D: CATransform3DScale(CATransform3DMakeRotation(CGFloat(p.rotation), 0, 0, 1),
                                                                     s, s * CGFloat(p.aspect), 1))
                }
            case let .ring(color):
                let paths = filled.map { p -> CGPath in
                    let s = CGFloat(p.size) * R
                    return CGPath(ellipseIn: CGRect(x: -s, y: -s * CGFloat(p.aspect), width: 2 * s, height: 2 * s * CGFloat(p.aspect)),
                                  transform: nil)
                }
                let widths = filled.map { max(0.5, CGFloat($0.lineWidth) * R) }
                // halo (×3, 35 %, always additive) · colour stroke · white core (×0.35, 60 %)
                for (mult, alpha, white, additive) in [(CGFloat(3), Float(0.35), false, true),
                                                       (1, 1, false, track.additive),
                                                       (0.35, 0.6, true, track.additive)] {
                    let shape = CAShapeLayer()
                    shape.fillColor = nil
                    shape.strokeColor = CosmeticShapeRasterizer.cg(white ? CosmeticShapeRasterizer.white : color)
                    shape.opacity = alpha
                    if additive { shape.compositingFilter = additiveFilter }
                    shape.path = paths.last
                    shape.lineWidth = widths.last.map { $0 * mult } ?? 1
                    layer.addSublayer(shape)
                    shape.add(keyframes("path", paths, keyTimes, spec.lifetime, begin), forKey: "path")
                    shape.add(keyframes("lineWidth", widths.map { $0 * mult }, keyTimes, spec.lifetime, begin), forKey: "lineWidth")
                }
                transforms = filled.map { _ in NSValue(caTransform3D: CATransform3DIdentity) }
            case let .slash(color):
                let full = filled.map { p -> CGPath in
                    CosmeticEffectPainter.slashPath(length: p.size * Double(R), width: max(1, p.lineWidth * Double(R)), reveal: p.reveal).cgPath
                }
                let core = filled.map { p -> CGPath in
                    CosmeticEffectPainter.slashPath(length: p.size * Double(R), width: max(1, p.lineWidth * Double(R)) * 0.35,
                                                    reveal: p.reveal).cgPath
                }
                let w = filled.map { max(1, CGFloat($0.lineWidth) * R) }
                let halo = CAShapeLayer()
                halo.fillColor = nil
                halo.strokeColor = CosmeticShapeRasterizer.cg(color)
                halo.lineJoin = .round
                halo.opacity = 0.4
                halo.path = full.last
                halo.lineWidth = (w.last ?? 1) * 1.6
                let body = CAShapeLayer()
                body.fillColor = CosmeticShapeRasterizer.cg(color)
                body.path = full.last
                let shine = CAShapeLayer()
                shine.fillColor = CosmeticShapeRasterizer.cg(CosmeticShapeRasterizer.white, alpha: 0.85)
                shine.path = core.last
                for l in [halo, body, shine] {
                    if track.additive { l.compositingFilter = additiveFilter }
                    layer.addSublayer(l)
                }
                halo.add(keyframes("path", full, keyTimes, spec.lifetime, begin), forKey: "path")
                halo.add(keyframes("lineWidth", w.map { $0 * 1.6 }, keyTimes, spec.lifetime, begin), forKey: "lineWidth")
                body.add(keyframes("path", full, keyTimes, spec.lifetime, begin), forKey: "path")
                shine.add(keyframes("path", core, keyTimes, spec.lifetime, begin), forKey: "path")
                transforms = filled.map { NSValue(caTransform3D: CATransform3DMakeRotation(CGFloat($0.rotation), 0, 0, 1)) }
            }
            let positions = filled.map { NSValue(cgPoint: CGPoint(x: CGFloat($0.x) * R, y: CGFloat($0.y) * R)) }
            let opacities = times.indices.map { NSNumber(value: track.opacity(at: $0)) }
            layer.position = positions.last?.cgPointValue ?? .zero
            layer.add(keyframes("position", positions, keyTimes, spec.lifetime, begin), forKey: "position")
            layer.add(keyframes("transform", transforms, keyTimes, spec.lifetime, begin), forKey: "transform")
            layer.add(keyframes("opacity", opacities, keyTimes, spec.lifetime, begin), forKey: "opacity")
            root.addSublayer(layer)
        }
        return root
    }

    /// Rotation · scale that maps the sprite (drawn at its reference size) onto primitive `p`.
    static func spriteTransform(_ p: CosmeticPrimitive, kind: CosmeticPrimitive.Kind, key: CosmeticSpriteKey, R: CGFloat) -> CATransform3D {
        let s = CGFloat(p.size) * R
        let ref = key.reference
        let sx: CGFloat, sy: CGFloat
        switch kind {
        case .streak:
            sx = s / ref.width; sy = max(0.8, CGFloat(p.lineWidth) * R) / ref.height
        case .drop:
            sx = s / ref.width; sy = max(1, CGFloat(p.lineWidth) * R) / ref.height
        case .glow:
            sx = s / ref.width; sy = sx * CGFloat(p.aspect)
        case .sprite:
            // Missing asset fallbacks: feather ellipse (s wide) or glow of radius 0.4 s.
            if key.shape == .glow { sx = 0.4 * s / ref.width; sy = sx } else { sx = s / ref.width; sy = sx * CGFloat(p.aspect) }
        default:
            sx = s / ref.width; sy = sx
        }
        // Glows are not rotated by the painter (radially symmetric anyway).
        let rotation = kind == .glow ? 0 : CGFloat(p.rotation)
        return CATransform3DScale(CATransform3DMakeRotation(rotation, 0, 0, 1), sx, sy, 1)
    }

    private static func keyframes(_ keyPath: String, _ values: [Any], _ keyTimes: [NSNumber],
                                  _ duration: TimeInterval, _ begin: CFTimeInterval) -> CAKeyframeAnimation {
        let a = CAKeyframeAnimation(keyPath: keyPath)
        a.values = values
        a.keyTimes = keyTimes
        a.duration = duration
        a.beginTime = begin
        a.calculationMode = .linear
        a.fillMode = .both
        a.isRemovedOnCompletion = false
        if #available(iOS 15.0, *) {
            a.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
        }
        return a
    }
}

/// Hosts the bursts of one CosmeticEffectLayer. Non-interactive, hidden from
/// accessibility; holds ≤ CosmeticEffectBounds.maxConcurrentBursts layer trees,
/// each removed when its burst ends.
final class CosmeticEffectHostView: UIView {
    var origin = UnitPoint(x: 0.5, y: 0.45)

    private struct Live { let start: TimeInterval; let layer: CALayer }
    private var live: [Int: Live] = [:]
    /// Bursts that arrived before the first layout.
    private var pending: [CosmeticBurst] = []

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        backgroundColor = .clear
        isAccessibilityElement = false
        accessibilityElementsHidden = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    var liveBurstCount: Int { live.count }

    func sync(_ bursts: [CosmeticBurst], now: TimeInterval = Date().timeIntervalSinceReferenceDate) {
        let wanted = Dictionary(bursts.map { ($0.id, $0) }, uniquingKeysWith: { $1 })
        for (id, entry) in live where wanted[id]?.startTime != entry.start {
            entry.layer.removeFromSuperlayer()
            live[id] = nil
        }
        guard bounds.width > 0, bounds.height > 0 else { pending = bursts; return }
        pending = []
        let R = CosmeticEffectBounds.radius(for: bounds.size)
        let center = CGPoint(x: bounds.width * origin.x, y: bounds.height * origin.y)
        let scale = window?.screen.scale ?? max(2, traitCollection.displayScale)
        for burst in bursts where live[burst.id] == nil {
            let elapsed = max(0, now - burst.startTime)
            let remaining = burst.spec.lifetime - elapsed
            guard remaining > 0 else { continue }
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            let tree = CosmeticEffectCARenderer.makeLayer(spec: burst.spec, radius: R, center: center,
                                                          elapsed: elapsed, screenScale: scale)
            layer.addSublayer(tree)
            CATransaction.commit()
            live[burst.id] = Live(start: burst.startTime, layer: tree)
            let id = burst.id
            DispatchQueue.main.asyncAfter(deadline: .now() + remaining + 0.05) { [weak self, weak tree] in
                guard let self, let tree, self.live[id]?.layer === tree else { return }
                tree.removeFromSuperlayer()
                self.live[id] = nil
            }
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if !pending.isEmpty { sync(pending) }
    }
}

/// SwiftUI bridge for CosmeticEffectHostView.
struct CosmeticEffectCAView: UIViewRepresentable {
    let bursts: [CosmeticBurst]
    let origin: UnitPoint

    func makeUIView(context: Context) -> CosmeticEffectHostView { CosmeticEffectHostView() }

    func updateUIView(_ view: CosmeticEffectHostView, context: Context) {
        view.origin = origin
        view.sync(bursts)
    }
}

// MARK: - Warm-up (QA-16)

/// Loads + decodes every image and shape sprite the resolved cosmetics can draw,
/// off the main thread, so neither the round bootstrap nor a tap decodes anything.
enum CosmeticEffectAssets {
    private static let queue = DispatchQueue(label: "perfecttap.cosmetics.warm", qos: .utility)

    /// Call on the main thread (Home appear, round bootstrap). Returns at once.
    static func warm(_ resolved: ResolvedCosmetics, completion: (() -> Void)? = nil) {
        guard resolved != .defaults else { completion?(); return }
        let scale = max(2, UITraitCollection.current.displayScale)
        queue.async {
            CosmeticImageCache.shared.warm(resolved)
            for slot in CosmeticSlot.effectSlots {
                if let name = resolved.item(for: slot).assets.imageName { CosmeticSpriteCache.shared.warm(named: name) }
            }
            CosmeticShapeSpriteAtlas.shared.warm(spriteKeys(for: resolved), screenScale: scale)
            if let completion { DispatchQueue.main.async(execute: completion) }
        }
    }

    /// Every shape sprite any event of `resolved` can draw (full and reduced).
    static func spriteKeys(for resolved: ResolvedCosmetics) -> Set<CosmeticSpriteKey> {
        var keys = Set<CosmeticSpriteKey>()
        let available: (String) -> Bool = { CosmeticSpriteCache.shared.image(named: $0) != nil }
        for event in CosmeticEvent.allCases {
            for level in [EffectsLevel.full, .reduced] {
                guard let spec = CosmeticEffectPlanner.spec(resolved: resolved, trigger: CosmeticEffectTrigger(event: event, sequence: 1),
                                                            level: level) else { continue }
                keys.formUnion(CosmeticEffectCARenderer.spriteKeys(for: spec, assetAvailable: available))
            }
        }
        return keys
    }
}
