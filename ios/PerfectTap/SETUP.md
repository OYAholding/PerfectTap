# Perfect Tap — iOS App Setup Guide

## Step 1: Create Xcode Project

1. Open **Xcode** → File → New → Project → **App**
2. Fill in:
   - Product Name: `PerfectTap`
   - Organization Identifier: `com.yourname` (your choice)
   - Interface: **SwiftUI**
   - Language: **Swift**
   - Minimum Deployment: **iOS 16.0**
3. Save into the `PerfectTap/` folder (next to the existing Swift files)

## Step 2: Add Existing Swift Files

In Xcode's file navigator, right-click the `PerfectTap` group → **Add Files to "PerfectTap"**.
Add all the `.swift` files from these folders:
- `Models/`
- `ViewModels/`
- `Views/` (all subfolders)
- `Services/`
- `Components/`
- `Utils/`

Make sure **"Copy items if needed"** is OFF (the files are already in the right place).

## Step 3: Add Firebase SDK

1. File → **Add Package Dependencies…**
2. Paste URL: `https://github.com/firebase/firebase-ios-sdk`
3. Click **Add Package**
4. Select these packages:
   - ✅ **FirebaseAuth**
   - ✅ **FirebaseFirestore**
   - ✅ **FirebaseFunctions**
   - ✅ **FirebaseAnalytics** (optional)

## Step 4: Set Up Firebase Console

1. Go to [console.firebase.google.com](https://console.firebase.google.com)
2. **Create a new project** → name it "PerfectTap"
3. Add an **iOS app**:
   - Bundle ID: same as your Xcode Bundle ID (e.g. `com.yourname.PerfectTap`)
   - Download **`GoogleService-Info.plist`**
   - Drag it into your Xcode project (make sure it's added to the app target)
4. Enable **Email/Password Authentication**:
   - Firebase Console → Authentication → Sign-in method → Email/Password → Enable
5. Create **Firestore Database**:
   - Firebase Console → Firestore Database → Create database → Start in production mode
   - Add Firestore rules (below)

## Step 5: Firestore Security Rules

In Firebase Console → Firestore → Rules, paste:

```
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    match /players/{userId} {
      allow read: if request.auth != null;
      allow write: if request.auth != null && request.auth.uid == userId;
    }
    match /duels/{duelId} {
      allow read: if request.auth != null;
      allow create: if request.auth != null;
      allow update: if request.auth != null;
    }
  }
}
```

## Step 6: Enable Firebase in the App

In `PerfectTapApp.swift`, uncomment the Firebase lines:

```swift
import FirebaseCore   // add this import at the top

init() {
    FirebaseApp.configure()   // uncomment this line
}
```

Also in `FirebaseService.swift`, the `#if canImport(FirebaseFirestore)` guards will
automatically activate once the SDK is added.

## Step 7: Deploy Cloud Functions (Optional — for score validation + duels)

If you want server-side score validation and duel management:

1. Install Firebase CLI: `npm install -g firebase-tools`
2. In Terminal: `firebase login`
3. Create a `functions/` folder in your project root
4. Port the 4 functions from the original React app's `functions/` folder to Node.js:
   - `createDuel.ts` → `functions/src/createDuel.ts`
   - `joinDuel.ts`   → `functions/src/joinDuel.ts`
   - `submitScore.ts` → `functions/src/submitScore.ts`
   - `cleanupDuels.ts` → scheduled function
5. Deploy: `firebase deploy --only functions`

## Step 8: Build & Run

1. Select a Simulator (iPhone 15 Pro recommended)
2. Press **⌘R** to build and run
3. Sign up with an email → set a username → play!

---

## Architecture Overview

```
PerfectTapApp.swift          ← App entry, Firebase config
├── RootView                 ← Auth state router
├── HomeView                 ← Main hub
│   ├── ModeSelectView       ← 6 game modes
│   │   └── GameView         ← Main game (CADisplayLink 60fps)
│   │       └── GameOverView ← Results + XP + achievements
│   ├── DuelLobbyView        ← Create/join 1v1 duels
│   ├── AchievementsView     ← 21 achievements
│   ├── DailyQuestsView      ← 3 daily missions
│   ├── DailyRewardsView     ← 7-day streak rewards
│   ├── LuckyWheelView       ← Daily spin
│   ├── SeasonPassView       ← Season 1 tier progression
│   ├── ChallengesView       ← Persistent challenges
│   ├── FriendsView          ← Add/view friends
│   ├── LeaderboardView      ← Global rankings
│   ├── ProfileView          ← Player stats
│   ├── ShopView             ← Coin packs (StoreKit)
│   └── GameSettingsView     ← Sound/haptics/theme
│
├── GameViewModel            ← Core game engine (CADisplayLink)
├── AuthViewModel            ← Firebase Auth state
├── FirebaseService          ← All Firestore + Functions calls
├── SoundEngine              ← Procedural audio (AVAudioEngine)
├── HapticsEngine            ← UIImpactFeedbackGenerator
└── ThemeManager             ← Active theme (@EnvironmentObject)
```

## Key Game Logic (from Game.jsx)

| Accuracy | Distance from center | Points |
|----------|---------------------|--------|
| PERFECT  | ±4%                 | 100    |
| GREAT    | ±10%                | 70     |
| GOOD     | ±20%                | 40     |
| MISS     | >20%                | 0 + lose 1 life |

**Combo multipliers:** ×1, ×1.5 (3+ combo), ×2 (5+ combo)
**Combo Frenzy:** up to ×6 at 20+ combo

**Speed increases:** Every 5 taps in Classic (-0.08), every 3 taps in Sudden Death (-0.10)

## Notes for Beginners

- The `GameViewModel` uses `CADisplayLink` for 60fps indicator movement — this is the
  Swift equivalent of `requestAnimationFrame` from the web version.
- `@EnvironmentObject` passes the router and theme to all views without prop drilling.
- Firebase is completely optional for local play — everything works offline with
  `UserDefaults` until Firebase is configured.
- For in-app purchases, add StoreKit 2 and replace the `// TODO: StoreKit` comments.
