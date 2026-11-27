// Cosmetic asset pipeline — extracts provisional sprites from the owner-supplied
// concept sheet into Assets.xcassets/Cosmetics, and writes the asset manifest
// (JSON + Markdown) and a QA contact sheet.
//
// Usage (from the repository root):
//   swift scripts/cosmetics/extract_assets.swift
//
// Deterministic: same sheet in, byte-identical PNGs out. No third-party deps
// (CoreGraphics / ImageIO / CoreText only).
//
// Per asset:
//   1. crop an explicit, documented rectangle of the sheet (sheet pixel coords,
//      origin top-left);
//   2. segment the background by region-growing from the crop border: a pixel
//      joins the background when it differs from its already-background
//      neighbour by < `stepTol` (follows smooth panel gradients and glow ramps)
//      and from the crop's border median by < `maxDist`;
//      `erase` rectangles are forced to background (neighbouring elements);
//   3. keep the largest foreground component plus components whose area is
//      ≥ `keepMinFrac` × largest (drops sparkles, text, neighbour fragments);
//   4. matte the 1-px boundary band: alpha = projection of the pixel on the
//      local fg/bg colour line, colour de-contaminated from the panel colour;
//   5. trim, fit proportionally into a square canvas (`fill` of the edge),
//      export @2x/@3x PNG + imageset Contents.json.

import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import CoreText

// MARK: - Configuration

struct IRect: Codable { let x: Int, y: Int, w: Int, h: Int }

struct AssetSpec {
    let name: String
    let collection: String      // catalog collection id
    let folder: String          // xcassets sub-folder
    let slot: String            // catalog slot
    let field: String           // which CosmeticAssetRefs field references it
    let role: String
    let sourceDescription: String
    let rect: IRect
    let canvasPt: Int
    var fill: Double = 0.92
    var stepTol: Double = 12
    var maxDist: Double = 60
    var keepMinFrac: Double = 1.0
    var erase: [IRect] = []
    /// Crop edges used as background seeds (an element cut by the tile edge must not seed).
    var seedBottom: Bool = true
    /// Rows of alpha ramp applied at the bottom of the trimmed content (element cut by the tile edge).
    var fadeBottom: Int = 0
    let replacementSpec: String
}

let sheetPath = "design/cosmetics/source/theme_event_sheet_v1.webp"
let assetRoot = "ios/PerfectTap/Assets.xcassets/Cosmetics"
let license = "Owner-supplied concept art (theme_event_sheet_v1). Ownership/licence to be confirmed by the owner before release."

let lifeSpec = "Transparent PNG master ≥ 256×256 px (or PDF vector), single icon centred with ≤ 6% margin, no baked panel/shadow; active + lost pair drawn on the same silhouette."
let emblemSpec = "Transparent PNG master ≥ 512×512 px (or PDF vector), character only (no text, no button body), consistent light direction with life icons."
let spriteSpec = "Transparent PNG master ≥ 512×512 px, single element, no background panel, glow optional (renderer adds its own)."

