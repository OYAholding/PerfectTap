# מוכנות לתשלומים אמיתיים — PerfectTap 1.2.0

**תאריך:** 25.11.2026 · **מצב:** ההטמעה מוכנה מקומית, אבל השחרור עדיין חסום. **לא בוצעה פריסה לפרודקשן, לא נוצרו מוצרי IAP ב-App Store Connect ולא הופעלה רכישה בכסף אמיתי.**

## ההחלטה

StoreKit 2 הוא מסלול התשלום היחיד לפריטים דיגיטליים באפליקציה. המשחק ו-Cloud Backup נשארים זמינים בלי הרשמה כפויה:

- אורח אנונימי רשאי לקנות `Remove Ads` וסקינים. השחזור מתבסס על היסטוריית StoreKit החתומה של Apple, ולכן אינו תלוי באימייל או בחשבון PerfectTap.
- חבילות מטבעות הן consumable ואינן נכללות ב-StoreKit `currentEntitlements`. לכן הן חסומות לאורח עד קישור חד-פעמי לחשבון בר-שחזור, בעדיפות ל-Sign in with Apple ובחלופה חשבון אימייל מאומת.
- `appAccountToken` הוא UUID של חשבון Supabase. עסקת מטבעות עם token חסר/שונה אינה מזוכה ואינה מסתיימת, כדי שניתן יהיה לנסות שוב אחרי כניסה לחשבון הנכון. עסקת non-consumable מאומתת יכולה להחזיר הרשאה מקומית בלבד, בלי להעביר בעלות בשרת ובלי ליצור זיכוי כפול.

## מה הוטמע

| רכיב | מצב נוכחי |
|---|---|
| מתגי הפעלה | שתי שכבות שנכשלות סגור: (1) תקרת יכולת בזמן build מקובצי `Config/Monetization.*.xcconfig` — `Debug` ו-`Release` כבויים לגמרי, `Debug-StoreKit` לבדיקה מקומית בלבד, `Release-IAP` מותר למכור; (2) מתג שרת לכל סביבת StoreKit (Sandbox / Production) דרך `get_iap_sales_status`, שסוגר מכירה אם אינו זמין. מסירה ושחזור אינם תלויים במתגים. פירוט: `docs/MONETIZATION_ACTIVATION_STRATEGY.md` |
| StoreKit 2 | טעינת מוצרים, רכישה עם `appAccountToken`, listener שמחובר כבר בהפעלה, סריקת `Transaction.unfinished`, בדיקת bundle/מוצר/סוג מוצר, שחזור לאורחים, reconcile של זכאויות והחזרים, refund reversal, וריטריי מדורג לאימות שרת. מטבעות מסתיימים רק אחרי אישור שרת; non-consumable נפתח מהיסטוריית Apple גם כשהשרת לא זמין |
| זהות ושחזור | Sign in with Apple עם nonce, קישור identity לחשבון האנונימי הקיים ושימור UID/נתונים; אם ה-Apple identity כבר קיים, כניסה לחשבון הקיים ומיזוג פרופיל שמרני |
| מסירה מקומית | ledger v2 שומר מוצר לכל transaction, מונע זיכוי כפול, תומך בכמה עסקאות פעילות לאותו non-consumable ושומר מזהי 1.1.x כסמני dedupe קבועים |
| שרת | ledger רכישות וכלכלה סמכותית ב-Postgres, config/catalog שמתחילים disabled, reconciliation ליתרות legacy, אימות JWS ב-Production וב-Sandbox ו-App Store Server Notifications V2 |
| Edge Functions | שלוש פונקציות החשבון/רכישה עברו ל-`Deno.serve` עם אימות bearer משותף; אין תלות ב-`@supabase/server` |
| החזרים | `REFUND`, `REVOKE` ו-`REFUND_REVERSED`, עם UUID dedupe, סדר לפי signed date ויומן audit |
| Leaderboard | ה-RPC הציבורי מחזיר רק שורות leaderboard שאומתו בשרת; אין fallback הנשלט על ידי הלקוח |
| פרטיות | Privacy Manifest והצהרת App Privacy כוללים Purchase History לצורך App Functionality |
| הכנת IAP | manifest מקומי לתשעת המוצרים, מחירים מוצעים, metadata, review notes, בדיקת ASC read-only ו-lane מקומי להכנה בלבד |
| פריסה | Supabase CLI נעול ל-`2.119.0`; פריסת רכישות דורשת `--apply-purchases` וגם `PT_CONFIRM_PRODUCTION=yes`. SQL containment קיים לביטול מכירות בלי למחוק ledger |

