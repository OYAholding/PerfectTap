# PerfectTap — הצהרת App Privacy (שאלון ב-App Store Connect)

> **סטטוס:** טיוטה לאישור הבעלים. השאלון **לא עודכן**: ה-API לא תומך בו, וממשק הדפדפן דורש התחברות שלך.
> נבדק ב-13.11.2026 מול: התווית החיה ב-App Store, קוד 1.0 ו-1.1.0, ‏`PrivacyInfo.xcprivacy`,
> ה-manifests של Google Mobile Ads ‏12.14 ו-UMP ‏3.1, Firebase Analytics ו-Supabase.

## איפה ממלאים
App Store Connect → PerfectTap → **App Privacy** → Edit. השאלון הוא **לכל האפליקציה**, לא לגרסה מסוימת.
הוא מתעדכן בחנות מיד עם **Publish**, ולכן הוא חייב להיות נכון גם ל-1.0 החיה וגם ל-1.1.0.

## מה מופיע היום בחנות (1.0, נקרא מהדף הציבורי)
- **Data Used to Track You:** Identifiers
- **Data Linked to You:** Contact Info, Identifiers, Usage Data
- **חסר**, גם ל-1.0 (שכבר כוללת AdMob ו-Firebase): Location, User Content, Diagnostics.

## האם האפליקציה מבצעת Tracking?
**כן, ב-1.1.0 רק אחרי אישור ATT.** כש-ATT מאושר, ‏Google Mobile Ads משתמש ב-IDFA למודעות מותאמות ולמדידה בין אפליקציות.
ה-manifest של Google מסמן את Device ID כ-tracking. התווית "Identifiers — Used to Track" **נכונה ונשארת**.
ב-1.0 לא הייתה בקשת ATT, ולכן iOS לא חשף שם את ה-IDFA (אפסים). זו בדיוק הסתירה שבגללה Apple דחתה את 1.01.

## התשובות הסופיות
| קטגוריה → סוג | Purposes | Linked | Tracking | מקור |
|---|---|---|---|---|
| Identifiers → **Device ID** | Third-Party Advertising, Analytics | Yes | **Yes** | IDFA אחרי ATT, ‏IDFV. ‏AdMob ו-Firebase Analytics |
| Identifiers → **User ID** | App Functionality | Yes | No | מזהה חשבון ב-Supabase (ב-1.0: ‏Firebase UID) |
| Contact Info → **Email Address** | App Functionality | Yes | No | חשבונות אימייל ישנים (Firebase) שעוברים ב-claim. ‏Cloud Backup (כבוי כרגע) |
| User Content → **Gameplay Content** | App Functionality | Yes | No | שם משתמש, ניקוד, חברים, דו-קרבות, לוחות תוצאות |
| Location → **Coarse Location** | Third-Party Advertising, Analytics, App Functionality | Yes | No | נגזר מ-IP ב-AdMob. ‏UMP קובע לפיו אזור (App Functionality) |
| Usage Data → **Product Interaction** | Analytics, Third-Party Advertising, App Functionality | Yes | No | אירועי Firebase Analytics, ‏AdMob ו-UMP |
| Usage Data → **Advertising Data** | Third-Party Advertising, Analytics | Yes | No | חשיפות ולחיצות על מודעות (AdMob) |
| Diagnostics → **Crash Data** | Analytics | No | No | AdMob |
| Diagnostics → **Performance Data** | Analytics, Third-Party Advertising, App Functionality | No | No | AdMob ו-UMP |
| Diagnostics → **Other Diagnostic Data** | Analytics, Third-Party Advertising | No | No | AdMob |

**לא לסמן:**
- **Purchases:** אין IAP ב-App Store Connect, וה-UI כבוי.
- **Name:** הכינוי במשחק נכנס תחת Gameplay Content.
- **Precise Location**, ‏**Health**, ‏**Financial**, ‏**Contacts**, ‏**Photos**, ‏**Audio**, ‏**Browsing / Search History**, ‏**Sensitive Info**: לא נאספים.
- **Push / Messaging:** ‏FirebaseMessaging הוסר ב-1.1.0. ב-1.0 הוא היה מקושר בלי הרשאת push, ולא מצאתי בו איסוף מידע שדורש הצהרה נפרדת.

## למה "Linked = Yes" במידע של Google
Apple מאחדת את כל ה-privacy manifests שבתוך ה-build. ה-manifest של Google Mobile Ads מסמן Device ID, ‏Coarse Location, ‏Product Interaction ו-Advertising Data כ-linked.
הצהרה שמרנית (Linked) לא תיצור סתירה מול ה-privacy report של Apple. הצהרה מקלה עלולה.

## אחרי Publish (בדיקה)
1. בדף החנות: "Data Used to Track You" = **Identifiers** בלבד.
2. "Data Linked to You": ‏Contact Info, ‏Identifiers, ‏Location, ‏User Content, ‏Usage Data.
3. "Data Not Linked to You": ‏Diagnostics.
4. Privacy Policy URL: ‏`https://oyaholding.github.io/PerfectTap/` (‏HTTP 200).
