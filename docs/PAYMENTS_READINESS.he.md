# מוכנות לתשלומים אמיתיים — PerfectTap 1.2.0

**תאריך:** 22.11.2026 · **מצב:** הקוד מוכן ונבדק מקומית. **שום מוצר אמיתי לא הופעל ושום לקוח לא חויב.**

## ההחלטה: StoreKit 2 בלבד

- פריטים קוסמטיים שנמכרים בתוך האפליקציה חייבים לעבור דרך IAP של אפל (הנחיה 3.1.1). ראו [COMPLIANCE.md](research/COMPLIANCE.md).
- **Lemon Squeezy לא נבחר.** ההרשמה נסגרה ב־16.11.2026, ועיבוד התשלומים מסתיים ב־31.3.2027 בלי הארכה.
- אם בעתיד תיבנה חנות אינטרנט (ארה"ב בלבד, קישור החוצה), החלופה המומלצת היא Stripe Managed Payments, ורק אחרי אישור של Stripe.

## מה בנוי בקוד (ענף `release/1.2.0`)

| רכיב | קובץ | מה הוא עושה |
|---|---|---|
| מתגים | `ios/PerfectTap/Utils/FeatureFlags.swift` | `iapEnabled = false`, `serverPurchaseVerification = false`. כל עוד הם כבויים, אי אפשר לקנות בכסף אמיתי |
| מסירה פעם אחת בדיוק | `Services/EntitlementLedger.swift` | כל עסקה מזוכה פעם אחת לפי מזהה. החזר כספי מבטל את מה שניתן. מטבעות לא יורדים מתחת לאפס. עסקאות שזוכו ב־1.1.x נשמרות ולא יזוכו שוב |
| צינור הרכישה | `Services/PurchaseManager.swift` | אימות StoreKit על המכשיר, ואז אימות שרת (כשמופעל), ואז זיכוי, ורק אז `finish()`. עסקאות שלא הסתיימו נמסרות בהפעלה הבאה (`Transaction.unfinished`). כל רכישה נקשרת לשחקן עם `appAccountToken`. יש שחזור רכישות |
| שני המתגים יחד | `FeatureFlags.realMoneyPurchasesEnabled` | רכישות בכסף אמיתי זמינות רק כששני המתגים דולקים. בלי אימות שרת, השרת היה מוריד סקינים ששולמו |
| סקינים פרימיום | `Models/ShopItem.swift`, `Utils/GameConfig.swift` | Neon Pulse, ‏Liquid Chrome, ‏Glitch Mode, ‏Cosmic Gold. אי אפשר לקנות אותם במטבעות, והם מוסתרים בחנות עד שהמתג מופעל |
| הגדרת StoreKit מקומית | `ios/PerfectTap/StoreKit/PerfectTap.storekit` | כל 9 המוצרים עם כסף מדומה, לבדיקה בסימולטור (סכמת PerfectTap › Run) |
| ספר עסקאות בשרת | `supabase/migrations/20261122120000_purchase_ledger_and_economy_guard.sql` | `purchase_ledger` (מזהה עסקה ייחודי), `economy` (no_ads, סקינים, מטבעות IAP שממתינים לסנכרון), יומן אירועים |
| הקשחת `save_profile` | אותה מיגרציה | הלקוח כבר לא יכול: להפעיל no_ads, להוסיף סקין שלא שולם, להפעיל season premium בלי 50 פרסומות, או לקפוץ במטבעות מעבר לתקרה נדיבה שתלויה בזמן. חריגה נחתכת ונרשמת ביומן, והשמירה לא נכשלת |
| אימות עסקה | `supabase/functions/verify-purchase` | מאמת את ה־JWS מול שרשרת התעודות של אפל (App Store Server Library 3.1.0), בודק bundle ו־appAccountToken, ורושם בספר |
| החזרים | `supabase/functions/app-store-notifications` | App Store Server Notifications V2: ‏REFUND/REVOKE מבטלים את הזכאות בספר |

### שמירת נתוני שחקנים קיימים
- המיגרציה **לא משנה אף ערך קיים**. היא יוצרת שורת `economy` לכל שחקן לפי דגל ה־no_ads הנוכחי שלו, וזהו.
- מטבעות, פריטים והתקדמות נשארים כפי שהם.
- נתיב התביעה של חשבונות Firebase הישנים (`save_profile_for` ישירות) לא עובר דרך המגבלה החדשה, כך שייבוא יתרות ישנות לא ייחתך.

## בדיקות שהורצו

| בדיקה | תוצאה |
|---|---|
| בדיקות יחידה ב־iOS (`xcodebuild test`, סכמת PerfectTap) | 91 בדיקות: ‏90 עברו, 0 נכשלו, 1 דולגה (ראו למטה) |
| בדיקות מסד נתונים pgTAP (`supabase test db --local`) | 104/104 עברו (70 קיימות ו־34 חדשות של ספר העסקאות, כולל שימוש חוזר בעסקה של שחקן אחר, החזר לפני רישום, ועקיפת התקרה בשמירות חוזרות) |
| בדיקות Deno ללוגיקת האימות | 6/6 עברו, ושתי הפונקציות עוברות `deno check` |

**הבדיקה שדולגה:** טעינת המוצרים דרך `SKTestSession`. סוכן ה־StoreKit בסימולטור החזיר `SKInternalErrorDomain 3` בהרצה משורת הפקודה. הבדיקה מסומנת "דולגה" ולא "עברה". קובץ ההגדרה עצמו נבדק בבדיקה נפרדת: כל 9 המוצרים קיימים, עם הסוג הנכון. כדאי להריץ את הבדיקה פעם אחת מתוך Xcode.

**לא נבדק:**
- רכישה אמיתית ב־Sandbox או ב־TestFlight. אין עדיין מוצרים ב־App Store Connect.
- אימות JWS אמיתי מול תעודות אפל. נדרשת עסקה חתומה.
- קבלת התראה אמיתית מאפל.
- המיגרציה הורצה רק על ה־DB המקומי: האובייקטים שלה נמחקו והקובץ הורץ מחדש כולו. לא הורץ `db reset` מלא, כדי לא למחוק נתונים מקומיים אחרים.

## צ'קליסט לבעלים, לפני שמפעילים כסף אמיתי

### App Store Connect (רק אתה, בממשק של אפל)
1. **Agreements, Tax, and Banking:** לוודא ש־**Paid Apps Agreement** פעיל, ושפרטי הבנק והמס הושלמו. *לא נגעתי ולא אגע בהגדרות האלה.*
2. ליצור את מוצרי ה־IAP עם אותם מזהים בדיוק:
   - `com.perfecttap.coins.500` / `.1200` / `.3000` / `.8000` — מסוג Consumable
   - `com.perfecttap.removeads` — מסוג Non-Consumable
   - `com.perfecttap.skin.neonpulse`, `.liquidchrome`, `.glitchmode`, `.cosmicgold` — מסוג Non-Consumable
3. לקבוע מחירים. המחירים בקובץ ה־`.storekit` (0.99–9.99$, סקין 1.99$) הם לבדיקה בלבד. ההחלטה שלך.
4. App Information › App Store Server Notifications:
   - Version 2
   - כתובת: `https://<project>.supabase.co/functions/v1/app-store-notifications`
   - כדאי להגדיר קודם את כתובת ה־Sandbox.
5. לכל מוצר: צילום מסך לבדיקה, ותיאור שמבהיר שזה קוסמטי בלבד.

### Supabase (דורש את אישורך המפורש, ולא בוצע)
1. להריץ את המיגרציה על פרויקט הפרודקשן (`supabase db push`), אחרי גיבוי.
2. להגדיר secrets לפונקציות:
   - `APPLE_ROOT_CAS_B64`: תעודות השורש מ־apple.com/certificateauthority, בקידוד base64 ומופרדות בפסיקים
   - `APPLE_ENVIRONMENT`: ‏`Sandbox`, ואחר כך `Production`
   - `APPLE_APP_APPLE_ID`: המזהה המספרי של האפליקציה
3. לפרוס את `verify-purchase` ואת `app-store-notifications`.

### באפליקציה (build חדש, דורש אישור)
1. `FeatureFlags.serverPurchaseVerification = true`, ואז בדיקת Sandbox: רכישה, רכישה כפולה, החזר דרך "Request a Refund" בסביבת הבדיקה, Ask to Buy, ניתוק רשת באמצע.
2. רק אחרי כל זה: `FeatureFlags.iapEnabled = true`, ‏build ל־TestFlight, ורק אחר כך App Review.

## סיכונים פתוחים
- **הלקוח עדיין סומך על עצמו מקומית.** במכשיר פרוץ אפשר לערוך את UserDefaults. השרת מגביל את הנזק לנתונים המשותפים: לוח תוצאות, זכאויות וגיבוי, אבל לא לעותק המקומי.
- **רווח מטבעות ממשחק עדיין מחושב בלקוח.** התקרה בשרת: תקציב מתגלגל של 30,000 לשעה (שמירות חוזרות לא ממלאות אותו מחדש), ועוד 20,000 לכל שעה אופליין מאז השמירה הקודמת, עד 500,000. היא חוסמת קפיצות לא סבירות, אבל זו לא כלכלה סמכותית מלאה. השלב הבא: RPC בשרת לכל מקור הכנסה (משחק עם session מאומת, משימות, גלגל).
- **החזר על מטבעות שכבר נוצלו:** היתרה יורדת עד אפס, ולא לתוך מינוס. זו מדיניות שצריך לאשר.