let specs: [AssetSpec] = [
    // Life icons — bottom strip "LIFE ICONS (ACTIVE / LOST)"
    AssetSpec(name: "cos_quack_life", collection: "quack_attack", folder: "QuackAttack", slot: "lifeIcon", field: "imageName",
              role: "life icon (active)", sourceDescription: "bottom strip, Quack life icon (active)",
              rect: IRect(x: 474, y: 870, w: 78, h: 78), canvasPt: 24, fill: 0.96, stepTol: 10, maxDist: 42, replacementSpec: lifeSpec),
    AssetSpec(name: "cos_quack_life_lost", collection: "quack_attack", folder: "QuackAttack", slot: "lifeIcon", field: "secondaryImageName",
              role: "life icon (lost)", sourceDescription: "bottom strip, Quack life icon (lost)",
              rect: IRect(x: 550, y: 870, w: 74, h: 78), canvasPt: 24, fill: 0.96, stepTol: 10, maxDist: 42, replacementSpec: lifeSpec),
    AssetSpec(name: "cos_paw_life", collection: "purrfect_tap", folder: "PurrfectTap", slot: "lifeIcon", field: "imageName",
              role: "life icon (active)", sourceDescription: "bottom strip, Purrfect life icon (active)",
              rect: IRect(x: 869, y: 866, w: 74, h: 74), canvasPt: 24, fill: 0.96, stepTol: 10, maxDist: 42, replacementSpec: lifeSpec),
    AssetSpec(name: "cos_paw_life_lost", collection: "purrfect_tap", folder: "PurrfectTap", slot: "lifeIcon", field: "secondaryImageName",
              role: "life icon (lost)", sourceDescription: "bottom strip, Purrfect life icon (lost)",
              rect: IRect(x: 942, y: 866, w: 74, h: 74), canvasPt: 24, fill: 0.96, stepTol: 10, maxDist: 42, replacementSpec: lifeSpec),
    AssetSpec(name: "cos_boom_life", collection: "boom_mode", folder: "BoomMode", slot: "lifeIcon", field: "imageName",
              role: "life icon (active)", sourceDescription: "bottom strip, Boom life icon (active)",
              rect: IRect(x: 1326, y: 862, w: 74, h: 86), canvasPt: 24, fill: 0.96, stepTol: 10, maxDist: 42, replacementSpec: lifeSpec),
    AssetSpec(name: "cos_boom_life_lost", collection: "boom_mode", folder: "BoomMode", slot: "lifeIcon", field: "secondaryImageName",
              role: "life icon (lost)", sourceDescription: "bottom strip, Boom life icon (lost)",
              rect: IRect(x: 1402, y: 860, w: 78, h: 88), canvasPt: 24, fill: 0.96, stepTol: 10, maxDist: 42, replacementSpec: lifeSpec),

    // Tap-button emblems — theme hero art column
    AssetSpec(name: "cos_quack_emblem", collection: "quack_attack", folder: "QuackAttack", slot: "tapButton", field: "emblemImageName",
              role: "tap-button emblem", sourceDescription: "row Quack Attack, column THEME (hero duck, text excluded)",
              rect: IRect(x: 8, y: 259, w: 216, h: 130), canvasPt: 72, fill: 0.96, stepTol: 24, maxDist: 150, keepMinFrac: 0.02, replacementSpec: emblemSpec),
    AssetSpec(name: "cos_paw_emblem", collection: "purrfect_tap", folder: "PurrfectTap", slot: "tapButton", field: "emblemImageName",
              role: "tap-button emblem", sourceDescription: "row Purrfect Tap, column THEME (hero paw, text excluded)",
              rect: IRect(x: 28, y: 486, w: 190, h: 124), canvasPt: 72, fill: 0.96, stepTol: 11, maxDist: 110, seedBottom: false, fadeBottom: 8, replacementSpec: emblemSpec),
    AssetSpec(name: "cos_boom_emblem", collection: "boom_mode", folder: "BoomMode", slot: "tapButton", field: "emblemImageName",
              role: "tap-button emblem", sourceDescription: "row Boom Mode, column THEME (hero bomb, text excluded)",
              rect: IRect(x: 18, y: 712, w: 204, h: 120), canvasPt: 72, fill: 0.96, stepTol: 11, maxDist: 110, seedBottom: false, fadeBottom: 6, replacementSpec: emblemSpec),

    // Effect sprites
    AssetSpec(name: "cos_quack_feather", collection: "quack_attack", folder: "QuackAttack", slot: "lifeLostEffect", field: "imageName",
              role: "effect sprite (feather)", sourceDescription: "row Quack Attack, column LIFE LOST (main feather)",
              rect: IRect(x: 1140, y: 215, w: 150, h: 112), canvasPt: 36, fill: 0.94, stepTol: 10, maxDist: 70, replacementSpec: spriteSpec),
    AssetSpec(name: "cos_quack_gameover", collection: "quack_attack", folder: "QuackAttack", slot: "gameOverEffect", field: "imageName",
              role: "effect sprite (sad duck)", sourceDescription: "row Quack Attack, column GAME OVER (sad duck in puddle; rain + feathers excluded)",
              rect: IRect(x: 1305, y: 245, w: 220, h: 135), canvasPt: 96, fill: 0.96, stepTol: 18, maxDist: 250, keepMinFrac: 0.03,
              erase: [IRect(x: 1455, y: 240, w: 55, h: 34), IRect(x: 1305, y: 245, w: 40, h: 28)], replacementSpec: spriteSpec),
    AssetSpec(name: "cos_paw_gameover", collection: "purrfect_tap", folder: "PurrfectTap", slot: "gameOverEffect", field: "imageName",
              role: "effect sprite (dizzy cat)", sourceDescription: "row Purrfect Tap, column GAME OVER (dizzy cat + spiral; dizzy dashes excluded)",
              rect: IRect(x: 1305, y: 416, w: 220, h: 192), canvasPt: 96, fill: 0.96, stepTol: 16, maxDist: 200, keepMinFrac: 0.015,
              erase: [IRect(x: 1486, y: 455, w: 39, h: 58), IRect(x: 1305, y: 465, w: 40, h: 42)], replacementSpec: spriteSpec),
    AssetSpec(name: "cos_boom_gameover", collection: "boom_mode", folder: "BoomMode", slot: "gameOverEffect", field: "imageName",
              role: "effect sprite (mushroom boom)", sourceDescription: "row Boom Mode, column GAME OVER (mushroom boom)",
              rect: IRect(x: 1304, y: 626, w: 222, h: 202), canvasPt: 96, fill: 0.96, stepTol: 10, maxDist: 80, keepMinFrac: 0.01, replacementSpec: spriteSpec),
]

