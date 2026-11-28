#!/usr/bin/env python3
"""Builds the offline owner review page for the Cosmetic Studio art and audio.

    python3 scripts/cosmetics/build_review_page.py            # WAVs + index.html
    python3 scripts/cosmetics/build_review_page.py --no-wav   # index.html only
    python3 scripts/cosmetics/build_review_page.py --check    # validate only (no writes)

Output: design/cosmetics/review/index.html and design/cosmetics/review/audio/*.wav.

* Python stdlib only. Inputs: design/cosmetics/asset_manifest.json (art) and
  ios/PerfectTap/Resources/Sounds/audio_manifest.json (audio).
* Browsers cannot play CAF reliably, so every CAF is also converted to a
  browser-playable 16-bit PCM WAV with macOS `afconvert -f WAVE -d LEI16`
  (same samples, different container). The WAVs are committed (≈0.9 MB total)
  so the page works from a plain checkout; re-run this script after any sound
  changes.
* Every file the page references is checked to exist, and the HTML is parsed
  back with html.parser (balanced tags) — `--check` does only that.
"""

import html
import json
import os
import shutil
import struct
import subprocess
import sys
from html.parser import HTMLParser

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT_DIR = os.path.join(ROOT, "design", "cosmetics", "review")
WAV_DIR = os.path.join(OUT_DIR, "audio")
ART_MANIFEST = os.path.join(ROOT, "design", "cosmetics", "asset_manifest.json")
AUDIO_MANIFEST = os.path.join(ROOT, "ios", "PerfectTap", "Resources", "Sounds", "audio_manifest.json")
IOS_DIR = os.path.join(ROOT, "ios", "PerfectTap")

COLLECTION_NAMES = {"quack_attack": "Quack Attack", "purrfect_tap": "Purrfect Tap", "boom_mode": "Boom Mode"}
PACK_ORDER = ["quack_attack", "purrfect_tap", "boom_mode"]
EVENT_ORDER = ["good", "great", "perfect", "miss", "lifeLost", "gameOver", "tap"]

# Where each graphic shows up (docs/cosmetics/ART_REPLACEMENT_SPEC.md has the point sizes).
ART_USAGE = {
    ("lifeIcon", "imageName"):
        "Lives HUD (lives modes): one icon per remaining life, 22 pt (≤19 pt with 5 lives in Rush). "
        "Also Studio collection/item cards and Preview Studio.",
    ("lifeIcon", "secondaryImageName"):
        "Lives HUD: a lost life slot, shown right after a miss that costs a life.",
    ("tapButton", "emblemImageName"):
        "Tap button, every tap of every round: drawn left of the TAP! label at 1.05 × button height "
        "(84 pt on the 80 pt button), lifted 8 pt. Also Studio cards (56 pt button) and Preview Studio.",
    ("lifeLostEffect", "imageName"):
        "Life Lost effect: 4–6 feather sprites (≈40–50 pt) burst from the lives HUD on a miss that costs a life.",
    ("gameOverEffect", "imageName"):
        "Game Over effect: one sprite (≈1.5 × effect radius, up to ≈135–165 pt wide) on the Game Over "
        "screen once per round (not on quit, not with Visual Effects off).",
}

# Gameplay trigger per sound event (docs/cosmetics/AUDIO_POLICY.md §1).
AUDIO_TRIGGER = {
    "good": "GOOD tap (round-robin v1 → v2 → v3). Preview Studio: the tap button and “Good”.",
    "great": "GREAT tap, incl. a GREAT that reaches a combo milestone (round-robin v1 → v3). Preview: “Great”.",
    "perfect": "PERFECT tap, incl. a PERFECT that reaches a combo milestone. Preview: “Perfect”.",
    "miss": "MISS that does not cost a life, and a broken combo (incl. a Hardcore break on a GOOD). Preview: “Miss”.",
    "lifeLost": "MISS that costs a life (lives modes); replaces the miss sound. Preview: “Lose a life”.",
    "gameOver": "Round end, as the Game Over screen appears (the final tap's own sound is skipped). Preview: “Game Over”.",
    "tap": "UNUSED — gameplay never plays it and the Preview Studio no longer does either (QA-08). "
           "Candidate for removal, or for a future deliberate tap layer (owner decision).",
}

