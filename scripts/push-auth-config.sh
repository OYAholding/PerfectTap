#!/usr/bin/env bash
# Pushes supabase/config.toml settings to the verified PerfectTap project.
# On the Free plan with Supabase's default email provider, custom email
# templates are rejected (entitlement_required), so the [auth.email.template.*]
# blocks are stripped from a temporary copy until custom SMTP is configured.
# Set PUSH_EMAIL_TEMPLATES=1 once SMTP is set up in the dashboard.
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/lib/perfecttap-target.sh
REF="$(resolve_perfecttap_ref "${1:-}")"
verify_perfecttap_target "$REF"

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/supabase"
cp -R supabase/templates "$TMP/supabase/" 2>/dev/null || true
if [[ "${PUSH_EMAIL_TEMPLATES:-0}" == "1" ]]; then
  cp supabase/config.toml "$TMP/supabase/config.toml"
else
  python3 - supabase/config.toml "$TMP/supabase/config.toml" <<'PY'
import re, sys
src = open(sys.argv[1]).read()
# Drop every [auth.email.template.<name>] table (header + its key lines).
out = re.sub(r'(?ms)^#[^\n]*\n(?=\[auth\.email\.template\.)|^\[auth\.email\.template\.[^\]]+\]\n(?:(?!\[)[^\n]*\n)*', '', src)
open(sys.argv[2], "w").write(out)
PY
fi
supabase config push --workdir "$TMP" --project-ref "$REF" "${@:2}"