struct NotProduced { let name: String; let collection: String; let slot: String; let field: String; let reason: String; let spec: String }
let buttonReason = "Not produced — native rendering (CosmeticTapButtonSkin draws the button body from the palette). The sheet's buttons have baked \"TAP!\" text and are ~200×60 px."
let buttonSpec = "Production art optional: text-free PNG ≥ 1080×240 px (9-slice safe 40 px caps), normal + pressed."
let notProduced: [NotProduced] = [
    NotProduced(name: "cos_quack_button", collection: "quack_attack", slot: "tapButton", field: "imageName", reason: buttonReason, spec: buttonSpec),
    NotProduced(name: "cos_quack_button_pressed", collection: "quack_attack", slot: "tapButton", field: "secondaryImageName", reason: buttonReason, spec: buttonSpec),
    NotProduced(name: "cos_paw_button", collection: "purrfect_tap", slot: "tapButton", field: "imageName", reason: buttonReason, spec: buttonSpec),
    NotProduced(name: "cos_paw_button_pressed", collection: "purrfect_tap", slot: "tapButton", field: "secondaryImageName", reason: buttonReason, spec: buttonSpec),
    NotProduced(name: "cos_boom_button", collection: "boom_mode", slot: "tapButton", field: "imageName", reason: buttonReason, spec: buttonSpec),
    NotProduced(name: "cos_boom_button_pressed", collection: "boom_mode", slot: "tapButton", field: "secondaryImageName", reason: buttonReason, spec: buttonSpec),
]

// MARK: - Image buffer (straight RGBA, Double for processing)

struct Img {
    let w: Int, h: Int
    var px: [Double]   // r,g,b,a 0…255 straight
    init(w: Int, h: Int) { self.w = w; self.h = h; px = [Double](repeating: 0, count: w * h * 4) }
    @inline(__always) func rgb(_ x: Int, _ y: Int) -> (Double, Double, Double) {
        let i = (y * w + x) * 4; return (px[i], px[i + 1], px[i + 2])
    }
}

func dist(_ a: (Double, Double, Double), _ b: (Double, Double, Double)) -> Double {
    let dr = a.0 - b.0, dg = a.1 - b.1, db = a.2 - b.2
    return (dr * dr + dg * dg + db * db).squareRoot()
}

