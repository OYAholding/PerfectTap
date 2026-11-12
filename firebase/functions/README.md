# Cloud Functions (verified scores)

| Function | Purpose |
|---|---|
| `startGame({mode})` | Issues a single-use, server-timed session (`game_sessions/{id}`), rate-limited to 20/min/user. |
| `submitScore({sessionId, mode, score, maxCombo, taps, perfects})` | Validates the run against the session's **server** start time and writes `leaderboard/{mode}/scores/{uid}` if it's a new best. Old clients (no `sessionId`) get `{accepted:false, reason:'update_required'}`. |

Region `europe-west1` (Firestore is `eur3`). `maxInstances: 10` caps cost.
Score rules live in `src/scoring.ts` and must mirror `GameConfig.swift` / `GameMode.swift`
(`testRankedModesMatchServer` in the Swift tests pins the ranked-mode list).

## Test
```bash
export PATH="/opt/homebrew/opt/openjdk@21/bin:$PATH"
cd functions && npm install && npm test      # 9 unit + 10 emulator tests
```
Run the iOS app against local emulators (DEBUG builds only):
```bash
firebase emulators:start --only auth,firestore,functions --project perfecttap-48a08
SIMCTL_CHILD_PT_USE_EMULATORS=1 xcrun simctl launch booted com.perfecttap.app
```

## Deploy (owner approval; needs the Blaze plan)
```bash
firebase deploy --only functions --project perfecttap-48a08
```
After deploy, enable a Firestore TTL policy on `game_sessions.expires_at` so old
sessions are deleted automatically (Console → Firestore → TTL).

## Known limit
Validation proves a score is *achievable in the real elapsed time with the reported
taps*; it can't prove the taps were accurate. Next step: server replay of a tap log.
