# PerfectTap 1.1.0 (2) — מוכנות להגשה (12.11.2026)

מקרא: ✅ הושלם ונבדק · 🧪 מומש, לא נבדק במכשיר אמיתי · 🔒 חסום בהרשאות · 👤 דורש אישור/פעולת בעלים

## 1. ביקורת App Store Connect
| נושא | מצב | סיווג |
|---|---|---|
| חיבור API (Team Key, ‏App Manager) | 200 בכל נקודות הקצה. אין גישה לאפליקציות אחרות | ✅ |
| גרסה חיה | 1.0 ‏`READY_FOR_SALE`. שדות נעולים | ✅ |
| גרסה ניתנת לעריכה | **1.01 → 1.1.0** (שונה ונבדק) ‏`PREPARE_FOR_SUBMISSION` | ✅ תוקן |
| Build מחובר ל-1.1.0 | ‏1.0.1 (1), פג תוקף. צריך להחליף ב-1.1.0 (2) אחרי העלאה | 👤 |
| Builds | ‏3, כולם `EXPIRED`, כולם build `1`. הבא: **2** (נבדק מול Apple) | ✅ |
| Review submission | ‏16.4.2026: ‏`UNRESOLVED_ISSUES` / `REJECTED` (5.1.2(i)) | ✅ זוהה |
| Privacy Policy URL ‏(1.1.0) | `…/PerfectTap/` → 200 | ✅ תוקן |
| Support URL ‏(1.1.0) | `…/PerfectTap/support.html` → 200 | ✅ תוקן |
| Marketing URL ‏(1.1.0) | `oyaholding.github.io/` → `…/PerfectTap/` | ✅ תוקן |
| כתובות 1.0 החיה (נעולות) | מפנות דרך `perfecttap-pages` → 200 | ✅ |
| Terms | `…/PerfectTap/terms.html` → 200 | ✅ |
| What's New ‏(1.1.0) | טקסט כללי → פרטיות, שרתי EU, מעבר חשבון | ✅ תוקן |
| Review Notes ‏(1.1.0) | עודכן: ‏ATT, אין login, מחיקת חשבון | ✅ תוקן (מתאר את build 2) |
| איש קשר ל-Review | שם, טלפון, אימייל מלאים. אין צורך ב-demo account | ✅ |
| Name / Subtitle / Keywords / Description / Promo | עקביים, en-US בלבד. לא שונו | ✅ |
| צילומי מסך | ‏iPhone 6.5" ×4, ‏iPad 13" ×4, ‏iPad 11" ×4, כולם `COMPLETE`. אין App Previews | ✅ (אופציונלי: לרענן) |
| Localization | en-US בלבד, אין חוסרים | ✅ |
| Category / Age rating | Games, ‏4+, ‏`advertising=true` | ✅ (ראו 10) |
| IAP / Subscriptions | 0 ב-ASC. ‏UI של IAP כבוי בקוד (`iapEnabled=false`) | ✅ |
| TestFlight groups | **נוצרה "PerfectTap Internal"** (ריקה) | ✅ / 👤 בודקים |
| Beta App Review info | ריק (נדרש רק לבדיקה חיצונית) | 👤 |
| Export compliance | `usesNonExemptEncryption=false` | ✅ |
| Bundle ID / Profile | ‏`com.perfecttap.app`, ‏App Store profile פעיל עד 22.3.2027 | ✅ |
| Distribution certificate | ‏2 ב-ASC (עד 20.2.2027). חתימה דרך cloud signing עם מפתח Admin | ✅ |
| שאלון App Privacy | **לא נגיש ב-API** | 🔒 / 👤 |
| טקסט הדחייה המלא | לא נגיש ב-API. נמסר על ידיך | — |