## הגנות הפעלה

| שכבה | מקור | ברירת מחדל |
|---|---|---|
| תקרת build | `PT_IAP_CATALOG_ENABLED`, `PT_IAP_SERVER_VERIFICATION_ENABLED`, `PT_IAP_COIN_PACKS_ENABLED`, `PT_IAP_REMOVE_ADS_ENABLED`, `PT_IAP_PREMIUM_SKINS_ENABLED` מתוך xcconfig | `NO` ב-`Debug` וב-`Release`; `YES` רק ב-`Release-IAP` (וב-`Debug-StoreKit` מול קובץ StoreKit מקומי בלבד) |
| מתג שרת | `private.iap_sales_control` לכל סביבה + `private.iap_products.enabled` לכל מוצר, דרך `public.get_iap_sales_status()` | שתי הסביבות סגורות; שגיאה/חוסר תשובה/תשובה ישנה מ-10 דקות ⇒ סגור |
| כלכלה סמכותית | `PT_AUTHORITATIVE_ECONOMY_ENABLED` + שורת `economy_configs` פעילה | `NO` בכל התצורות |

רכישה חדשה אפשרית רק כששתי השכבות פתוחות ויש UUID תקין. non-consumables זמינים גם לחשבון אנונימי; consumables דורשים זהות קבועה. App Review בודק ב-Sandbox באותו binary בזמן ש-Production נשאר סגור עד הפעלת הבעלים. `-PTIAPPreview` מציג UI ב-Debug בלבד ואינו נותן הרשאת רכישה.

## מצב בדיקות

| בדיקה | תוצאה |
|---|---|
| iOS unit tests — סכמת `PerfectTap`, ‏iOS 18.5 | 98/98 עברו, כולל בדיקת ברירת־מחדל שמשאירה את Model B כבוי |
| Postgres pgTAP | 132/132 עברו לאחר reset נקי של ה-stack המקומי |
| Supabase integration | 10/10 עברו מול ה-stack המקומי |
| Deno | 10/10 בדיקות purchase עברו; `deno check` עבר לשתי פונקציות ה-Edge עם ה-config הייעודי שלהן |
| StoreKit catalog structure | עבר: בדיוק תשעה מוצרים, מזהים, סוגים, reference names, מחירי בדיקה ולוקליזציית `en_US` תקינים |
| StoreKit lifecycle | עבר ב-CLI על iOS 26.2 ו-iOS 18.5. הכשל `SKInternalErrorDomain Code=3` משתחזר ב-runtime של iOS 26.5 ולכן אינו ייחודי להרצה משורת הפקודה |
| UI review screenshot | עבר על iOS 26.2: נוצרו חמישה צילומים עם מחירי StoreKit המקומיים. הם חומרי בדיקה, לא הוכחה למחירי ASC חיים |
| UI gameplay/consent | workload, מטריצת 15 מצבים ושתי בדיקות ATT האחרות עברו; `Allow` וצילום IAP עברו בריצה ממוקדת אחרי תיקון יציבות האוטומציה |
| Release build | עבר ל-iOS Simulator; נשארו אזהרות קיימות על XcodeGen groups כפולים ו-`Perf.swift` לקראת Swift 6 |
| Secret scan | היסטוריית Git ועץ העבודה הנקי עברו; התאמות allowlisted בלבד |
| App Store Connect read-only | נבדק שוב 25.11.2026 עם `iap_reconcile` (dry-run): API תקין, 0 מוצרים קיימים, כל תשעת המוצרים `MISSING`; כל מחירי הטיוטה ($0.99/$1.99/$3.99/$9.99, $2.99, $1.99) קיימים בטבלת המחירים של USA; 175 טריטוריות |

