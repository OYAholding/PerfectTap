#!/usr/bin/env bash
# Deploys the PerfectTap backend to its dedicated Supabase project ONLY.
#
#   ./scripts/deploy-supabase.sh            # dry run: verifies target, prints plan
#   ./scripts/deploy-supabase.sh --apply    # performs the hosted changes
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
# Public Firebase Web API key (already shipped in GoogleService-Info.plist); used
# server-side only to verify legacy email/password logins during migration.
FIREBASE_WEB_API_KEY="$(/usr/libexec/PlistBuddy -c 'Print :API_KEY' PerfectTap/GoogleService-Info.plist)"

echo "Supabase CLI: $(supabase --version 2>/dev/null | head -1)"
verify_perfecttap_target "$PERFECTTAP_REF"
grep -q "https://$PERFECTTAP_REF.supabase.co" PerfectTap/project.yml \
  || { echo "REFUSING: app (project.yml) does not point at $PERFECTTAP_REF — run scripts/use-supabase-project.sh $PERFECTTAP_REF" >&2; exit 2; }

cat <<PLAN

Plan (hosted, project $PERFECTTAP_REF only):
  1. supabase link --project-ref $PERFECTTAP_REF        (CLI login role; no DB password needed on CLI 2.119)
  2. supabase db push --linked                          (2 migrations: core schema, legacy import)
  3. supabase secrets set FIREBASE_PROJECT_ID / FIREBASE_WEB_API_KEY
  4. supabase functions deploy claim-legacy-account delete-account
  5. scripts/push-auth-config.sh (anonymous sign-ins, email confirmation, OTP; templates skipped on default SMTP)
  6. supabase db advisors --linked
PLAN

[[ "${1:-}" == "--apply" ]] || { echo; echo "Dry run only. Re-run with --apply to deploy."; exit 0; }

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