func loadSheet(_ path: String) -> Img {
    guard let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
          let cg = CGImageSourceCreateImageAtIndex(src, 0, nil) else { fatalError("cannot read \(path)") }
    let w = cg.width, h = cg.height
    var raw = [UInt8](repeating: 0, count: w * h * 4)
    let cs = CGColorSpace(name: CGColorSpace.sRGB)!
    raw.withUnsafeMutableBytes { buf in
        let ctx = CGContext(data: buf.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                            space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
    }
    var img = Img(w: w, h: h)
    for i in 0..<(w * h) {
        let a = Double(raw[i * 4 + 3])
        let k = a > 0 ? 255.0 / a : 0
        img.px[i * 4] = min(255, Double(raw[i * 4]) * k)
        img.px[i * 4 + 1] = min(255, Double(raw[i * 4 + 1]) * k)
        img.px[i * 4 + 2] = min(255, Double(raw[i * 4 + 2]) * k)
        img.px[i * 4 + 3] = a
    }
    return img
}

func crop(_ s: Img, _ r: IRect) -> Img {
    var o = Img(w: r.w, h: r.h)
    for y in 0..<r.h { for x in 0..<r.w {
        let si = ((y + r.y) * s.w + (x + r.x)) * 4, di = (y * r.w + x) * 4
        for c in 0..<4 { o.px[di + c] = s.px[si + c] }
    } }
    return o
}

// MARK: - Segmentation + matting

struct Extraction { var img: Img; let bgRef: (Double, Double, Double); let keptComponents: Int }

func extract(_ c: Img, spec: AssetSpec) -> Extraction {
    let w = c.w, h = c.h, n = w * h
    // Background reference = per-channel median of the crop border.
    var border: [(Double, Double, Double)] = []
    for x in 0..<w { border.append(c.rgb(x, 0)); border.append(c.rgb(x, h - 1)) }
    for y in 0..<h { border.append(c.rgb(0, y)); border.append(c.rgb(w - 1, y)) }
    func med(_ v: [Double]) -> Double { let s = v.sorted(); return s[s.count / 2] }
    let bgRef = (med(border.map { $0.0 }), med(border.map { $0.1 }), med(border.map { $0.2 }))

    var bg = [Bool](repeating: false, count: n)
    var queue: [Int] = []
    func seed(_ x: Int, _ y: Int) {
        let i = y * w + x
        if !bg[i] && dist(c.rgb(x, y), bgRef) < spec.maxDist { bg[i] = true; queue.append(i) }
    }
    for x in 0..<w { seed(x, 0); if spec.seedBottom { seed(x, h - 1) } }
    for y in 0..<h { seed(0, y); seed(w - 1, y) }
    for e in spec.erase {
        for y in max(0, e.y - spec.rect.y)..<min(h, e.y - spec.rect.y + e.h) {
            for x in max(0, e.x - spec.rect.x)..<min(w, e.x - spec.rect.x + e.w) {
                let i = y * w + x; if !bg[i] { bg[i] = true; queue.append(i) }
            }
        }
    }
    var head = 0
    while head < queue.count {
        let i = queue[head]; head += 1
        let x = i % w, y = i / w, p = c.rgb(x, y)
        for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
            let nx = x + dx, ny = y + dy
            guard nx >= 0, ny >= 0, nx < w, ny < h else { continue }
            let j = ny * w + nx
            if bg[j] { continue }
            let q = c.rgb(nx, ny)
            if dist(q, p) < spec.stepTol && dist(q, bgRef) < spec.maxDist { bg[j] = true; queue.append(j) }
        }
    }

    // Connected foreground components (8-connected).
    var label = [Int](repeating: -1, count: n)
    var areas: [Int] = []
    for s in 0..<n where !bg[s] && label[s] < 0 {
        let id = areas.count; var stack = [s]; label[s] = id; var area = 0
        while let i = stack.popLast() {
            area += 1
            let x = i % w, y = i / w
            for dy in -1...1 { for dx in -1...1 {
                let nx = x + dx, ny = y + dy
                guard nx >= 0, ny >= 0, nx < w, ny < h else { continue }
                let j = ny * w + nx
                if !bg[j] && label[j] < 0 { label[j] = id; stack.append(j) }
            } }
        }
        areas.append(area)
    }
    let largest = areas.max() ?? 0
    let keep = Set(areas.indices.filter { Double(areas[$0]) >= Double(largest) * spec.keepMinFrac && areas[$0] >= 6 })
    var fg = [Bool](repeating: false, count: n)
    for i in 0..<n where label[i] >= 0 && keep.contains(label[i]) { fg[i] = true }

    // Boundary band (pixels with a 4-neighbour of the other class).
    func isBand(_ i: Int) -> Bool {
        let x = i % w, y = i / w
        for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
            let nx = x + dx, ny = y + dy
            guard nx >= 0, ny >= 0, nx < w, ny < h else { continue }
            if fg[ny * w + nx] != fg[i] { return true }
        }
        return false
    }
    var band = [Bool](repeating: false, count: n)
    for i in 0..<n where isBand(i) { band[i] = true }

    var out = Img(w: w, h: h)
    for i in 0..<n {
        let x = i % w, y = i / w
        let P = c.rgb(x, y)
        if !band[i] {
            if fg[i] { out.px[i * 4] = P.0; out.px[i * 4 + 1] = P.1; out.px[i * 4 + 2] = P.2; out.px[i * 4 + 3] = 255 }
            continue
        }
        // Local fg / bg means (radius 3, excluding the band).
        var F = (0.0, 0.0, 0.0), B = (0.0, 0.0, 0.0), nf = 0.0, nb = 0.0
        for dy in -3...3 { for dx in -3...3 {
            let nx = x + dx, ny = y + dy
            guard nx >= 0, ny >= 0, nx < w, ny < h else { continue }
            let j = ny * w + nx
            if band[j] { continue }
            let q = c.rgb(nx, ny)
            if fg[j] { F.0 += q.0; F.1 += q.1; F.2 += q.2; nf += 1 }
            else { B.0 += q.0; B.1 += q.1; B.2 += q.2; nb += 1 }
        } }
        B = nb > 0 ? (B.0 / nb, B.1 / nb, B.2 / nb) : bgRef
        F = nf > 0 ? (F.0 / nf, F.1 / nf, F.2 / nf) : P
        let fb = (F.0 - B.0, F.1 - B.1, F.2 - B.2)
        let len2 = fb.0 * fb.0 + fb.1 * fb.1 + fb.2 * fb.2
        var a: Double
        if len2 < 1 { a = fg[i] ? 1 : 0 }
        else { a = ((P.0 - B.0) * fb.0 + (P.1 - B.1) * fb.1 + (P.2 - B.2) * fb.2) / len2 }
        a = min(1, max(0, a))
        if !fg[i] { a = min(a, 0.6) }   // outside pixels only contribute anti-aliasing
        if a <= 0.02 { continue }
        let dc = (min(255, max(0, B.0 + (P.0 - B.0) / a)), min(255, max(0, B.1 + (P.1 - B.1) / a)), min(255, max(0, B.2 + (P.2 - B.2) / a)))
        let t = max(0, min(1, (a - 0.3) / 0.5)); let s = t * t * (3 - 2 * t)
        out.px[i * 4] = F.0 * (1 - s) + dc.0 * s
        out.px[i * 4 + 1] = F.1 * (1 - s) + dc.1 * s
        out.px[i * 4 + 2] = F.2 * (1 - s) + dc.2 * s
        out.px[i * 4 + 3] = a * 255
    }
    return Extraction(img: out, bgRef: bgRef, keptComponents: keep.count)
}