AUDIO_DESCRIPTION = {
    ("quack_attack", "tap"): "short quack",
    ("quack_attack", "good"): "soft quack, ±3 % pitch / formant per variant",
    ("quack_attack", "great"): "rising, playful quack",
    ("quack_attack", "perfect"): "double rising quack + sparkle pings",
    ("quack_attack", "miss"): "subdued low quack",
    ("quack_attack", "lifeLost"): "water splash",
    ("quack_attack", "gameOver"): "descending “wah-wah” quacks",
    ("purrfect_tap", "tap"): "soft boop",
    ("purrfect_tap", "good"): "soft pop, ±3 % per variant",
    ("purrfect_tap", "great"): "short purr",
    ("purrfect_tap", "perfect"): "chime + synthesized meow",
    ("purrfect_tap", "miss"): "short subdued meow",
    ("purrfect_tap", "lifeLost"): "soft puff",
    ("purrfect_tap", "gameOver"): "fading purr into a sad meow",
    ("boom_mode", "tap"): "mechanical click + short pop",
    ("boom_mode", "good"): "tick, ±3 % per variant",
    ("boom_mode", "great"): "spark crackle",
    ("boom_mode", "perfect"): "compact impact",
    ("boom_mode", "miss"): "fizzle",
    ("boom_mode", "lifeLost"): "cartoon explosion",
    ("boom_mode", "gameOver"): "final boom with rumble tail",
}

STATUS_LABEL = {
    "provisional-needs-sound-designer": "provisional · needs sound designer",
    "provisional-pending-owner-listen": "provisional · owner listen",
}


def rel(path):
    """Path relative to the page (design/cosmetics/review/)."""
    return os.path.relpath(path, OUT_DIR).replace(os.sep, "/")


def png_size(path):
    with open(path, "rb") as f:
        head = f.read(24)
    if head[:8] != b"\x89PNG\r\n\x1a\n":
        raise ValueError("not a PNG: %s" % path)
    return struct.unpack(">II", head[16:24])


def kb(n):
    return "%.1f KB" % (n / 1024.0)


def load():
    with open(ART_MANIFEST) as f:
        art = json.load(f)
    with open(AUDIO_MANIFEST) as f:
        audio = json.load(f)
    return art, audio


def caf_path(sound):
    return os.path.join(IOS_DIR, sound["file"])


def wav_path(sound):
    return os.path.join(WAV_DIR, sound["id"] + ".wav")


def convert_wavs(audio):
    if not shutil.which("afconvert"):
        sys.exit("afconvert not found (macOS only). Run with --no-wav to rebuild the HTML only.")
    os.makedirs(WAV_DIR, exist_ok=True)
    wanted = set()
    for s in audio["sounds"]:
        out = wav_path(s)
        wanted.add(os.path.basename(out))
        subprocess.run(["afconvert", "-f", "WAVE", "-d", "LEI16", caf_path(s), out], check=True)
    for name in os.listdir(WAV_DIR):   # drop WAVs of sounds that no longer exist
        if name.endswith(".wav") and name not in wanted:
            os.remove(os.path.join(WAV_DIR, name))


# ---------------------------------------------------------------- HTML

