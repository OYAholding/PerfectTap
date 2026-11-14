# PerfectTap 1.1.0 (3) — מוכנות להגשה (13.11.2026)

מקרא: ✅ הושלם ונבדק · 🧪 מומש, לא נבדק במכשיר אמיתי · 🔒 חסום בהרשאות · 👤 דורש אישור/פעולת בעלים

## Release candidate
| | |
|---|---|
| Build | **1.1.0 (3)**, נבנה מ-`main` ‏`1f279d8` (העץ זהה לראש PR 5 ‏`4f9a9cd`, ‏CI ירוק) |
| חתימה | Apple Distribution ‏(K88C7DPG4C), ‏cloud signing עם מפתח Admin. ‏`codesign --verify` עבר, ‏`get-task-allow=false` |
| תוכן ה-IPA | ‏Supabase ‏`pgvtaotdyspwnpqtxpju` (פרנקפורט), ‏ATT string, ‏UMP, ‏consent defaults כבויים, ‏`ITSAppUsesNonExemptEncryption=false`, **בלי** FirebaseMessaging, **בלי** מזהי מודעות בדיקה |
| TestFlight | פנימי `IN_BETA_TESTING` ("PerfectTap Internal"). חיצוני **לא נשלח** |
| App Store Connect | build 3 **מחובר** לגרסה 1.1.0 (`PREPARE_FOR_SUBMISSION`) |
| Build 2 | נבדק במכשיר אמיתי על ידי הבעלים, ונשאר ב-TestFlight. ‏build 3 = ‏build 2 + הקשחת analytics ב-EEA + הסרת FCM |

## הגדרות App Store Connect (בוצעו ונבדקו)
| שדה | ערך |
|---|---|
| גרסה | 1.1.0 (שונה מ-1.01) |
| Release | **Manual**: אישור של Apple לא משחרר אוטומטית |
| Phased release | 7 ימים, `INACTIVE` עד שחרור ידני |
| Privacy / Support / Marketing URL | `…/PerfectTap/`, ‏`…/support.html`, ‏`…/PerfectTap/` (כולם 200) |
| כתובות 1.0 החיה (נעולות) | מפנות דרך `perfecttap-pages` (200) |
| What's New / Review Notes | מעודכנים: פרטיות, שרתי EU, מעבר חשבון, ‏ATT |
| Review contact | מלא. אין צורך ב-demo account |
| Export compliance | `false` (HTTPS בלבד) |
| Age rating | ‏4+, ‏`advertising=true`. ‏👤 שאלה פתוחה: שמות משתמש גלויים (UGC) |
| Categories | Games → Casual |
| צילומי מסך | ‏iPhone 6.5", ‏iPad 13", ‏iPad 11" (×4 כל אחד). en-US בלבד |
| מחיר / טריטוריות / IAP | לא שונו. אין IAP |
| Review submission | `UNRESOLVED_ISSUES` על 1.1.0 → **Reply + Resubmit** באותה הגשה |

## פרטיות (5.1.2(i))
- **שורש הבעיה:** Google Mobile Ads מסמן Device ID כ-tracking, ו-1.01 הפעיל מודעות בלי ATT. התווית נכונה, והתיקון בקוד.
- **בקוד:** UMP → ‏ATT → מודעות. אין SDK ואין בקשת מודעה לפני כן. התאמה אישית רק ב-ATT authorized.
- **Analytics:** כבוי עד להחלטה. ב-EEA/UK/CH רק עם TCF Purpose 1. ‏ad signals רק מחוץ לאזורים האלה ועם ATT.
- **בדיקות:**
  - Unit ‏56/56 (17 consent).
  - ATT UI על iPad Air 11 M3 ‏3/3 (פעמיים, גם אחרי השינוי האחרון).
  - 14/14 מצבי משחק על iPad.
  - Supabase: ‏pgTAP 70/70, ‏E2E 8/8.
  - בדיקת מכשיר אמיתי של הבעלים (build 2).
- 🧪 **לא נבדק:** טופס UMP בפועל באזור EEA (דורש הודעת GDPR ב-AdMob ומכשיר/VPN ב-EEA), ו-build 3 במכשיר אמיתי.
- 👤 **שאלון App Privacy:** ‏`docs/APP_PRIVACY_DECLARATION.he.md`. דורש Publish שלך.

## אבטחה
- מפתח Admin `V37FB6BY9N` בלבד, ב-`~/.config/perfecttap/apple/` ‏(700/600).
- `UNPCX236BH` בוטל (‏401 אומת), והקבצים שלו נמחקו.
- gitleaks: אין דליפות.
- `import-legacy.sh`: הדוגמה הצביעה על פרויקט סינגפור הישן. תוקן, וה-guard מסרב לו.

## עלויות
**‎$0 בחודש.** ‏Supabase Free, ‏Firebase Spark, ‏GitHub (repo ציבורי), ‏AdMob/UMP חינם. ‏Apple Developer ($99 לשנה) קיים.