func trim(_ img: Img) -> (Img, IRect) {
    var minX = img.w, minY = img.h, maxX = -1, maxY = -1
    for y in 0..<img.h { for x in 0..<img.w where img.px[(y * img.w + x) * 4 + 3] > 8 {
        minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
    } }
    precondition(maxX >= 0, "empty extraction")
    let r = IRect(x: minX, y: minY, w: maxX - minX + 1, h: maxY - minY + 1)
    return (crop(img, r), r)
}

// MARK: - CoreGraphics I/O

let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

func cgImage(_ img: Img) -> CGImage {
    var bytes = [UInt8](repeating: 0, count: img.w * img.h * 4)
    for i in 0..<(img.w * img.h * 4) { bytes[i] = UInt8(max(0, min(255, img.px[i].rounded()))) }
    let provider = CGDataProvider(data: Data(bytes) as CFData)!
    return CGImage(width: img.w, height: img.h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: img.w * 4,
                   space: sRGB, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
                   provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)!
}

func makeContext(_ w: Int, _ h: Int) -> CGContext {
    CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: sRGB,
              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
}

/// Fits `content` proportionally (never stretched) into a square canvas.
func render(_ content: CGImage, canvas: Int, fill: Double) -> (CGImage, Double) {
    let ctx = makeContext(canvas, canvas)
    ctx.interpolationQuality = .high
    let box = Double(canvas) * fill
    let scale = min(box / Double(content.width), box / Double(content.height))
    let dw = Double(content.width) * scale, dh = Double(content.height) * scale
    ctx.draw(content, in: CGRect(x: (Double(canvas) - dw) / 2, y: (Double(canvas) - dh) / 2, width: dw, height: dh))
    return (ctx.makeImage()!, scale)
}

