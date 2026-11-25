#!/usr/bin/env bash
# Prints the UDID of an available iPhone simulator on the CI runner, preferring the
# newest iOS runtime and a non-Pro/Max/Plus model (closest to the 16e QA device).
# Override with PT_SIM_UDID.
set -euo pipefail
if [[ -n "${PT_SIM_UDID:-}" ]]; then echo "$PT_SIM_UDID"; exit 0; fi
xcrun simctl list devices available -j | python3 -c '
import json, re, sys
devs = json.load(sys.stdin)["devices"]
def ver(rt):
    m = re.search(r"iOS-(\d+)-(\d+)", rt)
    return (int(m.group(1)), int(m.group(2))) if m else (0, 0)
cands = [(ver(rt), d) for rt, ds in devs.items() if "iOS" in rt for d in ds if d["name"].startswith("iPhone")]
if not cands:
    sys.exit("no available iPhone simulator")
plain = [c for c in cands if not re.search(r"Pro|Max|Plus", c[1]["name"])] or cands
best = max(plain, key=lambda c: c[0])
print(best[1]["udid"])
sys.stderr.write("picked %s iOS %d.%d\n" % (best[1]["name"], best[0][0], best[0][1]))
'
