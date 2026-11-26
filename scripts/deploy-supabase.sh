#!/usr/bin/env bash
# Deploys the PerfectTap backend to its dedicated Supabase project ONLY.
#
#   ./scripts/deploy-supabase.sh            # dry run: verifies target, prints plan
#   ./scripts/deploy-supabase.sh --apply              # DB + existing auth functions
#   ./scripts/deploy-supabase.sh --apply-purchases    # Apple secrets + purchase + rewarded-ad SSV functions
# Target ref: $PERFECTTAP_REF or supabase/.perfecttap-ref (set by use-supabase-project.sh).
#
# Guards (scripts/lib/perfecttap-target.sh): OYA Games org, EU region,
# "PerfectTap" name, never the Corelim refs; the app must point at the same ref. You type the database
# password yourself when `supabase link` asks; it is never stored in this repo.
set -euo pipefail
cd "$(dirname "$0")/.."

source scripts/lib/perfecttap-target.sh
PERFECTTAP_REF="$(resolve_perfecttap_ref "${PERFECTTAP_REF:-}")"
FIREBASE_PROJECT_ID="perfecttap-48a08"
EXPECTED_SUPABASE_CLI="2.119.0"
# Public Firebase Web API key (already shipped in GoogleService-Info.plist); used
# server-side only to verify legacy email/password logins during migration.
FIREBASE_WEB_API_KEY="$(/usr/libexec/PlistBuddy -c 'Print :API_KEY' ios/PerfectTap/GoogleService-Info.plist)"

ACTUAL_SUPABASE_CLI="$(supabase --version 2>/dev/null | head -1)"
[[ "$ACTUAL_SUPABASE_CLI" == "$EXPECTED_SUPABASE_CLI" ]] || {
  echo "REFUSING: Supabase CLI $ACTUAL_SUPABASE_CLI; this release script is pinned to $EXPECTED_SUPABASE_CLI." >&2
  echo "CLI v3 changes remote targeting semantics and must be qualified in a separate change." >&2
  exit 2
}
echo "Supabase CLI: $ACTUAL_SUPABASE_CLI (pinned)"
verify_perfecttap_target "$PERFECTTAP_REF"
grep -q "https://$PERFECTTAP_REF.supabase.co" ios/PerfectTap/project.yml \
  || { echo "REFUSING: app (project.yml) does not point at $PERFECTTAP_REF — run scripts/use-supabase-project.sh $PERFECTTAP_REF" >&2; exit 2; }

cat <<PLAN

Plan (hosted, project $PERFECTTAP_REF only):
  1. supabase link --project-ref $PERFECTTAP_REF        (CLI login role; no DB password needed on CLI 2.119)
  2. supabase db push --linked                          (all pending migrations; IAP catalog defaults disabled)
  3. supabase secrets set FIREBASE_PROJECT_ID / FIREBASE_WEB_API_KEY
  4. supabase functions deploy claim-legacy-account delete-account
  5. scripts/push-auth-config.sh (anonymous sign-ins, email confirmation, OTP; templates skipped on default SMTP)
  6. supabase db advisors --linked
PLAN

if [[ "${1:-}" == "--apply-purchases" ]]; then
  [[ "${PT_CONFIRM_PRODUCTION:-}" == "yes" ]] || {
    echo "REFUSING: set PT_CONFIRM_PRODUCTION=yes after the production migration, SMTP and Apple catalog are verified." >&2
    exit 2
  }
  : "${APPLE_ROOT_CAS_B64:?APPLE_ROOT_CAS_B64 is required}"
  : "${APPLE_APP_APPLE_ID:?APPLE_APP_APPLE_ID is required}"
  [[ "$APPLE_APP_APPLE_ID" == "6760975737" ]] || { echo "REFUSING: wrong Apple app id" >&2; exit 2; }
  verify_perfecttap_target "$PERFECTTAP_REF"
  supabase secrets set --project-ref "$PERFECTTAP_REF" \
    APPLE_ROOT_CAS_B64="$APPLE_ROOT_CAS_B64" \
    APPLE_APP_APPLE_ID="$APPLE_APP_APPLE_ID" \
    APPLE_ENABLED_ENVIRONMENTS="Production,Sandbox"
  # admob-ssv (verify_jwt=false: Google calls it) only records rewards while an
  # approved economy config is active; until then every callback fails closed.
  supabase functions deploy verify-purchase app-store-notifications admob-ssv --project-ref "$PERFECTTAP_REF"
  echo "Purchase + SSV backend deployed with both Apple environments. Catalog rows and sales switches remain disabled until explicitly enabled in SQL."
  exit 0
fi

[[ "${1:-}" == "--apply" ]] || {
  echo
  echo "Dry run only. Re-run with --apply for DB/auth, then --apply-purchases after Apple/SMTP gates pass."
  exit 0
}

supabase link --project-ref "$PERFECTTAP_REF"
LINKED="$(cat supabase/.temp/project-ref 2>/dev/null || true)"
[[ "$LINKED" == "$PERFECTTAP_REF" ]] || { echo "REFUSING: linked ref is '$LINKED'" >&2; exit 2; }

supabase db push --linked --yes
supabase secrets set --project-ref "$PERFECTTAP_REF" \
  FIREBASE_PROJECT_ID="$FIREBASE_PROJECT_ID" FIREBASE_WEB_API_KEY="$FIREBASE_WEB_API_KEY"
supabase functions deploy claim-legacy-account delete-account --project-ref "$PERFECTTAP_REF"
./scripts/push-auth-config.sh "$PERFECTTAP_REF" --yes
supabase db advisors --linked || true
echo "Done. Run the cloud smoke test: see supabase/tests/cloud/smoke.test.ts"
