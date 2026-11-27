# Cosmetic Studio — Integration Contract v1

Branch: `feature/modular-cosmetic-studio` (base `origin/release/1.2.0` @ `f0e2091`).
Status: engineering contract between the Lead Orchestrator and Agents A–E, and
between this branch and the release/1.2.0 session (PR #14).

## 1. Files this branch must NOT modify (owned by the release/1.2.0 session)

These have uncommitted work in the release worktree (`perfect-tap-release`) as of
2026-11-27 and are off-limits here:

```
ios/PerfectTap/Models/PlayerProfile.swift          ios/PerfectTap/Services/Economy/*
ios/PerfectTap/Services/EntitlementLedger.swift    ios/PerfectTap/Services/PurchaseManager.swift
ios/PerfectTap/Services/Backend/BackendCodec.swift ios/PerfectTap/ViewModels/AuthViewModel.swift
ios/PerfectTap/Models/SeasonPass.swift             ios/PerfectTap/Views/Progression/SeasonPassView.swift
ios/PerfectTap/PerfectTapTests/EconomyServiceTests.swift
supabase/migrations/* (existing files)             supabase/functions/*
.github/workflows/ci.yml                           scripts/qa/assert-built-flags.sh
docs/ECONOMY_SERVICE_CONTRACT.md, docs/RELEASE_1.2.0_RUNBOOK.he.md, docs/SUPABASE_ECONOMY_BACKEND.md
```

Consequences:
- **No new PlayerProfile fields.** The loadout is stored by `CosmeticLoadoutStore`
  in UserDefaults keyed by account id (`pt_cosmetic_loadout.<uid|anon>`).
  Cross-device loadout sync is a follow-up (§6).
- **Ownership = `PlayerProfile.ownedItems`** (unchanged schema). Cosmetic item ids
  (`<collection>.<slotRawValue>`, e.g. `quack_attack.tapButton` — decided at integration; these strings live in `ownedItems` forever, do not change them) are ordinary owned-item
  strings, so existing sync, restore, account switching and server `set_profile_item`
  work without schema changes.
- Coin purchases go through the **existing** `EconomyManager.buyItemForCurrentRollout(ShopItem)`
  → `EconomyService.purchaseItem`. Cosmetic items are bridged to `ShopItem` (category
  `.cosmetics`). No new wallet, no client-side amounts in authoritative mode.

## 2. Domain model (ios/PerfectTap/Models/Cosmetics)

| Type | Role |
|---|---|
| `CosmeticSlot` | tapButton, tapSound, lifeIcon, tapEffect, perfectEffect, missEffect, lifeLostEffect, gameOverEffect, haptics |
| `CosmeticItem` | id, version, slot, collectionID, name, rarity, proposedPrice, `CosmeticAssetRefs`, availability |
| `CosmeticCollection` / `CosmeticBundle` | membership; bundle id `bundle.<collection>` (never stored as owned) |
| `CosmeticLoadout` | slot → item id selection; missing = default |
| `ResolvedCosmetics` | loadout after ownership validation — the only thing renderers read |
| `CosmeticCatalog` | data-only specs for `default`, `quack_attack`, `purrfect_tap`, `boom_mode` |
| `CosmeticEvent` | tap, good, great, perfect, miss, lifeLost, gameOver |

## 3. Cross-agent interfaces (stubs exist in the contract commit)

| Interface | File | Owner | Consumers |
|---|---|---|---|
| `CosmeticLoadoutStore.shared` (`resolved`, `equip(_:)`, `equip(collection:)`, `refresh()`, `previewResolved(_:)`) | Models/Cosmetics/CosmeticLoadoutStore.swift | A | GameView, Shop, Studio |
| `CosmeticTapButtonSkin`, `CosmeticLivesView` views | Views/Game/Cosmetics/ | A | GameView, Studio |
| `CosmeticEffectLayer(resolved:trigger:origin:)` | Views/Game/Cosmetics/CosmeticEffectLayer.swift (+ Effects/) | B | GameView, Studio |
| Asset names in `CosmeticCatalog` (`cos_quack_button`, …) | Assets.xcassets/Cosmetics/ | B | A's views |
| `SoundEngine.playTapOutcome(_:)`, `playGameOverCosmetic()`, `setActiveSoundPack(_:)`, `previewSound(_:packID:)`, `stopPreview()` | Services/CosmeticAudio/ | C | GameViewModel (A), Studio (D) |
| `HapticsEngine` style routing (`setActiveHapticStyle(_:)`, `playTapOutcome(_:)`) | Services/HapticsEngine.swift | C | GameViewModel (A) |
| `ShopItem.cosmetics`, `ShopCategory.cosmetics`, bundle purchase in `EconomyManager` | Models/ShopItem.swift, Services/EconomyManager.swift | D | Shop, Studio |
| `FeatureFlags.cosmeticStudioEnabled` (`PT_COSMETIC_STUDIO_ENABLED`) | Utils/FeatureFlags.swift, project.yml | D | Shop, GameView |

Rules:
1. Cosmetic code is **off the scoring path**: TimingEngine and score/lives/speed logic
   in GameViewModel are not modified. A only replaces the sound/haptic *dispatch*
   lines after scoring with `playTapOutcome`.
2. With the default loadout the game must be pixel- and sound-identical to before.
3. No I/O, decoding, or catalog scans on the tap path. Packs are preloaded on round setup.
4. Effects obey `EffectsLevel` (`.off` = nothing; `.reduced` = no motion bursts).
5. Previewing never writes the loadout, ownedItems, coins, stats, quests or analytics economy events.

## 4. Feature flag

`PT_COSMETIC_STUDIO_ENABLED` (Info.plist, project.yml per configuration):
Debug / Debug-StoreKit = `YES`, Release / Release-IAP = `NO`. Flag OFF ⇒ the shop
shows no Studio entry and gameplay resolves the default loadout (byte-for-byte
current behaviour). Turning it on for release is an owner decision.

## 5. Authoritative economy (flag `PT_AUTHORITATIVE_ECONOMY_ENABLED`)

Server `purchase_economy_item` only accepts ids present in `private.economy_shop_items`
for the active config. New cosmetic ids are **not** there, so in authoritative mode
purchases return `item_unavailable` and the client shows *Preview only*. A proposed
(not applied) migration that adds rows and an atomic `purchase_economy_bundle` RPC lives in
`supabase/proposals/` and must be reviewed by the economy session before it is moved into
`supabase/migrations/`. Never deployed from this branch.

## 6. Follow-ups that need the release session

- Add `equipped_cosmetics` (jsonb, slot → id) to the profile sync once PlayerProfile
  changes from PR #14 have landed (custom `Decodable` with defaults).
- Merge the proposed economy migration with the hardening migration (`20261127110000`).
- `project.pbxproj` is regenerated by XcodeGen on this branch; on merge, regenerate after
  merging rather than hand-resolving pbxproj conflicts.