CSS = """
:root{--bg:#0d0d14;--panel:#171722;--line:#2a2a3a;--text:#ececf4;--muted:#9a9ab0;--gold:#f9bb42;--warn:#ff9f43;--ok:#38d17d}
*{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--text);font:15px/1.5 -apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif}
main{max-width:1200px;margin:0 auto;padding:24px 16px 64px}h1{font-size:26px;margin:0 0 4px}h2{margin:40px 0 8px;font-size:21px}
h3{margin:24px 0 8px;font-size:17px}p,li{color:var(--muted)}strong{color:var(--text)}code{font:13px ui-monospace,Menlo,monospace;color:var(--text)}
.banner{border:1px solid var(--warn);background:#2a1d0e;border-radius:12px;padding:12px 16px;margin:16px 0;color:#ffd9b0}
.grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(340px,1fr));gap:16px}
.card{background:var(--panel);border:1px solid var(--line);border-radius:14px;padding:14px}
.card h3{margin:0 0 6px;font-size:16px}.tiles{display:flex;gap:8px;flex-wrap:wrap;margin:8px 0}
.tile{border-radius:10px;padding:8px;display:flex;flex-direction:column;align-items:center;gap:4px;font-size:11px;color:var(--muted)}
.tile.dark{background:#0a0a0f;border:1px solid var(--line)}
.tile.light{background-color:#fff;background-image:linear-gradient(45deg,#ddd 25%,transparent 25%),linear-gradient(-45deg,#ddd 25%,transparent 25%),linear-gradient(45deg,transparent 75%,#ddd 75%),linear-gradient(-45deg,transparent 75%,#ddd 75%);background-size:16px 16px;background-position:0 0,0 8px,8px -8px,-8px 0;color:#444}
.tile img{image-rendering:auto;display:block}
dl{display:grid;grid-template-columns:max-content 1fr;gap:2px 10px;margin:6px 0 0;font-size:13px}dt{color:var(--muted)}dd{margin:0}
.pill{display:inline-block;border-radius:999px;padding:1px 8px;font-size:12px;font-weight:600;background:#3a2a10;color:var(--gold)}
.pill.unused{background:#3a1616;color:#ff8a8a}
table{width:100%;border-collapse:collapse;font-size:13px;margin:8px 0}th,td{border-bottom:1px solid var(--line);padding:8px 6px;text-align:left;vertical-align:top}
th{color:var(--muted);font-weight:600}td audio{width:220px;max-width:100%;height:32px}
.tablewrap{overflow-x:auto}.check{display:flex;gap:8px;align-items:flex-start;margin:4px 0;color:var(--muted)}
footer{margin-top:48px;color:var(--muted);font-size:12px}
"""


def art_card(asset):
    usage = ART_USAGE.get((asset["slot"], asset["catalogField"]), "")
    tiles = []
    for out in asset["outputs"]:
        path = os.path.join(ROOT, out["file"])
        w, h = png_size(path)
        scale = int(out["scale"].rstrip("x"))
        pt = w // scale
        src = html.escape(rel(path))
        for bg in ("dark", "light"):
            tiles.append(
                '<div class="tile %s"><img src="%s" width="%d" height="%d" alt="%s @%s on %s background">'
                '<span>@%s · %d×%d px · %d pt</span></div>'
                % (bg, src, pt, pt, html.escape(asset["id"]), out["scale"], bg, out["scale"], w, h, pt))
        # Actual pixels (1 image px = 1 CSS px) so the owner can judge softness.
        if scale == 3:
            tiles.append('<div class="tile dark"><img src="%s" width="%d" height="%d" alt="%s @3x actual pixels">'
                         '<span>@3x at 1 px = 1 px</span></div>' % (src, w, h, html.escape(asset["id"])))
    sizes = ", ".join("@%s %s px (%s)" % (o["scale"], o["pixels"], kb(o["bytes"])) for o in asset["outputs"])
    upscale = asset.get("scaleFrom3xSource", 1)
    return """
<div class="card" id="art-{id}">
  <h3><code>{id}</code> <span class="pill">provisional</span></h3>
  <div class="tiles">{tiles}</div>
  <dl>
    <dt>Collection</dt><dd>{collection}</dd>
    <dt>Slot · field</dt><dd><code>{slot}</code> · <code>{field}</code> ({role})</dd>
    <dt>Gameplay</dt><dd>{usage}</dd>
    <dt>Canvas</dt><dd>{canvas} pt square</dd>
    <dt>Files</dt><dd>{sizes} — total {total}</dd>
    <dt>Source</dt><dd>cut from the concept sheet; @3x is {upscale:.2f}× the source pixels{soft}</dd>
    <dt>Readiness</dt><dd>{readiness} — replace with production art (see ART_REPLACEMENT_SPEC.md)</dd>
  </dl>
</div>""".format(id=html.escape(asset["id"]), tiles="".join(tiles),
                 collection=html.escape(COLLECTION_NAMES.get(asset["collection"], asset["collection"])),
                 slot=asset["slot"], field=asset["catalogField"], role=html.escape(asset.get("role", "")),
                 usage=html.escape(usage), canvas=asset["canvasPt"], sizes=html.escape(sizes),
                 total=kb(asset["totalBytes"]), upscale=upscale,
                 soft=" (upscaled — soft)" if upscale > 1 else "", readiness=html.escape(asset["readiness"]))


