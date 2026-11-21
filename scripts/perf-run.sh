#!/usr/bin/env bash
# Reproducible simulator perf run for PerfectTap.
#
#   scripts/perf-run.sh <label> [simulator name]
#
# Uninstalls the app (clean state), runs GameplayPerformanceTests with the
# DEBUG frame probe, then copies Documents/perf-probe.json to
# docs/perf/<label>.json. Uses the offline backend: nothing is written to the
# real Supabase project and no ads are loaded.
#
# Simulator numbers show relative main-thread cost on this Mac; they are not a
# substitute for an Instruments capture on a physical iPhone
# (docs/perf/DEVICE_PROFILING_PROTOCOL.he.md).
set -euo pipefail

LABEL="${1:?usage: perf-run.sh <label> [simulator]}"
SIM="${2:-iPhone 17}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
IOS="$ROOT/ios/PerfectTap"
OUT="$ROOT/docs/perf"
DD="${PT_DERIVED_DATA:-$ROOT/build/perf-dd}"
BUNDLE="com.perfecttap.app"
mkdir -p "$OUT"

# PT_SIM_UDID pins an exact simulator (recommended: same one for every run).
UDID="${PT_SIM_UDID:-$(xcrun simctl list devices available | grep -E "^\s+$SIM \(" | tail -1 | sed -E 's/.*\(([0-9A-F-]+)\).*/\1/')}"
[ -n "$UDID" ] || { echo "simulator '$SIM' not found"; exit 1; }
xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl bootstatus "$UDID" -b >/dev/null
xcrun simctl uninstall "$UDID" "$BUNDLE" 2>/dev/null || true

cd "$IOS"
xcodebuild test -project PerfectTap.xcodeproj -scheme PerfectTapUITests \
  -destination "id=$UDID" -derivedDataPath "$DD" \
  -only-testing:PerfectTapUITests/GameplayPerformanceTests/test_gameplay_workload \
  > "$OUT/$LABEL.xcodebuild.log" 2>&1 || { echo "test failed — see $OUT/$LABEL.xcodebuild.log"; tail -30 "$OUT/$LABEL.xcodebuild.log"; exit 1; }

CONTAINER=$(xcrun simctl get_app_container "$UDID" "$BUNDLE" data)
cp "$CONTAINER/Documents/perf-probe.json" "$OUT/$LABEL.json"
python3 -m json.tool "$OUT/$LABEL.json"