func writePNG(_ img: CGImage, to path: String) {
    let url = URL(fileURLWithPath: path)
    let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, img, nil)
    precondition(CGImageDestinationFinalize(dest), "cannot write \(path)")
}

func writeJSON(_ obj: Any, to path: String) {
    let data = try! JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys])
    try! (String(data: data, encoding: .utf8)! + "\n").write(toFile: path, atomically: true, encoding: .utf8)
}

func folderContents() -> [String: Any] { ["info": ["author": "xcode", "version": 1], "properties": ["provides-namespace": false]] }

func fileSize(_ path: String) -> Int { (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? Int) ?? 0 }

// MARK: - Run

let fm = FileManager.default
guard fm.fileExists(atPath: sheetPath) else { fatalError("run from the repository root (missing \(sheetPath))") }
let sheet = loadSheet(sheetPath)
print("sheet \(sheet.w)×\(sheet.h)")

try? fm.removeItem(atPath: assetRoot)
try! fm.createDirectory(atPath: assetRoot, withIntermediateDirectories: true)
writeJSON(folderContents(), to: "\(assetRoot)/Contents.json")

struct Produced { let spec: AssetSpec; let trimmed: IRect; let srcW: Int; let srcH: Int; let files: [(scale: Int, px: Int, path: String, bytes: Int)]; let upscale3x: Double; let preview: CGImage }
var produced: [Produced] = []

for spec in specs {
    let folder = "\(assetRoot)/\(spec.folder)"
    if !fm.fileExists(atPath: folder) {
        try! fm.createDirectory(atPath: folder, withIntermediateDirectories: true)
        writeJSON(folderContents(), to: "\(folder)/Contents.json")
    }
    let set = "\(folder)/\(spec.name).imageset"
    try! fm.createDirectory(atPath: set, withIntermediateDirectories: true)

    let ex = extract(crop(sheet, spec.rect), spec: spec)
    var (content, tr) = trim(ex.img)
    if spec.fadeBottom > 0 {
        for y in max(0, content.h - spec.fadeBottom)..<content.h {
            let t = Double(content.h - y) / Double(spec.fadeBottom + 1)
            let k = t * t * (3 - 2 * t)
            for x in 0..<content.w { content.px[(y * content.w + x) * 4 + 3] *= k }
        }
    }
    let cg = cgImage(content)
    var files: [(Int, Int, String, Int)] = []
    var up3 = 0.0
    var preview: CGImage? = nil
    for scale in [2, 3] {
        let px = spec.canvasPt * scale
        let (img, s) = render(cg, canvas: px, fill: spec.fill)
        let path = "\(set)/\(spec.name)@\(scale)x.png"
        writePNG(img, to: path)
        files.append((scale, px, path, fileSize(path)))
        if scale == 3 { up3 = s; preview = img }
    }
    writeJSON([
        "images": [
            ["idiom": "universal", "scale": "1x"],
            ["filename": "\(spec.name)@2x.png", "idiom": "universal", "scale": "2x"],
            ["filename": "\(spec.name)@3x.png", "idiom": "universal", "scale": "3x"],
        ],
        "info": ["author": "xcode", "version": 1],
        "properties": ["preserves-vector-representation": false],
    ], to: "\(set)/Contents.json")
    produced.append(Produced(spec: spec, trimmed: tr, srcW: content.w, srcH: content.h, files: files.map { (scale: $0.0, px: $0.1, path: $0.2, bytes: $0.3) }, upscale3x: up3, preview: preview!))
    print(String(format: "%-22@ src %3d×%-3d comps %d  @3x scale %.2f%@", spec.name as NSString, content.w, content.h, ex.keptComponents, up3, up3 > 1.0 ? " (UPSCALED)" as NSString : "" as NSString))
}

// MARK: - Manifest (JSON + Markdown)