## חסמי שחרור

1. Xcode 26.6 דורש התקנת רכיב iOS 26.5 לפני בדיקת GUI. אחרי ההתקנה יש להריץ שוב את lifecycle ב-GUI; iOS 26.2 ו-18.5 כבר מספקים ראיית StoreKit תקינה.
2. להשלים ב-App Store Connect את Paid Apps Agreement, פרטי מס ובנק.
3. ליצור את תשעת מוצרי ה-IAP רק אחרי אישור: `PT_CONFIRM=yes bundle exec fastlane iap_reconcile confirm_create:true` (יצירה, לוקליזציה, מחיר, זמינות, צילום Review והערות, ואימות read-back), ולצרף אותם לגרסת 1.2.0 בעמוד הגרסה ב-ASC.
4. להפעיל Sign in with Apple ל-App ID ול-Supabase, כולל manual identity linking. SMTP נדרש רק לחלופת אימייל/Cloud Backup, לא לרכישת non-consumable.
5. אחרי גיבוי ואישור מפורש בלבד: לפרוס את המיגרציה וה-Edge Functions, להגדיר Apple root CAs ו-App Apple ID, ולהשאיר את קטלוג השרת disabled עד סוף QA.
6. לבצע על iPhone פיזי וב-Sandbox/TestFlight: רכישה, duplicate delivery, restore, מעבר מכשיר, offline באמצע אימות, Ask to Buy, refund, revoke ו-refund reversal.
7. לפרוס את `get_iap_sales_status` (מפרט בסעיף 4 של `docs/MONETIZATION_ACTIVATION_STRATEGY.md`), לפתוח מכירה ב-Sandbox בלבד, לבנות `Release-IAP` ל-TestFlight ול-App Review. Production נפתח רק אחרי אישור הגרסה והחלטת הבעלים.

## קבצי תפעול

- קטלוג מוצרים: `fastlane/iap/catalog.json`
- הערות Review: `fastlane/iap/review-notes.en-US.txt`
- בדיקת ASC ללא כתיבה: `bundle exec fastlane iap_check`
- reconciler אידמפוטנטי (dry-run כברירת מחדל): `bundle exec fastlane iap_reconcile`; כתיבה רק עם `confirm_create:true` וגם `PT_CONFIRM=yes`
- אסטרטגיית הפעלה לפי סביבה: `docs/MONETIZATION_ACTIVATION_STRATEGY.md`
- הכנת טיוטה מקומית ללא כתיבה או תלות במוצרי ASC: `bundle exec fastlane iap_prepare`
- שער הגשה סופי, read-only, שדורש תשעה מוצרי ASC וצילומי Review תקינים: `bundle exec fastlane iap_submission_validate`
- נוהל Sandbox במכשיר: `docs/STOREKIT_DEVICE_SANDBOX_QA.he.md`
- פריסת Supabase מוגנת: `scripts/deploy-supabase.sh`
- containment: `supabase/rollback/20261122120000_purchase_containment.sql`

## מדיניות החזר מטבעות

מדיניות חוב אינה פעילה ואינה מאושרת. ההמלצה היא חוב מוגבל/מותנה עם הגנות הונאה, בלי לחסום משחק; החלופות, כללי ההודעה ותהליך החריגים מפורטים ב-`docs/ECONOMY_1_2_0_EXECUTION.he.md`.
