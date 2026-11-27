#!/usr/bin/env python3
"""Summarise several perf-probe JSONs (scripts/perf-run.sh) per group as a Markdown table.

    python3 scripts/qa/perf-summary.py base=/tmp/p/base-run*.json integrated=/tmp/p/int-run*.json ...

Each argument is <group>=<glob>. Prints mean (min–max) per metric over the runs
of a group. Simulator numbers: relative main-thread cost only.
"""
import glob
import json
import statistics
import sys

METRICS = [
    ("frames (gameplay)", lambda d: d["gameplay"]["frames"]),
    ("p99 frame ms", lambda d: d["gameplay"]["p99Ms"]),
    ("worst frame ms", lambda d: d["gameplay"]["maxMs"]),
    ("frames >=25 ms", lambda d: d["gameplay"]["over25ms"]),
    ("frames >=100 ms", lambda d: d["gameplay"]["over100ms"]),
    ("hitch ratio %", lambda d: d["gameplay"]["hitchRatioPct"]),
    ("tap handler avg ms", lambda d: span_avg(d, "game.tap")),
    ("tap handler max ms", lambda d: d["spans"]["game.tap"]["maxMs"]),
    ("audio.tapOutcome.main avg ms", lambda d: span_avg(d, "audio.tapOutcome.main")),
    ("audio.tapOutcome.main max ms", lambda d: d["spans"]["audio.tapOutcome.main"]["maxMs"]),
    ("view bootstrap max ms", lambda d: d["spans"]["game.viewBootstrap"]["maxMs"]),
    ("round end -> Game Over avg ms", lambda d: span_avg(d, "nav.roundEndToGameOver")),
    ("round end -> Game Over max ms", lambda d: d["spans"]["nav.roundEndToGameOver"]["maxMs"]),
    ("taps measured", lambda d: d["spans"]["game.tap"]["count"]),
    ("resident memory MB", lambda d: d["residentMemoryMB"]),
    ("gameplay stalls >=250 ms", lambda d: sum(1 for s in d.get("stalls", []) if s.get("inGameplay") and s.get("ms", 0) >= 250)),
]


def span_avg(d, name):
    s = d["spans"][name]
    return s["totalMs"] / s["count"] if s["count"] else 0.0


def fmt(vals):
    if not vals:
        return "n/a"
    m = statistics.mean(vals)
    if len(vals) == 1:
        return f"{m:.2f}"
    return f"{m:.2f} ({min(vals):.2f}–{max(vals):.2f})"


def main(argv):
    groups = []
    for arg in argv[1:]:
        name, pattern = arg.split("=", 1)
        files = sorted(glob.glob(pattern))
        groups.append((name, [json.load(open(f)) for f in files]))
    print("| metric | " + " | ".join(f"{n} (n={len(r)})" for n, r in groups) + " |")
    print("|---|" + "---|" * len(groups))
    for label, get in METRICS:
        cells = []
        for _, runs in groups:
            vals = []
            for d in runs:
                try:
                    vals.append(float(get(d)))
                except (KeyError, TypeError, ZeroDivisionError):
                    pass
            cells.append(fmt(vals))
        print(f"| {label} | " + " | ".join(cells) + " |")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
