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
`PT_BACKEND` (build setting → Info.plist) selects the backend: **Debug = `supabase`**, **Release = `firebase`**
until the cutover in `docs/SUPABASE_MIGRATION.he.md`. Unit tests always use an offline backend.

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
```

## Deploy (PerfectTap project only)
```bash
./scripts/deploy-supabase.sh            # verifies org/region/ref, prints plan (dry run)
./scripts/deploy-supabase.sh --apply    # migrations, secrets, functions, auth config
```
The guard (`scripts/lib/perfecttap-target.sh`) refuses any project that is not the EU
PerfectTap project in the "OYA Games" organization.

Support: PerfectTap@oyaholding.com