גיבוי של הערכים הקודמים (What's New, ‏Marketing, ‏Notes) נשמר מקומית, ואפשר לשחזר.

## 2. שורש הדחייה
ההצהרה ב-App Store Connect ("Device ID — used to track") **נכונה**: ה-privacy manifest של Google Mobile Ads ‏12.14 מסמן Device ID כ-tracking.
אבל ב-1.01 ה-SDK הופעל ב-`didFinishLaunching` **בלי בקשת ATT**, בלי `NSUserTrackingUsageDescription` ובלי UMP.
הקוד כבר שלח `publisherPrivacyPersonalizationState = .disabled`, אבל זה לא מחליף בקשת הרשאה כש-SDK מוצהר כ-tracking.
**התיקון הוא מימוש ATT. לא שינוי של התווית.**

## 3. תיקוני פרטיות (ATT / UMP)
| שינוי | סטטוס |
|---|---|
| `ConsentManager`: ‏UMP → ‏ATT → החלטה. אין הפעלת SDK ואין טעינת מודעה לפני כן | ✅ unit + UI |
| Personalized ads + ‏Firebase ad signals רק ב-`.authorized`. ‏denied / restricted / notDetermined → לא מותאם | ✅ unit |
| Timeout של 8 שניות ל-UMP, כדי ש-ATT לא ייחסם ברשת איטית | ✅ unit |
| ניסיון חוזר אם iOS לא הציג את הבקשה כי האפליקציה לא הייתה active | ✅ unit |
| שינוי בהגדרות iOS או ביטול הסכמה ב-UMP → מוחל מחדש | ✅ unit |
| Settings → Privacy: ‏Ad Tracking (סטטוס + מעבר ל-iOS Settings), ‏Privacy Choices (UMP, איפה שנדרש) | ✅ UI |
| `NSUserTrackingUsageDescription` | ✅ ב-archive |
| Firebase consent defaults: ‏ad_storage / ad_user_data / ad_personalization = denied עד אישור ATT | ✅ ב-archive |
| `PrivacyInfo.xcprivacy`: ‏`NSPrivacyTracking=true` + ‏DeviceID, ‏AdvertisingData, ‏ProductInteraction, ‏UserID, ‏GameplayContent, ‏EmailAddress | ✅ |
| מדיניות פרטיות (אתר + טקסט באפליקציה): ‏ATT, ‏UMP, "לא מוכרים מידע" | ✅ (באתר אחרי merge) |
| בקשת ATT ב-iPad Air 11-inch (M3) ‏(iOS 26, עברית): מופיעה בהפעלה ראשונה; Allow / Deny / רק פעם אחת | ✅ UI (סימולטור) |
| טופס UMP באזור EEA | 🧪 לא נבדק. דורש הודעת GDPR ב-AdMob (👤) ומכשיר/VPN באזור EEA |
| ATT במכשיר אמיתי מ-TestFlight | 🧪 לא נבדק |

## 4. בדיקות
| בדיקה | תוצאה |
|---|---|
| Unit ‏(iPhone 17 Pro) | **52/52** (כולל 13 consent) ✅ |
| UI ‏ATT ‏(iPad Air 11 M3) | **3/3** ✅ |
| UI כל 14 המצבים ‏(iPad Air 11 M3) | **14/14 PASS** ✅ |
| Supabase pgTAP (מקומי) | **70/70** ✅ |
| Supabase E2E (מקומי): דו-קרבות realtime, חברים/הזמנות, legacy claim, rate limit | **8/8** ✅ |
| Release archive ‏(unsigned) | ✅ ‏1.1.0 (2), ‏iPhone+iPad, ‏Supabase Frankfurt, ‏UMP מוטמע |
| Signed IPA export | ✅ ‏1.1.0 (2), ‏Apple Distribution (cloud signing, מפתח Admin) |
| gitleaks (tree + history) | אין דליפות ✅ |
| AdMob אמיתי (revive, interstitial) | 🧪 בדיקה ידנית ב-TestFlight. ‏XCUITest לא יכול לסגור מודעה אמיתית |
| CI ‏(GitHub) | נוסף job ‏iOS unit tests. התוצאה ב-PR |

בדיקות ה-UI יצרו שחקני בדיקה אנונימיים ב-Supabase cloud ‏(`qa_runtime_*`, ‏`qa_att_*`). צריך למחוק אותם (👤, דורש service key / Dashboard).

## 5. חסמים להגשה
1. ✅ **חתימה להפצה (12.11, באישור):** ‏`fastlane build` עם מפתח ה-Admin יצר IPA חתום **1.1.0 (2)**
   (‏Apple Distribution: K88C7DPG4C, ‏App Store profile, ‏`get-task-allow=false`, ‏`codesign --verify` עבר).
   החתימה נעשתה ב-cloud signing. **לא נוצרו ולא שונו תעודות או profiles בחשבון** (השוואה לפני ואחרי).
   לא הועלה.
2. 👤 **שאלון App Privacy:** לפי `docs/APP_PRIVACY_DECLARATION.he.md`, ואז Publish.
3. 👤 **הודעת GDPR ב-AdMob:** ‏AdMob → Privacy & messaging → European regulations → יצירה ופרסום (חינם). בלעדיה UMP לא מציג טופס ב-EEA.
4. 👤 **העלאת build 2 ל-TestFlight** (`PT_CONFIRM=yes fastlane beta` או Organizer), ובדיקת ATT ומודעות במכשיר.
5. 👤 חיבור build 2 לגרסה 1.1.0, תשובה ב-Resolution Center (`docs/APP_REVIEW_RESPONSE_5.1.2.md`), הגשה.

## 6. עלויות
**‎$0 בחודש.** ‏Supabase Free, ‏Firebase Spark, ‏GitHub Pages/Actions (repo ציבורי), ‏UMP ו-AdMob חינם.
המנוי הקיים ל-Apple Developer Program ($99 לשנה) לא השתנה.