let totalBytes = produced.reduce(0) { $0 + $1.files.reduce(0) { $0 + $1.bytes } }
var jsonAssets: [[String: Any]] = produced.map { p in
    let s = p.spec
    let up = (p.upscale3x * 100).rounded() / 100
    return [
        "id": s.name, "collection": s.collection, "slot": s.slot, "catalogField": s.field, "role": s.role,
        "source": ["sheet": sheetPath, "description": s.sourceDescription,
                   "cropRect": ["x": s.rect.x, "y": s.rect.y, "w": s.rect.w, "h": s.rect.h],
                   "contentRect": ["x": s.rect.x + p.trimmed.x, "y": s.rect.y + p.trimmed.y, "w": p.srcW, "h": p.srcH]],
        "canvasPt": s.canvasPt,
        "outputs": p.files.map { ["scale": "\($0.scale)x", "pixels": "\($0.px)x\($0.px)", "bytes": $0.bytes, "file": $0.path] },
        "totalBytes": p.files.reduce(0) { $0 + $1.bytes },
        "transparency": "RGBA PNG, panel background keyed to alpha (region grow + 1 px matte)",
        "scaleFrom3xSource": up, "upscaled": p.upscale3x > 1.0,
        "readiness": "provisional",
        "license": license,
        "replacementSpec": s.replacementSpec,
    ]
}
for m in notProduced {
    jsonAssets.append(["id": m.name, "collection": m.collection, "slot": m.slot, "catalogField": m.field,
                       "readiness": "not_produced", "reason": m.reason, "replacementSpec": m.spec, "totalBytes": 0])
}
writeJSON(["sheet": sheetPath, "generator": "scripts/cosmetics/extract_assets.swift", "license": license,
           "totalBytes": totalBytes, "assets": jsonAssets], to: "design/cosmetics/asset_manifest.json")

var md = """
# Cosmetic Asset Manifest

> Generated by `swift scripts/cosmetics/extract_assets.swift` — do not edit by hand.
> Machine-readable copy: `design/cosmetics/asset_manifest.json`.
> QA contact sheet: `design/cosmetics/previews/extracted_contact_sheet.png`.

**Source:** `\(sheetPath)` (1536×1024 concept sheet).
**Licence / ownership:** owner-supplied concept art; **ownership and licence are not yet confirmed — the owner must confirm before release.**
**Readiness:** every produced asset is **provisional**: it is cut from ~60–200 px concept tiles, so it is soft at @3x and must be
replaced by production masters (spec per row) before the collections ship as final.

## Produced assets

| Asset | Collection | Slot (field) | Source crop (x,y,w,h) → content px | Canvas | @2x / @3x px | Bytes (@2x+@3x) | @3x scale | Readiness |
|---|---|---|---|---|---|---|---|---|

"""
for p in produced {
    let s = p.spec
    let bytes = p.files.reduce(0) { $0 + $1.bytes }
    let flag = p.upscale3x > 1.0 ? String(format: "**%.2f× upscaled**", p.upscale3x) : String(format: "%.2f×", p.upscale3x)
    md += "| `\(s.name)` | \(s.collection) | \(s.slot) (`\(s.field)`) | \(s.sourceDescription): (\(s.rect.x),\(s.rect.y),\(s.rect.w),\(s.rect.h)) → \(p.srcW)×\(p.srcH) | \(s.canvasPt) pt | \(s.canvasPt * 2) / \(s.canvasPt * 3) | \(bytes) | \(flag) | provisional |\n"
}
md += """

Transparency: all produced PNGs are RGBA with the dark panel keyed to alpha; neighbouring elements, labels, rain/sparkle
fragments and most baked glow are removed. Upscaled (>1×) rows are softer than native and are the first to replace.

**Total footprint added to the app bundle (PNG sources, before asset-catalog compilation): \(totalBytes) bytes (\(String(format: "%.1f", Double(totalBytes) / 1024)) KiB).**

## Not produced (intentional)

| Asset | Collection | Field | Reason | Replacement spec |
|---|---|---|---|---|

"""
for m in notProduced { md += "| `\(m.name)` | \(m.collection) | `\(m.field)` | \(m.reason) | \(m.spec) |\n" }
md += """

## Replacement specs (production art)

| Asset | Required replacement |
|---|---|

"""
for p in produced { md += "| `\(p.spec.name)` | \(p.spec.replacementSpec) |\n" }
md += """

## Pipeline

1. Crop the documented rectangle (sheet pixels, origin top-left).
2. Region-grow the background from the crop border (step tolerance / max distance per asset, see the script).
3. Keep the largest component (+ components above a per-asset area fraction); erase rectangles drop neighbours.
4. 1 px matte on the boundary (fg/bg colour projection, colour de-contaminated from the panel).
5. Trim, fit proportionally into a square canvas, export @2x/@3x PNG and `Contents.json`
   (`universal`, `preserves-vector-representation: false`).

Effects themselves (splash, ripple, sparks, star burst, sparkle, shockwave, feathers, fluff, scratch, smoke puff,
explosion, rain droop) are drawn natively in `Views/Game/Cosmetics/Effects/` and need no bitmap assets beyond the sprites above.

"""
try! md.write(toFile: "docs/cosmetics/ASSET_MANIFEST.md", atomically: true, encoding: .utf8)

