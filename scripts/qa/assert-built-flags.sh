#!/usr/bin/env bash
# Asserts that a BUILT PerfectTap.app (any configuration) has every monetization /
# economy flag resolved to NO in its Info.plist. Use on Release / archive products:
#
#   scripts/qa/assert-built-flags.sh <path/to/PerfectTap.app>
#
# A missing key also fails (the app treats missing as off, but a release artifact
# should state NO explicitly so the guard can prove it).
set -euo pipefail
APP="${1:?usage: assert-built-flags.sh <PerfectTap.app>}"
PLIST="$APP/Info.plist"
[[ -f "$PLIST" ]] || { echo "FAIL: $PLIST not found"; exit 1; }
FLAGS=(PT_IAP_CATALOG_ENABLED PT_IAP_SERVER_VERIFICATION_ENABLED PT_IAP_COIN_PACKS_ENABLED
       PT_IAP_REMOVE_ADS_ENABLED PT_IAP_PREMIUM_SKINS_ENABLED PT_AUTHORITATIVE_ECONOMY_ENABLED)
read_key() { /usr/libexec/PlistBuddy -c "Print :$1" "$PLIST" 2>/dev/null; }
fail=0
for f in "${FLAGS[@]}"; do
  v="$(read_key "$f" || true)"
  if [[ "$v" == "NO" || "$v" == "false" ]]; then
    echo "  ok   $f = $v"
  else
    echo "  FAIL $f = '${v:-<missing>}'"; fail=1
  fi
done
echo "PT_BACKEND = $(read_key PT_BACKEND || echo '<missing>')"
if [[ $fail -ne 0 ]]; then echo "FAIL: monetization flag not NO in built app"; exit 1; fi
echo "PASS: built app has all monetization flags = NO"
