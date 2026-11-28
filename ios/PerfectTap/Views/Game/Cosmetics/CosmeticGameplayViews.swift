import SwiftUI
import UIKit

// MARK: - Gameplay cosmetic views
//
// Used by GameView and by the Preview Studio, so the preview is the real thing.
//
// Rules for everything in this file:
//  * The default item renders exactly the pre-Studio view (same shapes, sizes,
//    colours). Themed rendering is a separate branch, so a default loadout
//    cannot be affected by themed-skin changes.
//  * A missing asset never crashes or leaves a blank: themed views fall back to
//    native drawing (tap button) or to the default look (life icons).
//  * No layout influence: these views never change the caller's hit area or
//    the HUD's height. Art is always aspect-fit / aspect-fill, never stretched.

// MARK: - Tap button skin

/// Visual of the wide TAP button. Never sets its own hit area: the caller keeps
/// `TouchDownTapArea` and the 80 pt height / full width unchanged. The TAP label
/// is native text, not part of the artwork.
struct CosmeticTapButtonSkin: View {
    let item: CosmeticItem
    /// Colours of the pre-Studio button (mode gradient) — used by the default skin.
    let fallbackColors: [Color]
    var isPressed: Bool = false
    var label: String = "TAP!"
    var height: CGFloat = 80

    var body: some View {
        if item.isDefault || item.slot != .tapButton {
            // Pre-Studio button, unchanged. Press feedback (scale/opacity) is
            // applied by TouchDownTapArea exactly as before.
            RoundedRectangle(cornerRadius: 20)
                .fill(LinearGradient(colors: fallbackColors, startPoint: .leading, endPoint: .trailing))
                .frame(height: height)
                .overlay(
                    Text(label)
                        .font(.system(size: 24, weight: .black))
                        .tracking(4)
                        .foregroundColor(.white)
                )
        } else {
            ThemedTapButton(item: item, fallbackColors: fallbackColors, isPressed: isPressed,
                            label: label, height: height)
        }
    }
}

/// Glossy capsule drawn natively from the item palette, with optional
/// background art and a leading emblem.
private struct ThemedTapButton: View {
    let item: CosmeticItem
    let fallbackColors: [Color]
    let isPressed: Bool
    let label: String
    let height: CGFloat

    @Environment(\.effectsLevel) private var effects

    private var assets: CosmeticAssetRefs { item.assets }

    /// palette[0] = body, palette[1] = body shade, palette[2] = rim accent.
    private var palette: [CosmeticRGBA] {
        if !assets.palette.isEmpty { return assets.palette }
        if let collection = CosmeticCatalog.collection(id: item.collectionID), !collection.palette.isEmpty {
            return collection.palette
        }
        return CosmeticCatalog.defaultSpec.palette
    }

    private var body0: CosmeticRGBA { palette[0] }
    private var body1: CosmeticRGBA { palette.count > 1 ? palette[1] : palette[0].darkened(0.25) }
    private var accent: CosmeticRGBA { palette.count > 2 ? palette[2] : palette[0].darkened(0.35) }

    private var backgroundArt: UIImage? {
        if isPressed, let pressed = CosmeticImageCache.shared.image(named: assets.secondaryImageName) { return pressed }
        return CosmeticImageCache.shared.image(named: assets.imageName)
    }

    private var emblem: UIImage? { CosmeticImageCache.shared.image(named: assets.emblemImageName) }

