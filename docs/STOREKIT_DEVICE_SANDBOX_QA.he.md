# StoreKit Sandbox — נוהל QA במכשיר אמיתי

הנוהל מיועד ל-PerfectTap 1.2.0 לאחר אישור מפורש להפעלת סביבת הבדיקה. הוא אינו מאשר תשלומי Production ואינו מחליף את שער ההגשה `iap_submission_validate`.

## תנאי פתיחה

1. ב-App Store Connect: הסכמי Paid Apps, מס ובנק תקינים; תשעת מוצרי ה-IAP קיימים עם IDs זהים ל-`PerfectTap.storekit`; משתמש Sandbox Tester נפרד מחשבון Apple אישי.
2. ב-Identifiers: capability של Sign in with Apple פעיל ל-`com.perfecttap.app`; ספק Apple ב-Supabase מוגדר ו-manual identity linking פעיל.
3. בשרת Sandbox מאושר בלבד: מיגרציה ו-Edge Functions פרוסים, Apple App ID ו-root CAs מוגדרים, וקטלוג השרת מכיל את תשעת המוצרים. אין להפעיל Production בלי אישור נוסף.
4. ב-iPhone: Developer Mode פעיל; ב-Settings → Developer → Sandbox Apple Account נכנסים עם ה-Sandbox Tester. מתקינים build של תצורת `Release-IAP` מ-TestFlight (build של `Release` לא ימכור לעולם — זו התנהגות מכוונת).
5. בשרת: `private.iap_sales_control` — `Sandbox` פתוח, `Production` סגור; המוצרים הנבדקים `enabled` ב-`private.iap_products`.

## תרחישי חובה

1. **אורח:** פתח התקנה נקייה, דחה Cloud Backup, ודא שהמשחק, Remove Ads והסקינים זמינים בלי אימייל.
2. **non-consumable:** קנה Remove Ads וסקין כאורח. ודא מסירה אחת בלבד גם כשה-listener וה-purchase flow מקבלים אותה עסקה.
3. **שחזור:** מחק והתקן מחדש, לחץ Restore Purchases, ודא ששתי ההרשאות חוזרות מהיסטוריית Apple בלי לדרוש אימייל ובלי להעביר ownership בשרת לחשבון אנונימי אחר.
4. **מטבעות כאורח:** נסה לקנות coin pack. חייב להופיע Sign in with Apple; אסור להציג sheet של StoreKit לפני קישור זהות קבועה.
5. **קישור Apple:** בצע Sign in with Apple, ודא שה-UID והפרופיל האנונימי הקיים נשמרים, ואז קנה את החבילה הקטנה. היתרה צריכה לעלות פעם אחת בלבד.
6. **retry/duplicate:** נתק רשת אחרי אישור התשלום ולפני תשובת השרת, פתח שוב את האפליקציה וחבר רשת. העסקה unfinished עד אימות, ואז מזוכה פעם אחת בלבד.
7. **חשבון שגוי:** נסה לעבד עסקת מטבע עם חשבון אחר. אסור לזכות או לסיים את העסקה; אחרי חזרה לחשבון Apple הנכון היא צריכה להמשיך בבטחה.
8. **מכשיר שני:** היכנס עם אותו Sign in with Apple. ודא שיתרת המטבעות מגיעה מהשרת וש-non-consumables חוזרים דרך Restore Purchases.
9. **Ask to Buy / cancel / pending:** ודא שאין grant לפני `verified`, וש-pending נשמר בלי הודעת הצלחה כוזבת.
10. **החזרים:** הפעל refund/revoke/refund reversal ב-Sandbox. ודא audit, סדר אירועים, הסרת entitlement והגנת יתרה מאפס.

11. **kill switch:** סגור את `Sandbox` בשרת, חזור לאפליקציה (foreground) — כפתורי הקנייה נעלמים תוך רענון אחד, אבל Restore Purchases ומסירת עסקאות פתוחות ממשיכים לעבוד. פתח שוב וודא שהחנות חוזרת.
12. **שרת לא זמין:** במצב טיסה, נסה לקנות — אסור שיופיע sheet של StoreKit (המתג נכשל סגור). Restore של Remove Forced Ads וסקינים חייב לעבוד גם בלי שרת.
13. **refund reversal:** אחרי refund של סקין ב-Sandbox, בצע reversal (אם זמין) וודא שהסקין חוזר פעם אחת בלבד.
14. **Production סגור:** ודא באותו build שהקוד קורא `AppTransaction.environment = sandbox`; build מ-App Store (Production) לא יציג חנות עד שהבעלים פותח את `Production`.

## ראיות לשמור

- צילום מסך לכל מוצר עם המחיר שמוחזר מ-Sandbox; אין לתאר מחיר טיוטה מקומי כמחיר חי.
- transaction ID, original transaction ID, product ID, appAccountToken ותוצאת verify ללא JWS/סודות מלאים.
- לוגי client ו-Edge Function לכל retry/refund, ותוצאת שאילתת ledger שמוכיחה שאין זיכוי כפול.
- דגם iPhone, גרסת iOS, מקור build וחשבון Sandbox ששימש לבדיקה.