def audio_rows(sounds):
    rows = []
    for s in sounds:
        caf = caf_path(s)
        wav = wav_path(s)
        unused = s["event"] == "tap"
        status = STATUS_LABEL.get(s["status"], s["status"])
        if unused:
            status = "unused · " + status
        rows.append("""
<tr id="snd-{id}">
  <td><code>{id}</code><br><span style="color:var(--muted)">{desc}</span></td>
  <td>{event}{variant}</td>
  <td>{trigger}</td>
  <td>{ms:.0f} ms</td>
  <td>{size}</td>
  <td><span class="pill{cls}">{status}</span></td>
  <td><audio controls preload="none" src="{wav}"></audio><br><a href="{caf}" style="color:var(--muted);font-size:12px">original .caf</a></td>
</tr>""".format(id=html.escape(s["id"]), desc=html.escape(AUDIO_DESCRIPTION.get((s["pack"], s["event"]), "")),
                event=html.escape(s["event"]),
                variant=" v%d" % s["variant"] if s["event"] in ("good", "great") else "",
                trigger=html.escape(AUDIO_TRIGGER[s["event"]]), ms=s["durationMs"], size=kb(s["bytes"]),
                cls=" unused" if unused else "", status=html.escape(status),
                wav=html.escape(rel(wav)), caf=html.escape(rel(caf))))
    return "".join(rows)