    var body: some View {
        let emblemImage = emblem
        GeometryReader { geo in
            let layout = ThemedTapButtonLayout.make(size: geo.size, hasEmblem: emblemImage != nil,
                                                    labelWidth: { ThemedTapButtonLayout.labelWidth(label, fontSize: $0) })
            ZStack(alignment: .topLeading) {
                bodyFill
                // Bottom shade gives the capsule volume.
                Capsule()
                    .fill(LinearGradient(colors: [.clear, .black.opacity(0.24)], startPoint: .center, endPoint: .bottom))
                // Top gloss highlight.
                Capsule()
                    .fill(LinearGradient(colors: [.white.opacity(0.55), .white.opacity(0.06)], startPoint: .top, endPoint: .bottom))
                    .frame(height: height * 0.42)
                    .padding(.horizontal, height * 0.24)
                    .padding(.top, 5)
                    .frame(maxHeight: .infinity, alignment: .top)
                if isPressed {
                    Capsule().fill(Color.black.opacity(0.16))
                }
                // QA-09: the emblem sits inside the capsule. Its art is cut flat at
                // the bottom, so the cut line is placed on the capsule's bottom edge
                // and clipped there, under the rim strokes drawn next.
                if let emblemImage, let frame = layout.emblemFrame {
                    Image(uiImage: emblemImage)
                        .resizable()
                        .scaledToFit()
                        .frame(width: frame.width, height: frame.height)
                        .scaleEffect(isPressed ? 0.92 : 1,
                                     anchor: UnitPoint(x: 0.5, y: ThemedTapButtonLayout.artCutFraction))
                        .position(x: frame.midX, y: frame.midY)
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipShape(Capsule())
                        .allowsHitTesting(false)
                }
                // Inner highlight stroke + coloured rim.
                Capsule()
                    .strokeBorder(Color.white.opacity(0.45), lineWidth: 1.5)
                    .padding(3)
                Capsule()
                    .strokeBorder(accent.color.opacity(0.9), lineWidth: 2.5)
                // QA-10: centred in the space the layout keeps free of the emblem.
                labelText(fontSize: layout.fontSize)
                    .fixedSize()
                    .position(x: layout.labelFrame.midX, y: layout.labelFrame.midY)
                fuseGlow(layout: layout)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .frame(height: height)
        .scaleEffect(isPressed ? 0.96 : 1)
        .animation(.easeOut(duration: 0.08), value: isPressed)
    }

    @ViewBuilder private var bodyFill: some View {
        if let art = backgroundArt {
            // Aspect-fill inside a fixed frame: the art is cropped, never stretched,
            // and its intrinsic size can't widen the button.
            Color.clear
                .overlay(Image(uiImage: art).resizable().scaledToFill())
                .clipShape(Capsule())
        } else {
            Capsule().fill(LinearGradient(
                // Light top → body → slightly deeper, shade-tinted bottom (a light
                // shade such as cream must not wash the bottom out, hence darkened).
                colors: [body0.lightened(0.22).color, body0.color,
                         body0.mixed(with: body1, 0.4).darkened(0.12).color],
                startPoint: .top, endPoint: .bottom))
        }
    }

    private func labelText(fontSize: CGFloat) -> some View {
        // White heavy text with a dark crisp drop + soft shadow: readable on
        // yellow, pink and steel bodies alike.
        Text(label)
            .font(.system(size: fontSize, weight: .black, design: .rounded))
            .tracking(ThemedTapButtonLayout.tracking(fontSize: fontSize))
            .foregroundColor(.white)
            .shadow(color: body1.darkened(0.55).color.opacity(0.9), radius: 0, x: 0, y: 2)
            .shadow(color: .black.opacity(0.35), radius: 3, x: 0, y: 1)
    }

    /// Boom: a short warm glow at the fuse while the finger is down.
    @ViewBuilder private func fuseGlow(layout: ThemedTapButtonLayout) -> some View {
        if assets.pressStyle == .fuseGlow, isPressed, effects.showsGlow, let frame = layout.emblemFrame {
            Circle()
                .fill(RadialGradient(colors: [palette.last?.color ?? .yellow, accent.color.opacity(0.5), .clear],
                                     center: .center, startRadius: 0, endRadius: 18))
                .frame(width: 36, height: 36)
                .opacity(effects.glowStrength)
                // The fuse spark of the bomb art (unit point in the emblem canvas).
                .position(x: frame.minX + frame.width * 0.83, y: frame.minY + frame.height * 0.24)
                .allowsHitTesting(false)
                .transition(.opacity)
        }
    }
}

// MARK: - Themed button layout (QA-09, QA-10)

/// Where a themed tap button puts its emblem and its label, for any size.
/// Pure geometry (unit-tested): the emblem's opaque art never intersects the
/// label box, and the emblem's flat-cut bottom lies on the capsule's bottom edge.
struct ThemedTapButtonLayout: Equatable {
    /// Emblem image frame (square) in button coordinates; nil = no emblem drawn.
    var emblemFrame: CGRect?
    /// Box of the label (estimated text bounds), centred where the label is drawn.
    var labelFrame: CGRect
    var fontSize: CGFloat

    // Emblem canvases (216 px, cos_*_emblem): opaque art spans x 6…209 and
    // y 31…180 px; Boom and Paw are cut flat at 180/177 px (QA-09), Quack ends
    // naturally at 171 px. Constants are conservative fractions of the canvas.
    static let artCutFraction: CGFloat = 0.84
    static let artTopFraction: CGFloat = 0.14
    static let artSideFraction: CGFloat = 0.025
    /// Emblem side / button height, largest first; tried until the label fits.
    static let emblemScales: [CGFloat] = [1.15, 1.0, 0.85, 0.75]
    static let maxFontSize: CGFloat = 26
    static let minFontSize: CGFloat = 12
    /// Space kept between emblem art, label and the capsule's trailing end.
    static func gap(height: CGFloat) -> CGFloat { max(4, height * 0.08) }

    static func preferredFontSize(height: CGFloat) -> CGFloat {
        min(maxFontSize, max(minFontSize, (height * 0.42).rounded()))
    }

    static func tracking(fontSize: CGFloat) -> CGFloat { 4 * fontSize / maxFontSize }

    static func labelHeight(fontSize: CGFloat) -> CGFloat { ceil(fontSize * 1.25) }

    /// Opaque part of the emblem art for an emblem drawn in `frame`, clipped to the button.
    static func artBox(emblemFrame f: CGRect, buttonHeight h: CGFloat) -> CGRect {
        CGRect(x: f.minX + f.width * artSideFraction, y: f.minY + f.height * artTopFraction,
               width: f.width * (1 - 2 * artSideFraction), height: f.height * (artCutFraction - artTopFraction))
            .intersection(CGRect(x: -1_000, y: 0, width: 10_000, height: h))
    }

    static func make(size: CGSize, hasEmblem: Bool, labelWidth: (CGFloat) -> CGFloat) -> ThemedTapButtonLayout {
        let w = max(size.width, 0), h = max(size.height, 1)
        let gap = gap(height: h)
        let preferred = preferredFontSize(height: h)
        let trailingInset = h * 0.25 + gap / 2   // capsule end rounding
        func label(font: CGFloat, from left: CGFloat) -> CGRect? {
            let lw = labelWidth(font), lh = labelHeight(fontSize: font)
            let right = w - trailingInset
            guard right - left >= lw else { return nil }
            return CGRect(x: (left + right - lw) / 2, y: (h - lh) / 2, width: lw, height: lh)
        }
        if hasEmblem {
            var candidates: [(CGFloat, CGFloat)] = emblemScales.map { ($0, preferred) }
            var f = preferred - 1
            while f >= minFontSize { candidates.append((emblemScales.last!, f)); f -= 1 }
            for (scale, font) in candidates {
                let s = h * scale
                // Cut line exactly on the bottom edge; art starts ~0.12 h from the leading end.
                let frame = CGRect(x: h * 0.12 - s * artSideFraction, y: h - s * artCutFraction, width: s, height: s)
                let art = artBox(emblemFrame: frame, buttonHeight: h)
                if let box = label(font: font, from: art.maxX + gap) {
                    return ThemedTapButtonLayout(emblemFrame: frame, labelFrame: box, fontSize: font)
                }
            }
        }
        // No emblem (or it can't fit beside a readable label): centred label only.
        var font = preferred
        while font > minFontSize && labelWidth(font) > w - 2 * trailingInset { font -= 1 }
        let lw = labelWidth(font), lh = labelHeight(fontSize: font)
        return ThemedTapButtonLayout(emblemFrame: nil,
                                     labelFrame: CGRect(x: (w - lw) / 2, y: (h - lh) / 2, width: lw, height: lh),
                                     fontSize: font)
    }

    private static let widthCache = NSCache<NSString, NSNumber>()

    /// Typographic width of the label as drawn (SF Rounded black + tracking), cached.
    static func labelWidth(_ text: String, fontSize: CGFloat) -> CGFloat {
        let key = "\(text)|\(fontSize)" as NSString
        if let hit = widthCache.object(forKey: key) { return CGFloat(hit.doubleValue) }
        var font = UIFont.systemFont(ofSize: fontSize, weight: .black)
        if let rounded = font.fontDescriptor.withDesign(.rounded) { font = UIFont(descriptor: rounded, size: fontSize) }
        let width = ceil((text as NSString).size(withAttributes: [.font: font, .kern: tracking(fontSize: fontSize)]).width)
        widthCache.setObject(NSNumber(value: Double(width)), forKey: key)
        return width
    }
}

// MARK: - Lives

/// Lives indicator for the HUD (upper right).
struct CosmeticLivesView: View {
    let item: CosmeticItem
    let maxLives: Int
    let lives: Int
    /// Preferred themed icon size; shrinks so the row never exceeds `maxTotalWidth`.
    var iconSize: CGFloat = 22
    /// Cap for themed icons so 5 lives (Rush) never push the score.
    var maxTotalWidth: CGFloat = 100

    private var clampedLives: Int { min(max(lives, 0), maxLives) }

    var body: some View {
        content
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Lives")
            .accessibilityValue("\(clampedLives) of \(maxLives) lives")
    }

    @ViewBuilder private var content: some View {
        if !item.isDefault, item.slot == .lifeIcon,
           let active = CosmeticImageCache.shared.image(named: item.assets.imageName) {
            themed(active: active, lost: CosmeticImageCache.shared.image(named: item.assets.secondaryImageName))
        } else {
            // Pre-Studio dots, unchanged.
            HStack(spacing: 4) {
                ForEach(0..<maxLives, id: \.self) { i in
                    Circle()
                        .frame(width: 10, height: 10)
                        .foregroundColor(i < lives ? Color(red: 0.92, green: 0.27, blue: 0.27) : Color.white.opacity(0.15))
                }
            }
        }
    }

    private func themed(active: UIImage, lost: UIImage?) -> some View {
        let spacing: CGFloat = maxLives >= 5 ? 2 : 4
        let count = CGFloat(max(maxLives, 1))
        let size = min(iconSize, (maxTotalWidth - spacing * (count - 1)) / count)
        return HStack(spacing: spacing) {
            ForEach(0..<maxLives, id: \.self) { i in
                Group {
                    if i < lives {
                        Image(uiImage: active).resizable().scaledToFit()
                    } else if let lost {
                        Image(uiImage: lost).resizable().scaledToFit()
                    } else {
                        // No depleted art: the active icon, desaturated and faded.
                        Image(uiImage: active).resizable().scaledToFit()
                            .grayscale(1)
                            .opacity(0.45)
                    }
                }
                .frame(width: size, height: size)
            }
        }
    }
}

// MARK: - Image lookup cache

/// Memoises `UIImage(named:)` results, including misses, so view bodies that
/// re-render every tap (HUD, button) never hit the asset catalog again.
/// `preload(_:)` runs at round bootstrap, so the first tap does no lookups.
final class CosmeticImageCache {
    static let shared = CosmeticImageCache()

    private let lock = NSLock()
    private var images: [String: UIImage] = [:]
    private var misses: Set<String> = []

    func image(named name: String?) -> UIImage? {
        guard let name, !name.isEmpty else { return nil }
        lock.lock()
        if let hit = images[name] { lock.unlock(); return hit }
        if misses.contains(name) { lock.unlock(); return nil }
        lock.unlock()
        let loaded = UIImage(named: name)
        lock.lock()
        if let loaded { images[name] = loaded } else { misses.insert(name) }
        lock.unlock()
        return loaded
    }

    /// Looks up every image the resolved cosmetics reference (synchronous; a
    /// memory hit for each once `warm` has run).
    func preload(_ resolved: ResolvedCosmetics) {
        for name in Self.imageNames(resolved) { _ = image(named: name) }
    }

    /// Looks up *and decodes* every referenced image. Call off the main thread
    /// (CosmeticEffectAssets.warm at Home appear / round bootstrap): the first
    /// frame that shows the button or lives then has nothing to decode (QA-16).
    func warm(_ resolved: ResolvedCosmetics) {
        for name in Self.imageNames(resolved) {
            lock.lock()
            let known = images[name] != nil || misses.contains(name)
            lock.unlock()
            if known { continue }
            let decoded = UIImage(named: name).map { $0.preparingForDisplay() ?? $0 }
            lock.lock()
            if images[name] == nil && !misses.contains(name) {
                if let decoded { images[name] = decoded } else { misses.insert(name) }
            }
            lock.unlock()
        }
    }

    static func imageNames(_ resolved: ResolvedCosmetics) -> [String] {
        // Button and lives art; effect sprites live in CosmeticSpriteCache.
        CosmeticSlot.allCases.filter { !CosmeticSlot.effectSlots.contains($0) }.flatMap { slot -> [String] in
            let assets = resolved.item(for: slot).assets
            return [assets.imageName, assets.secondaryImageName, assets.emblemImageName].compactMap { $0 }.filter { !$0.isEmpty }
        }
    }
}

// MARK: - Colour helpers

extension CosmeticRGBA {
    func lightened(_ amount: Double) -> CosmeticRGBA {
        CosmeticRGBA(r: r + (1 - r) * amount, g: g + (1 - g) * amount, b: b + (1 - b) * amount, a: a)
    }

    func darkened(_ amount: Double) -> CosmeticRGBA {
        CosmeticRGBA(r: r * (1 - amount), g: g * (1 - amount), b: b * (1 - amount), a: a)
    }

    func mixed(with other: CosmeticRGBA, _ t: Double) -> CosmeticRGBA {
        CosmeticRGBA(r: r + (other.r - r) * t, g: g + (other.g - g) * t, b: b + (other.b - b) * t, a: a + (other.a - a) * t)
    }
}
