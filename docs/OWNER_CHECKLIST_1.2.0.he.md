# PerfectTap 1.2.0 — צ׳קליסט לבעלים (App Store Connect, הסכמים, Sandbox, TestFlight)

את הצעדים האלה רק הבעלים יכול לבצע או לאשר. כל שורה מסומנת לפי השער ב-`docs/RELEASE_1.2.0_RUNBOOK.he.md`. לא לשתף בצ׳אט סיסמאות, קובצי `.p8` או מספרי חשבון.

## א. הסכמים, מס ובנק (חובה לפני כל IAP) — G4
- [ ] App Store Connect → **Business** (Agreements, Tax, and Banking): לחתום על **Paid Apps Agreement** (Free Apps כבר פעיל).
- [ ] **Banking**: להוסיף חשבון בנק. Apple מאמתת אותו, וזה יכול לקחת כמה ימים.
- [ ] **Tax**: למלא את טופס ה-W-8BEN (או W-8BEN-E לחברה), ואת טפסי המס של המדינות הרלוונטיות.
- [ ] לוודא שהסטטוס של שלושתם **Active**. עד אז מוצרים לא יופיעו גם ב-Sandbox.

## ב. מוצרי IAP — G3 + G4
- [ ] לאשר בכתב את 9 המחירים הסופיים (מועמדים ב-`docs/PRODUCT_DECISIONS_1.2.0_RC.md`).
- [ ] אני מריץ בדיקה בלבד: `bundle exec fastlane iap_reconcile`. כרגע 9 מתוך 9 לא קיימים.
- [ ] אחרי אישור מפורש שלך: `PT_CONFIRM=yes bundle exec fastlane iap_reconcile confirm_create:true`. הפעולה יוצרת את המוצרים, הלוקליזציה, המחיר, הזמינות, צילום ה-Review והערת ה-Review. **אי אפשר לבטל אותה. מזהה מוצר שנוצר לא חוזר לשימוש.**
- [ ] בעמוד הגרסה ב-ASC: לסמן את ה-IAPs שיוגשו עם הגרסה (IAPs ראשונים חייבים להיות מצורפים לגרסה).

## ג. Sign in with Apple — G5
- [ ] Apple Developer → Identifiers → `com.perfecttap.app`: לוודא שהיכולת **Sign in with Apple** מסומנת.
- [ ] ליצור Services ID ו-Key ל-Sign in with Apple. את הסוד להזין **רק** ב-Supabase Dashboard: Auth → Providers → Apple.
- [ ] Supabase Auth: להפעיל **Manual identity linking** (קישור של חשבון אורח).
- [ ] ASC → App Information → **App Store Server Notifications V2**: להזין את אותו URL ל-Production ול-Sandbox, `https://pgvtaotdyspwnpqtxpju.supabase.co/functions/v1/app-store-notifications`. רק אחרי פריסת השלב D5.
- [ ] ללחוץ על "Request a Test Notification" ולוודא שהיא התקבלה (אני בודק בלוגים).

## ד. Supabase ו-AdMob — G7 / G8
- [ ] להחליט על staging: לוותר עליו, או לאשר פרויקט חד-פעמי בתשלום (בערך $10 לחודש, נמחק אחרי החזרה). פרטים ב-`docs/STAGING_AND_DEPLOY_PLAN_1.2.0.md` §1.
- [ ] לאשר את פריסת שבע המיגרציות ל-production (D2) אחרי גיבוי מאומת (D0).
- [ ] לאשר את פריסת `verify-purchase`, `app-store-notifications` ו-`admob-ssv` (D5).
- [ ] AdMob → כל rewarded ad unit → **Server-side verification**: להזין URL של `…/functions/v1/admob-ssv`. לשלוח לי את מזהי ה-ad units, ואגדיר אותם ב-`ADMOB_ALLOWED_AD_UNITS`.
- [ ] Firebase Console → Authentication → **לחסום הרשמה חדשה** (סוגר את C2 בדוח האבטחה). חשבונות קיימים ממשיכים לעבוד.

## ה. Sandbox על מכשיר — G9
- [ ] ASC → Users and Access → **Sandbox Testers**: ליצור משתמש בדיקה (אימייל ייעודי שלא שימש ל-Apple ID).
- [ ] על iPhone פיזי: Settings → App Store → Sandbox Account, ולהתחבר עם משתמש הבדיקה.
- [ ] לעבור על 10 התרחישים ב-`docs/STOREKIT_DEVICE_SANDBOX_QA.he.md`: אורח, Remove Ads, Restore, מטבעות, קישור Apple, כפילות, חשבון שגוי, מכשיר שני, **Ask to Buy**, **refund/reversal**. וגם AirPods ופרסומת אמיתית.

## ו. TestFlight ו-App Review — G10 / G11
- [ ] לאשר build מסוג **`Release-IAP`**, הבינארי שנשלח עם ה-IAPs (המכירה נפתחת רק בשרת): `PT_CONFIRM_IAP_CEILING=yes PT_CONFIRM=yes bundle exec fastlane beta configuration:Release-IAP`. אני מריץ אותו רק אחרי אישורך.
- [ ] לפני ה-Review: לפתוח מכירה **ב-Sandbox בלבד** (`iap_sales_control` עבור Sandbox), ולהפעיל את המוצרים שבבדיקה. Production נשאר סגור.
- [ ] Submit ידני ב-ASC, עם **"Manually release this version"**. הערות ה-Review נמצאות ב-`fastlane/iap/review-notes.en-US.txt`.
- [ ] אחרי Approved: שחרור ידני (מומלץ Phased Release), ורק אחר כך החלטה נפרדת על פתיחת המכירה ב-Production.

## ז. לא חלק מ-1.2.0, ומחייב אישור נפרד בעתיד
- הפעלת הכלכלה הסמכותית (`economy_configs.active` ואז `PT_AUTHORITATIVE_ECONOMY_ENABLED`). דורשת גרסת מינימום מחייבת, כי 1.1.x לא יכולה להרוויח מטבעות אחרי ההפעלה. דורשת גם reconcile מאושר וטיפול בתור ה-review.
