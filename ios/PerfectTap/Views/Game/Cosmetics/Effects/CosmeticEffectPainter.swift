import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Cosmetic effects: Canvas rasteriser
//
// Draws the primitives produced by CosmeticEffectFrames. No state, no I/O
// except the sprite cache (asset-catalog lookups are cached and can be
// preloaded on round setup via `CosmeticSpriteCache.shared.preload(_:)`).

/// Thread-safe cache of effect sprites (asset catalog → UIImage).
final class CosmeticSpriteCache {
    static let shared = CosmeticSpriteCache()

    private let lock = NSLock()
    private var images: [String: UIImage] = [:]
    private var missing: Set<String> = []

    func image(named name: String) -> UIImage? {
        lock.lock(); defer { lock.unlock() }
        if let img = images[name] { return img }
        if missing.contains(name) { return nil }
        if let img = UIImage(named: name) { images[name] = img; return img }
        missing.insert(name)
        return nil
    }

    /// Warm the cache for every sprite the resolved loadout can draw (call on round setup).
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
