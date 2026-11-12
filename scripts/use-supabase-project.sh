#!/usr/bin/env bash
# Points the repo at a (new) PerfectTap Supabase project:
#   ./scripts/use-supabase-project.sh <project-ref>
# Verifies the target (OYA Games org, EU region, not Corelim), fetches ONLY the
# publishable key, updates project.yml, regenerates the Xcode project and
# records the ref in supabase/.perfecttap-ref for deploy-supabase.sh.
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/lib/perfecttap-target.sh
REF="$(resolve_perfecttap_ref "${1:-}")"
verify_perfecttap_target "$REF"

KEY="$(supabase projects api-keys --project-ref "$REF" -o json 2>/dev/null | python3 -c '
import json, sys
data = json.load(sys.stdin)
keys = data if isinstance(data, list) else data.get("keys", data)
pub = [k.get("api_key") or k.get("key") for k in keys if (k.get("type") or k.get("name")) == "publishable"]
if not pub or not pub[0].startswith("sb_publishable_"): sys.exit("No publishable key found (create one in Settings → API Keys)")
print(pub[0])')"

python3 - "$REF" "$KEY" <<'PY'
import re, sys
ref, key = sys.argv[1], sys.argv[2]
p = "ios/PerfectTap/project.yml"
s = open(p).read()
s, n1 = re.subn(r'SUPABASE_URL: "[^"]*"', f'SUPABASE_URL: "https://{ref}.supabase.co"', s)
s, n2 = re.subn(r'SUPABASE_PUBLISHABLE_KEY: "[^"]*"', f'SUPABASE_PUBLISHABLE_KEY: "{key}"', s)
if n1 != 1 or n2 != 1: sys.exit(f"project.yml: expected 1 URL + 1 key line, found {n1}/{n2}")
open(p, "w").write(s)
PY
echo "$REF" > supabase/.perfecttap-ref
(cd ios/PerfectTap && xcodegen generate >/dev/null)
echo "App now points at https://$REF.supabase.co (publishable key only). Next: ./scripts/deploy-supabase.sh"
