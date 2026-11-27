#!/usr/bin/env bash
# Asserts the monetization / economy flags resolved in a BUILT PerfectTap.app.
#
#   scripts/qa/assert-built-flags.sh <path/to/PerfectTap.app>                # Release: every flag NO
#   scripts/qa/assert-built-flags.sh --release-iap <path/to/PerfectTap.app>  # Release-IAP
#
# Release (default): PT_MONETIZATION_PROFILE=Off and every flag NO.
# Release-IAP: PT_MONETIZATION_PROFILE=AppStoreIAP, the five PT_IAP_* ceilings
# YES (selling still needs the server gate), and PT_AUTHORITATIVE_ECONOMY_ENABLED
# NO (not activated in 1.2.0).
# A missing key always fails (a release artifact must state every flag).
set -euo pipefail
MODE="release"
if [[ "${1:-}" == "--release-iap" ]]; then MODE="release-iap"; shift; fi
APP="${1:?usage: assert-built-flags.sh [--release-iap] <PerfectTap.app>}"
PLIST="$APP/Info.plist"
[[ -f "$PLIST" ]] || { echo "FAIL: $PLIST not found"; exit 1; }
IAP_FLAGS=(PT_IAP_CATALOG_ENABLED PT_IAP_SERVER_VERIFICATION_ENABLED PT_IAP_COIN_PACKS_ENABLED
           PT_IAP_REMOVE_ADS_ENABLED PT_IAP_PREMIUM_SKINS_ENABLED)
read_key() { /usr/libexec/PlistBuddy -c "Print :$1" "$PLIST" 2>/dev/null; }
is_no()  { [[ "$1" == "NO" || "$1" == "false" ]]; }
is_yes() { [[ "$1" == "YES" || "$1" == "true" ]]; }
fail=0
expect() { # key, want (NO|YES|literal)
  local v; v="$(read_key "$1" || true)"
  case "$2" in
    NO)  is_no "$v"  && echo "  ok   $1 = $v" || { echo "  FAIL $1 = '${v:-<missing>}' (want NO)"; fail=1; } ;;
    YES) is_yes "$v" && echo "  ok   $1 = $v" || { echo "  FAIL $1 = '${v:-<missing>}' (want YES)"; fail=1; } ;;
    *)   [[ "$v" == "$2" ]] && echo "  ok   $1 = $v" || { echo "  FAIL $1 = '${v:-<missing>}' (want $2)"; fail=1; } ;;
  esac
}
if [[ "$MODE" == "release" ]]; then
  expect PT_MONETIZATION_PROFILE Off
  for f in "${IAP_FLAGS[@]}"; do expect "$f" NO; done
else
  expect PT_MONETIZATION_PROFILE AppStoreIAP
  for f in "${IAP_FLAGS[@]}"; do expect "$f" YES; done
fi
expect PT_AUTHORITATIVE_ECONOMY_ENABLED NO
echo "PT_BACKEND = $(read_key PT_BACKEND || echo '<missing>')"
if [[ $fail -ne 0 ]]; then echo "FAIL: built app flags do not match $MODE"; exit 1; fi
echo "PASS: built app flags match $MODE"
