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
        ZStack {
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
            // Inner highlight stroke + coloured rim.
            Capsule()
                .strokeBorder(Color.white.opacity(0.45), lineWidth: 1.5)
                .padding(3)
            Capsule()
                .strokeBorder(accent.color.opacity(0.9), lineWidth: 2.5)

            labelText
                // Keep the label clear of the emblem; still centred in the free space.
                .padding(.leading, emblemImage == nil ? 0 : height * 0.8)
        }
        .frame(height: height)
        // Overlays never affect layout: the emblem may poke above the top edge
        // without changing the 80 pt height.
        .overlay(alignment: .leading) {
            if let emblemImage {
                Image(uiImage: emblemImage)
                    .resizable()
                    .scaledToFit()
                    .frame(width: height * 1.05, height: height * 1.05)
                    .scaleEffect(isPressed ? 0.92 : 1)
                    .padding(.leading, 8)
                    .offset(y: -height * 0.1)
                    .allowsHitTesting(false)
            }
        }
        .overlay(alignment: .topLeading) { fuseGlow }
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

    private var labelText: some View {
        // White heavy text with a dark crisp drop + soft shadow: readable on
        // yellow, pink and steel bodies alike.
        Text(label)
            .font(.system(size: 26, weight: .black, design: .rounded))
            .tracking(4)
            .foregroundColor(.white)
            .shadow(color: body1.darkened(0.55).color.opacity(0.9), radius: 0, x: 0, y: 2)
            .shadow(color: .black.opacity(0.35), radius: 3, x: 0, y: 1)
    }

    /// Boom: a short warm glow at the fuse while the finger is down.
    @ViewBuilder private var fuseGlow: some View {
        if assets.pressStyle == .fuseGlow, isPressed, effects.showsGlow {
            Circle()
                .fill(RadialGradient(colors: [palette.last?.color ?? .yellow, accent.color.opacity(0.5), .clear],
                                     center: .center, startRadius: 0, endRadius: 18))
                .frame(width: 36, height: 36)
                .opacity(effects.glowStrength)
                .offset(x: height * 0.72, y: -height * 0.2)
                .allowsHitTesting(false)
                .transition(.opacity)
        }
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

    /// Looks up every image the resolved cosmetics reference.
    func preload(_ resolved: ResolvedCosmetics) {
        for slot in CosmeticSlot.allCases {
            let assets = resolved.item(for: slot).assets
            _ = image(named: assets.imageName)
            _ = image(named: assets.secondaryImageName)
            _ = image(named: assets.emblemImageName)
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
