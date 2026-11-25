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
| מתגי הפעלה | שישה Info.plist flags נפרדים לקטלוג, אימות שרת, חבילות מטבעות, Remove Forced Ads, סקינים וכלכלה סמכותית. כולם `NO` גם ב-Debug וגם ב-Release ונכשלים סגור אם חסרים |
| StoreKit 2 | טעינת מוצרים, רכישה עם `appAccountToken`, listener, סריקת `Transaction.unfinished`, שחזור, reconcile של זכאויות וריטריי מדורג לאימות שרת |
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

- `PT_IAP_CATALOG_ENABLED`
- `PT_IAP_SERVER_VERIFICATION_ENABLED`
- `PT_IAP_COIN_PACKS_ENABLED`
- `PT_IAP_REMOVE_ADS_ENABLED`
- `PT_IAP_PREMIUM_SKINS_ENABLED`
- `PT_AUTHORITATIVE_ECONOMY_ENABLED`

רכישה אפשרית רק כשמתגי הקטלוג, אימות השרת והקטגוריה דולקים ויש UUID תקין. non-consumables זמינים גם לחשבון אנונימי; consumables דורשים זהות קבועה. `-PTIAPPreview` מציג UI ב-Debug בלבד ואינו נותן הרשאת רכישה.

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
| App Store Connect read-only | 0 מוצרים קיימים; כל תשעת המוצרים ב-manifest עדיין `MISSING` |

## חסמי שחרור

1. Xcode 26.6 דורש התקנת רכיב iOS 26.5 לפני בדיקת GUI. אחרי ההתקנה יש להריץ שוב את lifecycle ב-GUI; iOS 26.2 ו-18.5 כבר מספקים ראיית StoreKit תקינה.
2. להשלים ב-App Store Connect את Paid Apps Agreement, פרטי מס ובנק.
3. ליצור את תשעת מוצרי ה-IAP, ולשלוח לפחות consumable ראשון ו-non-consumable ראשון יחד עם 1.2.0.
4. להפעיל Sign in with Apple ל-App ID ול-Supabase, כולל manual identity linking. SMTP נדרש רק לחלופת אימייל/Cloud Backup, לא לרכישת non-consumable.
5. אחרי גיבוי ואישור מפורש בלבד: לפרוס את המיגרציה וה-Edge Functions, להגדיר Apple root CAs ו-App Apple ID, ולהשאיר את קטלוג השרת disabled עד סוף QA.
6. לבצע על iPhone פיזי וב-Sandbox/TestFlight: רכישה, duplicate delivery, restore, מעבר מכשיר, offline באמצע אימות, Ask to Buy, refund, revoke ו-refund reversal.
7. רק אחרי שכל השלבים עוברים: להפעיל flags לפי קטגוריה, קודם ב-TestFlight ולבסוף ב-build ל-App Review.

## קבצי תפעול

- קטלוג מוצרים: `fastlane/iap/catalog.json`
- הערות Review: `fastlane/iap/review-notes.en-US.txt`
- בדיקת ASC ללא כתיבה: `bundle exec fastlane iap_check`
- הכנת טיוטה מקומית ללא כתיבה או תלות במוצרי ASC: `bundle exec fastlane iap_prepare`
- שער הגשה סופי, read-only, שדורש תשעה מוצרי ASC וצילומי Review תקינים: `bundle exec fastlane iap_submission_validate`
- נוהל Sandbox במכשיר: `docs/STOREKIT_DEVICE_SANDBOX_QA.he.md`
- פריסת Supabase מוגנת: `scripts/deploy-supabase.sh`
- containment: `supabase/rollback/20261122120000_purchase_containment.sql`

## מדיניות החזר מטבעות

מדיניות חוב אינה פעילה ואינה מאושרת. ההמלצה היא חוב מוגבל/מותנה עם הגנות הונאה, בלי לחסום משחק; החלופות, כללי ההודעה ותהליך החריגים מפורטים ב-`docs/ECONOMY_1_2_0_EXECUTION.he.md`.
