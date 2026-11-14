# PerfectTap 1.1.0 (3) — מוכנות להגשה חוזרת (14.11.2026)

מקרא: ✅ הושלם ונבדק · 🧪 מומש, לא נבדק במכשיר אמיתי · 👤 דורש אישור או פעולה שלך

## Release candidate
| | |
|---|---|
| Build | **1.1.0 (3)**, נבנה מ-`main` ‏`1f279d8`. ‏build id ‏`a4d8ec4a…`. ‏`VALID`, לא פג תוקף, ‏min iOS 16.0 |
| מחובר להגשה | ✅ **build 3 הוא ה-build שמחובר לגרסה 1.1.0** (נקרא מה-API, 14.11.2026). ה-IPA המקומי הוא 1.1.0 (3), ובבינארי אין מחרוזות debug |
| חתימה | Apple Distribution, ‏cloud signing עם מפתח Admin. ‏`get-task-allow=false` |
| TestFlight | פנימי `IN_BETA_TESTING`. חיצוני לא נשלח (`READY_FOR_BETA_SUBMISSION`) |
| `main` | ‏PR 6 מוזג (merge commit ‏`0c52758`). ‏CI ירוק: secret-scan, ‏backend, ‏ios-unit-tests |
| שינויים אחרי build 3 | רק Fastlane, תיעוד, דגל DEBUG ‏`-PTUMPDebugEEA` ותיקון סקריפט הייבוא. **אף אחד מהם לא מצדיק build חדש** |

## דגל ה-EEA לבדיקות: לא משפיע על Release ✅
- הקוד עטוף ב-`#if DEBUG` (`ConsentManager.swift`, ‏`LiveConsentEnvironment.updateConsentInfo`).
- ב-Release ‏`SWIFT_ACTIVE_COMPILATION_CONDITIONS` ריק. ב-Debug הוא `DEBUG` (‏`xcodebuild -showBuildSettings`).
- נבנה Release מהקוד הנוכחי (`main`): **0** מופעים של `PTUMPDebugEEA` ו-`PTUMPReset` בבינארי.
- build 3 נבנה לפני שהדגל נוסף. גם בו: 0 מופעים.

## App Store Connect (נקרא ב-14.11.2026)
| שדה | ערך | |
|---|---|---|
| גרסה | 1.1.0 ‏`PREPARE_FOR_SUBMISSION`. ‏1.0 ‏`READY_FOR_SALE` | ✅ |
| Release | **MANUAL**. ‏Phased release ‏`INACTIVE` (מתחיל רק כשתלחץ Release) | ✅ |
| Export compliance | `usesNonExemptEncryption=false` ב-build 3 (וגם ב-Info.plist) | ✅ |
| Review notes | **עודכנו היום:** נוספה שורה על הסדר באירופה (טופס Google ואחריו ATT) | ✅ |
| Review contact | מלא. ‏demo account לא נדרש | ✅ |
| What's New | פרטיות, שרתי EU, מעבר חשבון אוטומטי, יציבות | ✅ |
| Description / Keywords / Promo | ‏659 / 100 / 76 תווים | ✅ |
| URLs | Privacy, ‏Support ו-Marketing ב-`oyaholding.github.io/PerfectTap/` | ✅ |
| צילומי מסך | iPhone 6.5" ‏×4, ‏iPad 13" ‏×4, ‏iPad 11" ‏×4. כולם `COMPLETE` | ✅ |
| Age rating | ‏4+. ‏UGC=No, ‏Messaging=No, ‏Advertising=Yes. ראו `AGE_RATING_UGC_AUDIT.he.md` | ✅ ללא שינוי |
| App Privacy | פורסם. דף החנות הציבורי תואם (Track: Identifiers. ‏Not Linked: Diagnostics) | ✅ |
| AdMob GDPR | "פורסמה", פעילה, רק ל-PerfectTap | ✅ |
| Review submission | `016ce0ae…` ‏`UNRESOLVED_ISSUES`, ‏item ‏`REJECTED` → **Reply + Resubmit** באותה הגשה | 👤 |
| מחיר / טריטוריות | לא שונו | ✅ |

## מכשיר אמיתי: build 3 (‏10–15 דקות) 👤
**בדיקות סימולטור לא נספרות כאן.** ‏build 2 נבדק אצלך. ‏build 3 שונה ממנו ב-analytics ב-EEA ובהסרת FCM, לכן צריך בדיקה קצרה.

| # | פעולה | צפוי | ✓ |
|---|---|---|---|
| 1 | TestFlight → PerfectTap → לוודא שמותקן **1.1.0 (3)** | מספר ה-build הוא 3 | ☐ |
| 2 | למחוק את האפליקציה ולהתקין מחדש. ב-iOS: Settings → Privacy → Tracking → "Allow Apps to Request to Track" **פעיל** | — | ☐ |
| 3 | לפתוח | בקשת ATT מופיעה **פעם אחת**, תוך כמה שניות, לפני כל פרסומת | ☐ |
| 4 | Ask App Not to Track → לבחור שם → לשחק 3–4 סיבובים | המשחק עובד, ומופיעה פרסומת בין סיבובים | ☐ |
| 5 | Settings (במשחק) → Privacy | "Ad Tracking: Not allowed". ‏Privacy Choices **לא** מופיע (מחוץ ל-EEA) | ☐ |
| 6 | לסגור לגמרי ולפתוח שוב | אין בקשת ATT שנייה | ☐ |
| 7 | rewarded (revive) | הפרסומת מוצגת, וה-revive מתקבל רק אחרי צפייה מלאה | ☐ |
| 8 | Leaderboard, ‏Friends, דו-קרב (אם יש מכשיר שני) | נטען, ללא שגיאה | ☐ |
| 9 | מצב טיסה → לפתוח את האפליקציה | המשחק נפתח תוך ~8 שניות לכל היותר ומשחק offline | ☐ |
| 10 | (אופציונלי) להתקין מחדש ולבחור **Allow** | Settings → Privacy מציג "Allowed" | ☐ |
| 11 | (אופציונלי) Delete Account | נמחק. בהפעלה הבאה נוצר שחקן חדש | ☐ |

אם 1–9 עברו, המשפט "on a real iPhone via TestFlight" בתשובה ל-Apple נכון, ואפשר לשלוח.

## הגירה מ-Firebase ל-Supabase
- נבדקה התוכנית (`RELEASE_PLAN_1.1.0.he.md` §9ב).
- **נמצא ותוקן באג:** ‏`import-legacy.sh` היה נכשל בייבוא השני (`raw_docs_pkey`). עכשיו הוא עושה upsert בטרנזקציה אחת. נבדק ב-stack המקומי בלבד.
- **פער ידוע:** ה-claim קורא מה-snapshot. לכן מומלץ לייבא ביום השחרור, ביום 3 וביום 7.
- ייבוא לענן = כתיבה ל-DB. דורש את אישורך ואת סיסמת ה-DB. **לא בוצע.**

## אבטחה
- רק מפתח Admin ‏`V37FB6BY9N`, ב-`~/.config/perfecttap/apple/` (הרשאות 700/600). ‏`UNPCX236BH` בוטל.
- gitleaks: אין דליפות.

## עלויות
**‎$0 בחודש.** לא הופעל אף שירות בתשלום.
