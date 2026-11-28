# Integration plan: PR #14 (release/1.2.0) and PR #15 (Cosmetic Studio)

Status 2026-11-28. Read-only analysis. Neither PR is merged, nothing is deployed, and no flag is enabled.

## Facts

| | PR #14 `release/1.2.0` → `main` | PR #15 `feature/modular-cosmetic-studio` → `release/1.2.0` |
|---|---|---|
| Head | `94a680e` + this commit | `81f7ce3` (draft) |
| CI | green (both runs for `94a680e`) | `ios-unit-tests` FAIL: 15 failures, all in its new `CosmeticAudioTests.swift` (pack-preload waits time out at 10 s and the next tests inherit the in-flight pack via `coldPackID()`). `ios-release-build` was cancelled because GitHub never assigned a runner. Everything else is green |
| Relation | | 7 commits behind release (6 code, 1 docs). `git merge-tree` is clean (`b7b7702`), and no file is changed on both sides |
| Size | | +165 files / ~13.9 MB. About 1.6 MB of sounds and images ships in the app even with the flag off |
| Flag | | `PT_COSMETIC_STUDIO_ENABLED`: YES in Debug and Debug-StoreKit, NO in Release and Release-IAP (project.yml and pbxproj) |

## Verified on release/1.2.0

- **QA-01** (a duplicate `event_key` grants a different item for free) is fixed by `supabase/migrations/20261127110000_economy_hardening.sql`. A replay with another item raises `invalid_payload`, charges nothing and grants nothing. A same-item replay returns `duplicate`.
  - PR #15's own repro (`docs/cosmetics/qa/sql/purchase_item_duplicate_event_key.test.sql`) now stops with `invalid_payload` at the replay. Its last assertion (no free item) holds.
  - An explicit regression test is now in `supabase/tests/database/economy_hardening.test.sql` (QA-01 block). pgTAP passes 377/377 locally.
- **Compatibility:** PR #15 changes no purchase id, shop item id, IAP product id, `PlayerProfile` encoding or balance logic. It doesn't touch `Services/Economy/*`, `PurchaseManager`, `EntitlementLedger`, `PlayerProfile` or the migrations. The `EconomyManager` changes only add code, and cosmetic purchases refuse when the authoritative economy is on.
- **Guards:** `PT_COSMETIC_STUDIO_ENABLED` and `PT_EMAIL_OTP_ENABLED` are now checked:
  - `scripts/security/check-monetization-flags.sh`: never exempt under Release-IAP. `Debug-*` configs are now treated as Debug in project.yml too, matching the pbxproj rule. Before this fix, the merged tree failed on `Debug-StoreKit`.
  - `scripts/qa/assert-built-flags.sh`: must be NO when present. Absent counts as off.
  - Run against the merged tree `b7b7702`, the guard passes. It fails if the cosmetic flag is set to YES in Release-IAP.

## Must fix before the cosmetic server catalog becomes a migration (not blockers for a flag-off merge)

1. **F1 (high):** cosmetic ids are not server-owned until `cosmetic-studio-rc1` is active. Once the authoritative economy is on, a profile save could add them to `owned_items`, and they would survive activation.
   - Fix: register the cosmetic ids, disabled, under the active config. `server_owned_items` ignores `enabled`.
   - Or strip cosmetic ids that have no ledger entry when the config is activated.
2. **F2 (medium):** `purchase_economy_bundle` locks `profile_data` before `economy`. The rule is economy first (hardening L1), so the bundle can deadlock against `purchase_economy_item`.
3. **F3 (low):** grant only when `status = 'applied'`. Return `invalid_payload` for a key reused with another bundle, and run the delta before the `already_owned` short-circuit, as `purchase_economy_item` does.
4. **F4:** the `economy_shop_items` primary key change to `(config_version, item_id)` is safe, but the economy owner must agree to it.
5. **Cross-device loadout (future):** an optional `equipped_cosmetics` jsonb in the profile, last writer wins. `sanitize_economy` drops any id that is neither owned nor a Classic default, and caps the size. Keep the client's round-start ownership check.

## Decided path (owner, 2026-11-28): ship Cosmetic Studio in 1.2.1, not 1.2.0

Why:
- 1.2.0 is QA-signed at `94a680e`, including the idle perf gate 3/3. PR #15 changes `SoundEngine`, `GameView` and `GameViewModel` on paths that run even with the flag off, so merging it would invalidate that evidence.
- Its CI is red.
- Its prices, art and server catalog are unapproved.

Steps:
1. **Now (this commit):** both guards in release/1.2.0 already cover the cosmetic flag. Nothing else from PR #15 goes into 1.2.0.
2. **Cosmetic session, in its own worktree:**
   - Fix `CosmeticAudioTests`: `coldPackID()` must skip in-flight packs, reset the engine between tests, and wait on a signal rather than a 10 s poll.
   - Update `RELEASE_INTEGRATION_NOTES.md` (QA-01 is fixed in release).
   - Fix F1–F3 in `supabase/proposals/`, test it on top of the hardening migration, and keep it a proposal.
3. **After the owner merges PR #14 into `main`:**
   - Cut `release/1.2.1` from `main` and retarget PR #15 to it (`gh pr edit 15 --base release/1.2.1`).
   - The cosmetic session merges `release/1.2.1` into its branch with a merge commit (no rebase).
4. **Before PR #15 can merge:**
   - CI fully green, including a real Release and Release-IAP build with both flag asserts.
   - The full suite and one idle perf gate (default plus one cosmetic loadout).
   - Device QA-02 per `docs/DEVICE_TEST_PROCEDURE_1.2.0.he.md` §1/§3 (build C).
5. Owner approval to merge PR #15 into `release/1.2.1`. The flag stays NO until prices and assets are approved.

## Alternative considered and declined: include it in 1.2.0

Same steps 2 and 4, but against `release/1.2.0`, then a merge commit into release/1.2.0. After that, PR #14's QA evidence must be rerun (full suite, Release and Release-IAP flag asserts, perf gate) before TestFlight.

## Merge order to `main` (unchanged)

PR #12 → PR #13 → PR #14, or #14 alone. Use merge commits, not squash. Merging needs owner approval.
