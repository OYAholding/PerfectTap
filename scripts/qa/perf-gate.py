#!/usr/bin/env python3
"""Freeze/stutter regression gate for a simulator perf-probe JSON.

    python3 scripts/qa/perf-gate.py docs/perf/<label>.json [--baseline docs/perf/after-1.2.0-default-run2.json]

Reads the JSON written by `scripts/perf-run.sh` (DEBUG frame probe, workload
GameplayPerformanceTests) and checks the absolute 1.1.1/1.2.0 acceptance limits
plus, optionally, a relative comparison with a baseline run on the SAME Mac and
SAME simulator model. Exit 0 = PASS, 1 = FAIL, 2 = bad input.

Simulator numbers show relative main-thread cost only; a PASS here does not
replace the physical-device protocol (docs/perf/DEVICE_PROFILING_PROTOCOL.he.md).
"""
import json
import sys

# Absolute limits (gameplay window only). Derived from docs/perf/RESULTS_1.1.1.he.md
# and the 1.2.0 runs: 1.1.1/1.2.0 measured 0 frames >=250 ms, worst 110-124 ms,
# p99 16.7 ms, round end -> Game Over avg 31-58 ms, tap handler avg ~0.1 ms.
LIMITS = [
    # (label, getter, max allowed)
    ("gameplay frames >=250 ms", lambda d: d["gameplay"]["over250ms"], 0),
    ("gameplay frames >=100 ms", lambda d: d["gameplay"]["over100ms"], 2),
    ("gameplay worst frame ms", lambda d: d["gameplay"]["maxMs"], 250.0),
    ("gameplay p99 frame ms", lambda d: d["gameplay"]["p99Ms"], 25.0),
    ("gameplay hitch ratio % (>=25 ms)", lambda d: d["gameplay"]["hitchRatioPct"], 0.6),
    ("round end -> Game Over avg ms", lambda d: span_avg(d, "nav.roundEndToGameOver"), 150.0),
    ("round end -> Game Over max ms", lambda d: d["spans"]["nav.roundEndToGameOver"]["maxMs"], 250.0),
    ("tap handler avg ms", lambda d: span_avg(d, "game.tap"), 1.0),
    ("tap handler max ms", lambda d: d["spans"]["game.tap"]["maxMs"], 4.0),
    ("game screen bootstrap max ms", lambda d: d["spans"]["game.viewBootstrap"]["maxMs"], 50.0),
    ("music start on main max ms", lambda d: d["spans"].get("audio.musicStart.main", {}).get("maxMs", 0.0), 5.0),
    ("resident memory MB", lambda d: d["residentMemoryMB"], 150.0),
]
MIN_SESSIONS = 5  # workload: Classic x3, Timed, Endless


def span_avg(d, name):
    s = d["spans"][name]
    return s["totalMs"] / s["count"] if s["count"] else 0.0


def main(argv):
    if len(argv) < 2:
        print(__doc__)
        return 2
    path = argv[1]
    baseline = None
    if "--baseline" in argv:
        baseline = json.load(open(argv[argv.index("--baseline") + 1]))
    d = json.load(open(path))
    print(f"perf gate: {path}  build={d.get('build')} device={d.get('device')} sessions={d.get('gameSessions')}")
    fails = 0
    if d.get("gameSessions", 0) < MIN_SESSIONS:
        print(f"  FAIL workload incomplete: {d.get('gameSessions')} sessions < {MIN_SESSIONS}")
        fails += 1
    # A gameplay stall (inGameplay=true) of >=250 ms is a freeze regardless of totals.
    for s in d.get("stalls", []):
        if s.get("inGameplay") and s.get("ms", 0) >= 250:
            print(f"  FAIL gameplay stall {s['ms']:.0f} ms at {s.get('atSec', 0):.1f}s ({s.get('context')})")
            fails += 1
    for label, get, limit in LIMITS:
        try:
            v = float(get(d))
        except (KeyError, TypeError, ZeroDivisionError):
            print(f"  FAIL {label}: missing in probe JSON")
            fails += 1
            continue
        line = f"{label}: {v:.2f} (limit {limit})"
        if baseline is not None:
            try:
                b = float(get(baseline))
                line += f"  baseline {b:.2f}"
                # Relative regression: >50% worse than baseline AND above a noise floor.
                if b > 0 and v > b * 1.5 and v - b > 10 and "memory" not in label and "%" not in label:
                    line += "  <-- >50% worse than baseline (investigate)"
            except (KeyError, TypeError, ZeroDivisionError):
                pass
        ok = v <= limit
        print(("  ok   " if ok else "  FAIL ") + line)
        fails += 0 if ok else 1
    print("PASS" if fails == 0 else f"FAIL ({fails})")
    return 0 if fails == 0 else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
