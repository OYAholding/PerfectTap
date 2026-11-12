# PerfectTap!

One-tap timing game for iOS (SwiftUI) with friends, duels and verified leaderboards.
Backend: **Supabase** (Frankfurt, `eu-central-1`). Public pages: GitHub Pages from `website/`.

```
ios/PerfectTap/        Xcode project (XcodeGen: project.yml), app sources, PerfectTapTests/
supabase/              migrations/, functions/ (Edge Functions), tests/, config.toml
website/               Privacy Policy, Terms, Support (GitHub Pages)
scripts/               guarded deploy/config scripts, Firestore → Supabase migration
docs/                  architecture, migration and audit reports (Hebrew)
firebase/              legacy Firebase backend — kept for rollback until cutover
legacy/                pre-iOS web version (Base44) — reference only
.github/workflows/     CI: secret scan, backend tests, Pages deploy
```

## Backend switch
`PT_BACKEND` (build setting → Info.plist) selects the backend. From **1.1.0 both Debug and Release use
`supabase`** (Frankfurt). App Store builds ≤ 1.0.2 keep using Firebase, which stays running; their
players move over through `claim-legacy-account` on first launch of 1.1.0. Release, monitoring and
rollback limits: `docs/RELEASE_PLAN_1.1.0.he.md`. Unit tests always use an offline backend.

`PT_EMAIL_OTP_ENABLED` (default `NO`) gates Cloud Backup sign-up, which needs verified email delivery
(custom SMTP). It is never bypassed.

Only the Supabase **publishable** key ships in the app (`ios/PerfectTap/project.yml`).
Secret / service-role keys live only in Supabase Edge Function secrets — never commit one
(`gitleaks` with `.gitleaks.toml` blocks `sb_secret_…`).

## Develop & test
```bash
# Backend (local Docker stack on ports 556xx; never touches the cloud)
supabase start
supabase test db --local                      # pgTAP: RLS, state machine, validation
./supabase/tests/integration/run.sh           # end-to-end: concurrency, Realtime, Edge Functions

# iOS
cd ios/PerfectTap && xcodegen generate
xcodebuild test -project PerfectTap.xcodeproj -scheme PerfectTap \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
# UI mode matrix (Debug → Supabase cloud; creates one test player — delete it afterwards)
xcodebuild test -project PerfectTap.xcodeproj -scheme PerfectTapUITests \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

## Deploy (PerfectTap project only)
```bash
./scripts/deploy-supabase.sh            # verifies org/region/ref, prints plan (dry run)
./scripts/deploy-supabase.sh --apply    # migrations, secrets, functions, auth config
```
The guard (`scripts/lib/perfecttap-target.sh`) refuses any project that is not the EU
PerfectTap project in the "OYA Games" organization.

Support: PerfectTap@oyaholding.com
