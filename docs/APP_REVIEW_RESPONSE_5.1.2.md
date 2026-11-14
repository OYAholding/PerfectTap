# App Review response — Guideline 5.1.2(i) (final text, ready to send)

> **Build 4 (14.11.2026):** after the build 3 resubmission, App Store Connect returned **ITMS-91064** (invalid tracking
> information in the app's `PrivacyInfo.xcprivacy`: `NSPrivacyTracking=true` with an empty `NSPrivacyTrackingDomains`).
> Version 1.1.0 became `INVALID_BINARY`. Build **1.1.0 (4)** = build 3 + a corrected privacy manifest only (no code change).
> The follow-up message below was posted in the same thread before resubmitting build 4.
>
> **Status (14.11.2026): final, approved by the owner for sending.** Done: build 1.1.0 (3) is attached to version 1.1.0 (`VALID`,
> export compliance `false`). App Privacy is published (the public App Store page shows it). The AdMob GDPR message is published.
> Review Notes are updated in App Store Connect (below).
> **Real-device status:** the owner tested build 1.1.0 (3) on a real iPhone via TestFlight on 14.11.2026, and it passed.
>
> **Where to send:** App Store Connect → PerfectTap → App Review → the open submission (Guideline 5.1.2(i), `UNRESOLVED_ISSUES`) → **Reply**
> with the text below. Then press **Resubmit to App Review** on the same submission. Build 3 is already attached, so no build change is needed.
> Do not create a new submission.

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
   (On a device in the EEA, UK or Switzerland, Google's consent message appears first, then the ATT prompt.)
2. Choose **Ask App Not to Track**. Enter any name and play. Ads appear and the game works.
3. Open **Settings → Privacy → Ad Tracking**. It shows "Not allowed — ads are not personalized."
4. (Optional) Reinstall, choose **Allow**, and check that Settings shows "Allowed."

No login or demo account is needed.

**Testing we performed:** the prompt, both answers, and a single prompt per install were tested on a real iPhone with this exact build (1.1.0 (3), via TestFlight), and on iPhone and iPad Air 11-inch (M3) simulators, including the EEA consent message.

Thank you,
PerfectTap! team — PerfectTap@oyaholding.com

---

## Follow-up message (build 4)

```
Hello App Review team,

Following up on our message above: after we resubmitted, App Store Connect reported ITMS-91064 (invalid tracking information in the app's privacy manifest) for build 3.

We have uploaded build 1.1.0 (4). It is identical to build 3 except for the corrected privacy manifest: the app's own manifest no longer sets NSPrivacyTracking without tracking domains, and the Device ID is still declared as data used for tracking (the Google Mobile Ads SDK declares its own tracking in its bundled manifest). There are no code changes. The App Tracking Transparency flow, the App Privacy information and the test steps described above are unchanged.

Thank you,
PerfectTap! team — PerfectTap@oyaholding.com
```

## App Review notes (already saved in App Store Connect, 14.11.2026)

```
No login is required: a player account is created automatically after choosing a name.
This is a reaction-based arcade game. Ads may appear between runs; rewarded ads are optional (revive / continue).
App Tracking Transparency: the system prompt appears on first launch, before the ad SDK starts or any ad is requested.
In the EEA, UK and Switzerland, Google's consent message (UMP) is shown first, then the ATT prompt.
Denying tracking keeps all features; ads are then non-personalized.
Privacy choices: Settings → Privacy (Ad Tracking, and Privacy Choices where required by law).
Account deletion: Settings → Delete Account.
```
