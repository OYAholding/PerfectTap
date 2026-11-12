# PerfectTap — בדיקת App Store Connect API (12.11.2026)

כל הבדיקות היו **קריאה בלבד** (GET). לא בוצע שום שינוי ב-App Store Connect, לא הועלה build ולא נשלח דבר ל-review.
נבדקה רק האפליקציה PerfectTap (App ID `6760975737`). שום אפליקציה אחרת בחשבון לא נקראה.

## 1. סטטוס חיבור API
**מחובר.** מפתח Team API ‏(App Manager), JWT ‏ES256 נוצר מקובץ `.p8` מקומי (`~/.config/perfecttap/apple/`, הרשאות `600`, מחוץ לריפו).
כל 20 נקודות הקצה שנבדקו החזירו HTTP 200. ה-JWT ותוכן המפתח לא הודפסו ולא נשמרו.

## 2. הרשאות שאושרו (קריאה)
| משאב | סטטוס |
|---|---|
| App, appInfos, ‏localizations, ‏age rating, ‏categories | ✅ |
| App Store versions, ‏localizations, ‏review detail, ‏screenshot sets | ✅ |
| Builds, ‏preReleaseVersions, ‏buildBetaDetails | ✅ |
| TestFlight: ‏betaGroups, ‏betaTesters, ‏betaAppReviewDetail, ‏betaAppLocalizations, ‏betaLicenseAgreement | ✅ |
| reviewSubmissions + items | ✅ |
| Pricing, ‏availability | ✅ |

הרשאות כתיבה **לא נבדקו** בכוונה. לפי Apple, ‏App Manager מספיק להעלאת builds, ‏TestFlight ועדכון metadata.
**לא זמין ב-API בכלל:** טקסט הדחייה של App Review ושאלון App Privacy (Privacy "nutrition labels").

## 3. גרסאות App Store
| גרסה | מצב | Build מחובר | הערות |
|---|---|---|---|
| 1.0 | `READY_FOR_SALE` | ‏1.0.0 (1) | הגרסה החיה |
| 1.01 | `PREPARE_FOR_SUBMISSION` | ‏1.0.1 (1) | נדחתה, חזרה לעריכה |

- Review submission מ-16.4.2026 ‏19:43 UTC: ‏`UNRESOLVED_ISSUES`, ‏item ‏`REJECTED` (גרסה 1.01).
- Build ‏1.0.2 (1) הועלה ב-16.4.2026 ואינו מחובר לאף גרסה כרגע.
- **אי-התאמה בשם הגרסה:** ב-App Store Connect הגרסה היא `1.01`, וה-builds הם `1.0.1` / `1.0.2`. ענף השחרור הנוכחי בונה `1.1.0`. כדאי לשנות את 1.01 ל-1.1.0 לפני ההגשה הבאה.
- **כל ה-builds עם מספר build `1`.** ה-lane `build` מחשב את ההבא (2), וזה תואם לתוכנית 1.1.0.
- `usesNonExemptEncryption=false` מוגדר בכל ה-builds. ‏`minOsVersion` 16.0.

## 4. TestFlight
- 3 builds, **כולם פגי תוקף** (`EXPIRED`, פנימי וחיצוני).
- **אין קבוצות בודקים** (גם לא פנימית). 0 בודקים.
- Beta App Review Information ריק (איש קשר, הערות), ואין Beta App Localizations (feedback email, תיאור). הם נדרשים רק לבדיקה חיצונית.
- כדי להפיץ build חדש לבודקים פנימיים צריך ליצור קבוצה פנימית.

## 5. פרטי הדחייה
ה-API מחזיר רק את המצב (`UNRESOLVED_ISSUES` / `REJECTED`), ‏**בלי הטקסט של Apple**.
ציטוט מדויק של Guideline 5.1.2 נמצא רק ב-App Store Connect → ‏PerfectTap → ‏App Review
(submission `016ce0ae-319d-4cd1-8877-6ff36f61bad2`). זו פעולה ידנית בדפדפן.

## 6. תיקוני פרטיות נדרשים
### א. קישורים שבורים, גם בגרסה החיה (דחוף)
| שדה | ערך נוכחי | HTTP | ערך מוצע |
|---|---|---|---|
| Privacy Policy URL (App Info) | `https://oyaholding.github.io/perfecttap-pages/` | **404** | `https://oyaholding.github.io/PerfectTap/` |
| Support URL ‏(1.0 ו-1.01) | `https://oyaholding.github.io/perfecttap-pages/support.html` | **404** | `https://oyaholding.github.io/PerfectTap/support.html` |
| Marketing URL ‏(1.01) | `https://oyaholding.github.io/` | 200 | עמוד כללי של הארגון. כדאי לשנות ל-`/PerfectTap/` |

