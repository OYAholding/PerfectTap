#!/usr/bin/env bash
# Read-only check of the public Firebase iOS API key's restrictions.
# Creates nothing: uses createAuthUri (lookup) and model/API listing calls.
#   ./scripts/security/probe-firebase-key.sh
# Expected AFTER applying "iOS apps: com.perfecttap.app" in Google Cloud:
#   no bundle header      -> BLOCKED (API_KEY_IOS_APP_BLOCKED)
#   com.perfecttap.app    -> OK
#   other bundle id       -> BLOCKED
#   Gemini                -> BLOCKED (API_KEY_SERVICE_BLOCKED)
set -euo pipefail
cd "$(dirname "$0")/../.."
KEY=$(/usr/libexec/PlistBuddy -c 'Print :API_KEY' ios/PerfectTap/GoogleService-Info.plist)
BODY='{"identifier":"probe-nonexistent@example.com","continueUri":"http://localhost"}'

check() {
  local label=$1; shift
  local out; out=$(curl -s -m 15 "$@")
  printf '%-34s ' "$label"
  printf '%s' "$out" | python3 -c '
import json, sys
try:
    d = json.load(sys.stdin)
except Exception:
    print("non-JSON response"); sys.exit()
e = d.get("error") if isinstance(d, dict) else None
if not e:
    print("OK"); sys.exit()
reasons = [x.get("reason") for x in e.get("details", []) if isinstance(x, dict) and x.get("reason")]
print("BLOCKED", e.get("code"), reasons or e.get("status"))'
}
URL="https://identitytoolkit.googleapis.com/v1/accounts:createAuthUri?key=$KEY"
check "Auth, no bundle header"        -X POST "$URL" -H "Content-Type: application/json" -d "$BODY"
check "Auth, com.perfecttap.app"      -X POST "$URL" -H "Content-Type: application/json" -H "X-Ios-Bundle-Identifier: com.perfecttap.app" -d "$BODY"
check "Auth, other bundle id"         -X POST "$URL" -H "Content-Type: application/json" -H "X-Ios-Bundle-Identifier: com.example.other" -d "$BODY"
check "Gemini (must stay blocked)"    "https://generativelanguage.googleapis.com/v1beta/models?key=$KEY" -H "X-Ios-Bundle-Identifier: com.perfecttap.app"
