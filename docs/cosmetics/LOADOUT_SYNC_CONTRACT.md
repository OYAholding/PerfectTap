# Cosmetic loadout — cross-device sync contract (PROPOSED, not wired)

Status: **prepared only**. The owner approved this work, coordinated with PR #14.
Nothing in the app reads or writes the field yet. Wiring it means changing
`PlayerProfile.swift`, `BackendCodec.swift` and `save_profile` / `sanitize_economy`.
The release session owns those files, so the wiring happens after PR #14 merges
(see "Migration order" below).

Pure client side, already in this branch:
`ios/PerfectTap/Models/Cosmetics/CosmeticLoadoutSync.swift` (`encode`, `decode`,
`merge`, `changedSlots`). Tests: `PerfectTapTests/CosmeticEconomyHardeningTests.swift`.

## 1. Field

| | |
|---|---|
| Profile key (server JSON, `private.profile_data.data`) | `equipped_cosmetics` |
| Type | jsonb object, `slot rawValue → item id` (both strings) |
| Example | `{"tapButton": "quack_attack.tapButton", "haptics": "boom_mode.haptics"}` |
| Missing key / `null` / `{}` | every slot is the default (old profiles, old clients) |
| Default items | never sent: a missing slot means "default" |
| Size | 9 slots today; more than 32 entries is rejected as a whole (client and server) |

Slot names are `CosmeticSlot.rawValue` (`tapButton`, `tapSound`, `lifeIcon`,
`tapEffect`, `perfectEffect`, `missEffect`, `lifeLostEffect`, `gameOverEffect`,
`haptics`). Item ids are `<collection>.<slot>` (`CosmeticItem.makeID`). These are the same strings
that are stored in `owned_items`.

## 2. Client decoding (PlayerProfile, release-owned)

- Proposed `PlayerProfile` property: `var equippedCosmetics: [String: String]? = nil`. It is an
  optional, so the synthesized `Codable` used for local persistence still decodes
  every profile saved by an older build (the key is absent → `nil` → default loadout). If the
  property must not be optional, write a custom `init(from:)` with
  `decodeIfPresent(...) ?? [:]`. Never use a non-optional synthesized property: old local
  profiles would fail to decode as a whole.
- `BackendCodec.decodeProfile`: `p.equippedCosmetics = CosmeticLoadoutSync.encode(CosmeticLoadoutSync.decode(data["equipped_cosmetics"]))`.
  This keeps only the slots and ids this build understands, and never throws.
- `BackendCodec.encodeProfile`: `"equipped_cosmetics": CosmeticLoadoutSync.encode(loadout)`.
- `CosmeticLoadout` already decodes per entry and drops unknown slots (a newer build's
  slot never breaks an older build). `CosmeticLoadoutSync.decode` applies the same
  rule to the wire value, and also drops unknown ids, ids of another slot,
  non-string values and default ids.

## 3. Merge / conflict rule: server wins, except unacknowledged local edits

When a server profile arrives (sign-in, refresh, or after a save):

```
for each slot:
    pending (changed on this device, not yet acknowledged by a successful save)
        → keep the local value (including a local "back to default")
    otherwise
        → take the server value
```

`CosmeticLoadoutSync.merge(server:local:pendingLocalSlots:)`. The store adds
`changedSlots(from:to:)` to its pending set on each local equip. It clears a slot
when a profile save that carried that value succeeds.

Why this rule and not last-write-wins on the profile's `updated_at`:

- `updated_at` belongs to the whole profile. Every save (a finished game, coins, quests) bumps it,
  so it says nothing about which device last changed the *loadout*. Comparing
  timestamps would let a game finished on device A overwrite a loadout change
  made on device B a minute earlier.
- Per-slot timestamps would need a new clock per slot. Device clocks are not
  trustworthy, and the loadout is cosmetic and low value, so it does not need that.
- "Server wins" is deterministic and clock-free. It matches how ownership already works (the
  server copy is the truth). The pending-slot exception makes sure an edit made offline,
  or just before the app was killed, is not silently reverted on the next fetch. The
  edit wins until the save that carries it succeeds.
- At **sign-in** to an account on a new device, nothing is pending, so the server loadout is
  applied as is. That is the expected "my look follows me" behaviour.

The local per-account storage (`pt_cosmetic_loadout.<uid>`) stays the cache and the offline
copy. The merge result is written there.

## 4. Server validation (in `save_profile` → sanitize, proposed)

Run after `owned_items` has been sanitized (so it sees the final ownership):

1. If `equipped_cosmetics` is not a JSON object, or has more than 32 keys → drop the key (stored value kept).
2. For each entry, keep it only if:
   - the key is one of the 9 slot names (unknown slots are dropped),
   - the value is a string that matches `^[a-z0-9_]+\.<key>$` (the id belongs to that slot),
   - the value is `default.<slot>` **or** is present in the sanitized `owned_items`.
     A default is accepted but should not be sent, and the server may drop it.
3. Never grant anything. The field can never add to `owned_items`. Ownership comes only from
   the ledger (`purchase_economy_item` / `purchase_economy_bundle`) or, before
   activation, the legacy rules.
4. A revoked item that is still equipped is dropped on the next save. Until then, every
   client already resolves it to the slot default (`ResolvedCosmetics.resolve`).

pgTAP (proposed, written together with the migration): unknown slot dropped; wrong-slot id dropped;
unowned id dropped; owned id kept; non-object ignored; oversized ignored; the field
never changes `owned_items`.

## 5. Privacy

The field holds only catalog item ids chosen by the player: no PII, free text,
device identifiers or timestamps. It lives in `private.profile_data` like `equipped_theme`,
and is visible only to its owner through `get_my_profile`. It is not exposed through
`public.profiles`, leaderboards or friends. Showing a friend's look would be a separate,
explicit decision. Analytics never log the loadout dictionary.

## 6. Migration order (with PR #14)

1. PR #14 (release/1.2.0) merges to `main`. Cut `release/1.2.1` from `main`. Retarget PR #15. Merge
   `main` into `feature/modular-cosmetic-studio` with a merge commit.
2. Server: one migration adds the `equipped_cosmetics` validation to the sanitize path.
   The column needs no change, because `data` is jsonb. It ships **before** any client that sends
   the field. Old clients never send it, and the field is kept as stored when the key is absent.
3. Client (release session or with their approval): `PlayerProfile.equippedCosmetics`
   (optional), `BackendCodec` encode/decode through `CosmeticLoadoutSync`,
   `CosmeticLoadoutStore` keeps the pending-slot set and merges on profile fetch.
4. Rollout behind `PT_COSMETIC_STUDIO_ENABLED` (Release OFF until the owner flips it).
   With the flag OFF the store resolves defaults whatever the field says.

Not decided here (owner/release session): whether a stale client save that omits the key
should keep the stored value (proposed: yes, absent = keep) or clear it.