האתר הישן `perfecttap-pages` אוחד לריפו `PerfectTap`, והכתובות ב-App Store Connect לא עודכנו.
כרגע מדיניות הפרטיות של האפליקציה החיה לא נגישה.

### ב. פרסום ומעקב (הסיבה הסבירה ל-5.1.2)
- האפליקציה כוללת **Google Mobile Ads (AdMob)** ו-**Firebase Analytics**.
- **אין** `AppTrackingTransparency`, **אין** `NSUserTrackingUsageDescription` ב-Info.plist, ו**אין** מסך הסכמה (Google UMP).
- `PrivacyInfo.xcprivacy`: ‏`NSPrivacyTracking=false`, ‏Device ID ו-Product Interaction מסומנים "לא מקושרים".
- מדיניות הפרטיות כתובה "may request permission before … tracking", אבל בפועל האפליקציה לא מבקשת.

צריך לבחור דרך אחת ולהתאים אליה **ארבעה דברים**: הקוד, ‏`PrivacyInfo.xcprivacy`, שאלון App Privacy, ומדיניות הפרטיות.
- **מומלץ: מעקב עם ATT.** בקשת ATT לפני טעינת המודעות, `NSUserTrackingUsageDescription`, ‏`NSPrivacyTracking=true` + ‏`NSPrivacyTrackingDomains` של Google,
  ובשאלון App Privacy: Device ID → ‏Third-Party Advertising → ‏"Used for tracking". בנוסף **Google UMP** למשתמשי EEA/UK
  (Google דורשת CMP מאושר להצגת מודעות שם).
- **חלופה: בלי מעקב.** לסמן בשאלון שאין מעקב, ולוודא ש-AdMob מגיש מודעות לא מותאמות אישית. כאן אין מסך ATT, אבל חייבת להיות התאמה מלאה.

### ג. השלמת סוגי המידע
לפי מדיניות הפרטיות והקוד, האפליקציה אוספת גם: User ID (חשבון Supabase/אנונימי), שם משתמש ונתוני משחק (לוחות תוצאות, חברים, דו-קרבות),
אימייל (Cloud Backup), ‏push token ‏(Firebase Messaging). הם חסרים ב-`PrivacyInfo.xcprivacy`, וצריך לבדוק שהם מופיעים בשאלון App Privacy, מסומנים "Linked to user".

### ד. נקודות נוספות לבדיקה
- Age rating: ‏`userGeneratedContent=false`, ‏`messagingAndChat=false`. אם שמות משתמש גלויים לאחרים (לוחות תוצאות, חברים), כדאי לבדוק את סעיף UGC ‏(1.2).
- Privacy Choices URL לא מוגדר (אופציונלי).
- מחיקת חשבון קיימת באפליקציה (5.1.1(v)) ✅.
- ענף השחרור `release/supabase-testflight-rc` ‏(1.1.0 build 2) **עדיין בלי ATT**. כדאי לתקן לפני ה-build.

## 7. פעולות ידניות שנותרו
1. לקרוא את טקסט הדחייה המלא ב-App Review ולהעביר אותו.
2. לעדכן את שאלון App Privacy (לא זמין ב-API).
3. לאשר עדכון Privacy Policy URL ו-Support URL (אפשר דרך `metadata_push` או ידנית).
4. להחליט על מספר הגרסה (1.01 → 1.1.0).
5. ליצור קבוצת TestFlight פנימית. לבדיקה חיצונית: למלא Beta App Review Info ו-Beta localization.
6. תגובה ב-Resolution Center והגשה מחדש: רק בידיים שלך, אחרי אישור.

## 8. מוכנות לאוטומציה
| יכולת | סטטוס |
|---|---|
| חיבור API + בדיקת מצב (`asc_check`) | ✅ נבדק |
| הורדת metadata (`metadata_pull`) | ✅ נבדק (לתיקייה זמנית) |
| Build חתום מקומי (`build`) | ⚠️ מוכן, לא הורץ. חתימה אוטומטית עם מפתח ה-API (`-allowProvisioningUpdates`) |
| העלאה ל-TestFlight (`beta`) | ⚠️ מוכן, לא הורץ. דורש `PT_CONFIRM=yes` |
| עדכון metadata (`metadata_push`) | ⚠️ מוכן, לא הורץ. דורש `PT_CONFIRM=yes` |
| שליחה ל-review / שחרור | ❌ בכוונה לא קיים |

הוראות שימוש: `fastlane/README.he.md`.
