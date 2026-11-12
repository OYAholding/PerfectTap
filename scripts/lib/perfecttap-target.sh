# Shared guard: resolves and verifies the PerfectTap Supabase project.
# Source it, then call: verify_perfecttap_target "<ref>"
# Refuses Corelim refs, other orgs, non-EU regions and non-PerfectTap names.
PERFECTTAP_ORG="ddbgkcsgayqtsnhqjszs"   # "OYA Games" (recreated Nov 2026)
CORELIM_REFS=("wjyougesuxfkucpmgoyx" "ulrdeytlwqetfzishxuj")   # Corelim, Corelim Test — never touch
PERFECTTAP_REF_FILE="supabase/.perfecttap-ref"

resolve_perfecttap_ref() {
  local ref="${1:-${PERFECTTAP_REF:-}}"
  [[ -z "$ref" && -f "$PERFECTTAP_REF_FILE" ]] && ref="$(tr -d '[:space:]' < "$PERFECTTAP_REF_FILE")"
  [[ -n "$ref" ]] || { echo "No project ref: pass one, set PERFECTTAP_REF, or run scripts/use-supabase-project.sh <ref>" >&2; return 2; }
  echo "$ref"
}

verify_perfecttap_target() {
  local ref="$1"
  for bad in "${CORELIM_REFS[@]}"; do
    if [[ "$ref" == "$bad" ]]; then echo "REFUSING: $ref is a Corelim project" >&2; return 2; fi
  done
  supabase projects list -o json 2>/dev/null | python3 scripts/lib/verify_target.py "$ref" "$PERFECTTAP_ORG"
}
