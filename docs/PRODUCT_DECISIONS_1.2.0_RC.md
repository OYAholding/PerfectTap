# PerfectTap 1.2.0 — provisional product decisions (release candidates)

Approved by the owner on **2026-11-27** as **release candidates for testing**,
not for production activation. Production activation and final live pricing
each still need a separate explicit approval (runbook gates G2/G3/G13).

| Area | RC decision | Where it lives |
|---|---|---|
| Economy model | Model B — `balanced-premium-rc1` | `private.economy_configs` (row stays `active = false`, status `candidate_not_approved`); `EconomyConfig.balancedPremiumRC1` |
| Daily gameplay coin cap | 1,500 coins / UTC day (gameplay + duels) | config `gameplay_daily_cap` |
| Achievement / challenge payout cap | 3,000 coins / UTC day, first claim of the day always passes (security hardening, follows from the RC economy) | config `progress_daily_cap` |
| Seasons | Quarterly, anchored 2026-03-01 UTC, ids `season_<n>`, 30 tiers, 15 tiers/day pacing, **72-hour grace** for claims queued at the boundary | config `season_calendar`; `SeasonSchedule` |
| Seasonal progression | **Resets between seasons**: season XP, tier, claimed tiers, ad progress, ad-unlocked premium | `PlayerProfile.applySeasonRollover` (client, forward-only); server premium = this season's verified ads |
| Preserved across seasons | coins, purchased cosmetics, all owned items incl. historical season rewards, achievements, challenges, lifetime statistics | rollover touches only the five seasonal fields (tests `SeasonRolloverTests`) |
| Refunds | Deduct the available coin balance down to zero; spent coins are not clawed back; **`coin_debt` disabled** | `revoke_purchase`; `docs/SUPPORT_OPERATIONS.md` |
| IAP catalog | The current 9 products and proposed prices, as testing candidates | `fastlane/iap/catalog.json` |

## IAP testing candidates

| Product | Type | USD |
|---|---|---|
| `com.perfecttap.coins.500` | consumable | 0.99 |
| `com.perfecttap.coins.1200` | consumable | 1.99 |
| `com.perfecttap.coins.3000` | consumable | 3.99 |
| `com.perfecttap.coins.8000` | consumable | 9.99 |
| `com.perfecttap.removeads` | non-consumable | 2.99 |
| `com.perfecttap.skin.neonpulse` | non-consumable | 1.99 |
| `com.perfecttap.skin.liquidchrome` | non-consumable | 1.99 |
| `com.perfecttap.skin.glitchmode` | non-consumable | 1.99 |
| `com.perfecttap.skin.cosmicgold` | non-consumable | 1.99 |

No product exists in App Store Connect yet (dry-run reconcile: 9 × `MISSING`).
Creating them is irreversible and stays behind G4.

## Principles kept

No pay-to-win (purchases are cosmetic, ad removal or coins for cosmetics),
no manipulative monetization (no timers/loot boxes/dark patterns), no
unsupported ADHD claims.