// MARK: - Contact sheet

func checker(_ ctx: CGContext, _ r: CGRect, _ a: CGColor, _ b: CGColor, cell: CGFloat = 12) {
    ctx.saveGState(); ctx.clip(to: r)
    var y = r.minY, row = 0
    while y < r.maxY {
        var x = r.minX, col = 0
        while x < r.maxX {
            ctx.setFillColor((row + col) % 2 == 0 ? a : b)
            ctx.fill(CGRect(x: x, y: y, width: cell, height: cell))
            x += cell; col += 1
        }
        y += cell; row += 1
    }
    ctx.restoreGState()
}

func drawText(_ ctx: CGContext, _ s: String, at p: CGPoint, size: CGFloat, color: CGColor) {
    let font = CTFontCreateWithName("Helvetica-Bold" as CFString, size, nil)
    let attr = NSAttributedString(string: s, attributes: [
        NSAttributedString.Key(kCTFontAttributeName as String): font,
        NSAttributedString.Key(kCTForegroundColorAttributeName as String): color,
    ])
    let line = CTLineCreateWithAttributedString(attr)
    ctx.textPosition = p
    CTLineDraw(line, ctx)
}

let cell = 240, labelH = 34, perRow = 3
let rows = (produced.count + perRow - 1) / perRow
let sheetW = perRow * cell * 2 + (perRow + 1) * 16
let sheetH = rows * (cell + labelH + 16) + 16
let cs = makeContext(sheetW, sheetH)
cs.setFillColor(CGColor(srgbRed: 0.1, green: 0.1, blue: 0.12, alpha: 1))
cs.fill(CGRect(x: 0, y: 0, width: sheetW, height: sheetH))
for (k, p) in produced.enumerated() {
    let col = k % perRow, row = k / perRow
    let x0 = CGFloat(16 + col * (cell * 2 + 16))
    let yTop = CGFloat(sheetH - 16 - row * (cell + labelH + 16))
    let dark = CGRect(x: x0, y: yTop - CGFloat(labelH + cell), width: CGFloat(cell), height: CGFloat(cell))
    let light = dark.offsetBy(dx: CGFloat(cell), dy: 0)
    checker(cs, dark, CGColor(srgbRed: 0.08, green: 0.08, blue: 0.10, alpha: 1), CGColor(srgbRed: 0.18, green: 0.18, blue: 0.22, alpha: 1))
    checker(cs, light, CGColor(srgbRed: 0.97, green: 0.97, blue: 0.97, alpha: 1), CGColor(srgbRed: 0.84, green: 0.84, blue: 0.86, alpha: 1))
    let img = p.preview
    // Small icons are magnified (nearest) so edge quality is visible.
    let mag = min(3.0, Double(cell - 16) / Double(img.width))
    let d = CGFloat(Double(img.width) * mag)
    cs.interpolationQuality = mag > 1 ? .none : .high
    for r in [dark, light] {
        cs.draw(img, in: CGRect(x: r.midX - d / 2, y: r.midY - d / 2, width: d, height: d))
    }
    drawText(cs, "\(p.spec.name)  @3x \(img.width)px  ×\(String(format: "%.1f", mag))", at: CGPoint(x: x0 + 4, y: yTop - 22), size: 15,
             color: CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
}
try? fm.createDirectory(atPath: "design/cosmetics/previews", withIntermediateDirectories: true)
writePNG(cs.makeImage()!, to: "design/cosmetics/previews/extracted_contact_sheet.png")
print("total bytes \(totalBytes)")