def build_html(art, audio):
    produced = [a for a in art["assets"] if a.get("outputs")]
    not_produced = [a for a in art["assets"] if not a.get("outputs")]
    sounds = audio["sounds"]
    by_pack = {p: sorted([s for s in sounds if s["pack"] == p],
                         key=lambda s: (EVENT_ORDER.index(s["event"]), s["variant"])) for p in PACK_ORDER}
    unused = [s for s in sounds if s["event"] == "tap"]

    parts = ["""<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Cosmetic Studio Review</title><style>%s</style></head><body><main>
<h1>Cosmetic Studio — art &amp; audio review</h1>
<p>PerfectTap Cosmetic Studio (Quack Attack, Purrfect Tap, Boom Mode). Generated by
<code>scripts/cosmetics/build_review_page.py</code> from <code>design/cosmetics/asset_manifest.json</code> and
<code>ios/PerfectTap/Resources/Sounds/audio_manifest.json</code>. Works offline: open this file in Safari or Chrome.</p>
<div class="banner"><strong>Everything on this page is provisional.</strong> The %d graphics were cut from the
owner-supplied concept sheet (<code>design/cosmetics/source/theme_event_sheet_v1.webp</code>; licence still to be confirmed)
and are soft at @3x. The %d sounds are <strong>original procedural synthesis</strong>
(<code>scripts/audio/generate_sound_packs.py</code>, seed %d) — the “duck” and “cat” voices are synthesized
approximations, <strong>not animal recordings</strong>. Prices are proposals too. Nothing here is approved.</div>
<h2 id="how">How to review / what to approve</h2>
<ol>
<li><strong>Art.</strong> For each graphic, check it on the dark tile (how the game shows it) and on the checkerboard
(stray halo, cut-off edges — e.g. QA-09: emblem bottoms are cut flat). Decide per asset: <em>approve as-is</em>,
<em>replace</em> (spec: <code>docs/cosmetics/ART_REPLACEMENT_SPEC.md</code>), or <em>drop</em>.</li>
<li><strong>Audio.</strong> Listen on an iPhone speaker <em>and</em> headphones if you can (a browser on a laptop is a
rough guide only). The “Gameplay trigger” column says exactly when each sound plays. Decide per sound:
<em>approve</em>, <em>needs sound designer</em>, or <em>drop</em>. Rows marked “needs sound designer” are the weakest.</li>
<li><strong>Unused <code>_tap</code> sounds.</strong> Decide: <em>remove</em> them, or keep them for a future deliberate
tap layer (gameplay change, separate decision).</li>
<li><strong>Rights.</strong> Confirm ownership/licence of the concept sheet. The sounds are original project work.</li>
</ol>
<p>The checkboxes below are a scratch pad only: they are not saved anywhere.</p>
""" % (CSS, len(produced), len(sounds), audio["masterSeed"])]

    parts.append('<h2 id="art">Graphics (%d produced)</h2>' % len(produced))
    for coll in PACK_ORDER:
        items = [a for a in produced if a["collection"] == coll]
        parts.append('<h3>%s</h3><div class="grid">%s</div>'
                     % (html.escape(COLLECTION_NAMES[coll]), "".join(art_card(a) for a in items)))
        parts.append('<label class="check"><input type="checkbox"> %s art reviewed</label>'
                     % html.escape(COLLECTION_NAMES[coll]))

    parts.append('<h3 id="not-produced">Optional button backgrounds (not produced — native rendering)</h3>'
                 '<div class="tablewrap"><table><tr><th>Asset id (reserved)</th><th>Collection</th><th>Field</th>'
                 '<th>Why not produced</th><th>If commissioned</th></tr>')
    for a in not_produced:
        parts.append('<tr><td><code>%s</code></td><td>%s</td><td><code>%s</code></td><td>%s</td><td>%s</td></tr>'
                     % (html.escape(a["id"]), html.escape(COLLECTION_NAMES[a["collection"]]), a["catalogField"],
                        html.escape(a["reason"]), html.escape(a["replacementSpec"])))
    parts.append("</table></div>")

    parts.append('<h2 id="audio">Sounds (%d files, %s)</h2>' % (len(sounds), kb(audio["totalBytes"])))
    parts.append("<p>Players are browser-playable WAV copies (<code>afconvert -f WAVE -d LEI16</code>, same samples) in "
                 "<code>design/cosmetics/review/audio/</code>; “original .caf” links to the file the app ships. "
                 "The Classic pack has no files (built-in tones, unchanged).</p>")
    head = ('<div class="tablewrap"><table><tr><th>Sound</th><th>Event</th><th>Gameplay trigger</th><th>Duration</th>'
            '<th>Size (CAF)</th><th>Status</th><th>Listen</th></tr>')
    for p in PACK_ORDER:
        total = sum(s["bytes"] for s in by_pack[p])
        parts.append('<h3>%s <span style="color:var(--muted);font-weight:400">(<code>%s</code>, %d files, %s)</span></h3>'
                     % (html.escape(COLLECTION_NAMES[p]), p, len(by_pack[p]), kb(total)))
        parts.append(head + audio_rows(by_pack[p]) + "</table></div>")
        parts.append('<label class="check"><input type="checkbox"> %s sounds reviewed (speaker)</label>'
                     '<label class="check"><input type="checkbox"> %s sounds reviewed (headphones)</label>'
                     % (html.escape(COLLECTION_NAMES[p]), html.escape(COLLECTION_NAMES[p])))

    parts.append('<h2 id="unused">Unused sounds (%d) — owner decision</h2>' % len(unused))
    parts.append("<p>Gameplay never plays the <code>tap</code> event (every scored tap has a grade), and since QA-08 "
                 "the Preview Studio tap button plays what a real GOOD tap plays. These files ship in the app but are "
                 "never heard: <strong>unused — candidate for removal or for a future deliberate tap layer (owner "
                 "decision)</strong>. Total %s.</p><ul>" % kb(sum(s["bytes"] for s in unused)))
    for s in unused:
        parts.append('<li><a href="#snd-%s"><code>%s</code></a> — %s</li>'
                     % (html.escape(s["id"]), html.escape(s["id"]), html.escape(AUDIO_DESCRIPTION[(s["pack"], "tap")])))
    parts.append("</ul>")

    parts.append("""<footer>Regenerate: <code>python3 scripts/cosmetics/build_review_page.py</code> (macOS, needs
<code>afconvert</code>) · validate only: <code>--check</code>. Audio reproducibility:
<code>python3 scripts/audio/generate_sound_packs.py --check</code>. Docs: <code>docs/cosmetics/ASSET_MANIFEST.md</code>,
<code>docs/cosmetics/AUDIO_MANIFEST.md</code>, <code>docs/cosmetics/AUDIO_POLICY.md</code>.</footer>
</main></body></html>
""")
    return "".join(parts)


