# App Review response — Guideline 5.1.2(i) (draft for owner review)

> **Status:** draft. Not sent. Send only after (1) build 1.1.0 (3) is uploaded and attached to version 1.1.0,
> (2) the App Privacy questionnaire is published (`docs/APP_PRIVACY_DECLARATION.he.md`), and
> (3) a quick check of build 3 on a real device (build 2 already passed the owner's full device test on 13.11.2026).
> Remove any sentence below that is not true at the time of sending.
>
> **Where to send:** App Store Connect → PerfectTap → App Review → the open submission (Guideline 5.1.2(i)) → Reply.
> Then replace the build in version 1.1.0 and use **Resubmit to App Review** on the same submission
> (it is `UNRESOLVED_ISSUES`, so it is updated and resubmitted rather than replaced by a new one).

---

Hello App Review team,

Thank you for reviewing PerfectTap!. We have addressed the issue raised under Guideline 5.1.2(i).

**Issue.** Our App Privacy information indicates that the app collects Device ID for tracking, but version 1.01 did not use App Tracking Transparency to request permission.

**Root cause.** The app shows ads through the Google Mobile Ads SDK, which can use the device's advertising identifier for personalized advertising. The App Privacy information was correct, but the app did not present the ATT prompt before ads were initialized.

**What changed in version 1.1.0 (build 3):**
- The app now uses AppTrackingTransparency. On first launch, before the ad SDK is started or any ad is requested, the system prompt is shown with this purpose string: *"PerfectTap shows ads. If you allow tracking, ads can be more relevant to you. If you don't, you'll still see ads, but they won't be personalized. The game works the same either way."*
- Personalized ads are enabled only if the user selects **Allow**. If the user selects **Ask App Not to Track**, or tracking is restricted, the advertising identifier is not used, ads are non-personalized, and advertising signals from Firebase Analytics stay disabled.
- Gameplay, progress and all features are identical whatever the user chooses.
- Where required by law (EEA, UK, Switzerland), Google's certified consent message (Google User Messaging Platform) is shown before ads are requested. In those regions, usage analytics runs only with the user's consent to device storage, and no advertising signals are sent from Firebase Analytics.
- An unused push-messaging SDK was removed.
- Users can review their choice at any time in **Settings → Privacy → Ad Tracking** (opens iOS Settings) and, where applicable, **Settings → Privacy → Privacy Choices**.
- The app's privacy manifest, our App Privacy information and our Privacy Policy (https://oyaholding.github.io/PerfectTap/) now describe this behavior consistently.

**How to test (iPhone or iPad):**
1. Install the app fresh and open it. The ATT prompt appears within a few seconds, on the first screen.
2. Choose **Ask App Not to Track**. Enter any name and play. Ads appear and the game works.
3. Open **Settings → Privacy → Ad Tracking**. It shows "Not allowed — ads are not personalized."
4. (Optional) Reinstall, choose **Allow**, and check that Settings shows "Allowed."

No login or demo account is needed.

**Testing we performed:** the prompt, both answers, and a single prompt per install were tested on iPhone and on iPad Air 11-inch (M3) simulators, and on a real device via TestFlight.

Thank you,
PerfectTap! team — PerfectTap@oyaholding.com

---

## App Review notes (for the "Notes" field of version 1.1.0)

```
No login is required: a player account is created automatically after choosing a name.
This is a reaction-based arcade game. Ads may appear between runs; rewarded ads are optional (revive / continue).
App Tracking Transparency: the system prompt appears on first launch, before any ad is requested.
Denying tracking keeps all features; ads are then non-personalized.
Privacy choices: Settings → Privacy (Ad Tracking, and Privacy Choices where required by law).
Account deletion: Settings → Delete Account.
```
