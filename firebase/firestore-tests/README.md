# Firestore rules tests

Replays every Firestore write the iOS client makes (same payloads as
`PerfectTap/Services/FirebaseService.swift`) plus attack attempts, against the
local emulator. Nothing touches production.

```bash
brew install openjdk@21                     # once
export PATH="/opt/homebrew/opt/openjdk@21/bin:$PATH"
cd firestore-tests && npm install && npm test
```

**Rule of thumb:** if you change what the app writes, add a `client:` test here
first — a rule the shipped client violates means silently failing saves.

Deploy (owner only, after tests pass):
```bash
firebase deploy --only firestore:rules --project perfecttap-48a08
```