# ---------------------------------------------------------------- validation

class RefCollector(HTMLParser):
    VOID = {"meta", "img", "br", "input", "link", "source", "hr"}

    def __init__(self):
        super().__init__()
        self.refs, self.stack, self.errors = [], [], []

    def handle_starttag(self, tag, attrs):
        for k, v in attrs:
            if k in ("src", "href") and v and not v.startswith("#"):
                self.refs.append(v)
        if tag not in self.VOID:
            self.stack.append(tag)

    def handle_endtag(self, tag):
        if tag in self.VOID:
            return
        if not self.stack or self.stack[-1] != tag:
            self.errors.append("unbalanced </%s> (open: %s)" % (tag, self.stack[-3:]))
        else:
            self.stack.pop()


def validate(page_path, audio, art):
    with open(page_path, encoding="utf-8") as f:
        text = f.read()
    p = RefCollector()
    p.feed(text)
    errors = list(p.errors)
    if p.stack:
        errors.append("unclosed tags: %s" % p.stack)
    missing = [r for r in p.refs if not os.path.isfile(os.path.normpath(os.path.join(OUT_DIR, r)))]
    errors += ["missing file: %s" % m for m in missing]
    wavs = [r for r in p.refs if r.endswith(".wav")]
    cafs = [r for r in p.refs if r.endswith(".caf")]
    pngs = set(r for r in p.refs if r.endswith(".png"))
    if len(wavs) != len(audio["sounds"]) or len(cafs) != len(audio["sounds"]):
        errors.append("expected %d wav + caf refs, got %d / %d" % (len(audio["sounds"]), len(wavs), len(cafs)))
    expected_png = sum(len(a.get("outputs", [])) for a in art["assets"])
    if len(pngs) != expected_png:
        errors.append("expected %d distinct PNGs, got %d" % (expected_png, len(pngs)))
    for r in wavs:   # WAV header sanity: RIFF/WAVE, PCM 16-bit mono 44.1 kHz
        with open(os.path.normpath(os.path.join(OUT_DIR, r)), "rb") as f:
            h = f.read(36)
        if h[:4] != b"RIFF" or h[8:12] != b"WAVE":
            errors.append("not a WAV: %s" % r)
        elif struct.unpack("<HHI", h[20:28]) != (1, 1, 44100) or struct.unpack("<H", h[34:36])[0] != 16:
            errors.append("unexpected WAV format: %s" % r)
    wav_bytes = sum(os.path.getsize(os.path.join(WAV_DIR, n)) for n in os.listdir(WAV_DIR)
                    if n.endswith(".wav")) if os.path.isdir(WAV_DIR) else 0
    return errors, {"refs": len(p.refs), "png": len(pngs), "wav": len(wavs), "caf": len(cafs), "wavBytes": wav_bytes}


def main():
    art, audio = load()
    page = os.path.join(OUT_DIR, "index.html")
    if "--check" not in sys.argv:
        os.makedirs(OUT_DIR, exist_ok=True)
        if "--no-wav" not in sys.argv:
            convert_wavs(audio)
        with open(page, "w", encoding="utf-8") as f:
            f.write(build_html(art, audio))
    errors, stats = validate(page, audio, art)
    print("review page: %s" % os.path.relpath(page, ROOT))
    print("references: %(refs)d (PNG %(png)d, WAV %(wav)d, CAF %(caf)d); WAV total %(wavBytes)d bytes" % stats)
    if errors:
        print("\n".join("ERROR: " + e for e in errors))
        sys.exit(1)
    print("OK: HTML balanced, every referenced file exists")


if __name__ == "__main__":
    main()
