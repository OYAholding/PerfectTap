# PerfectTap 1.2.0 — Runbook שחרור מבוקר (gated)

**גרסה:** 1.2.0 (build 6 ומעלה) · **עודכן:** 27.11.2026 · **בעלים:** OYA Holding · **מצב:** טיוטה תפעולית. שום שלב כאן לא בוצע מול Production (head ב-production: `20261114120000`).

מסמכים קשורים: `docs/STAGING_AND_DEPLOY_PLAN_1.2.0.md` (סדר פריסה, secrets, staging), `docs/OWNER_CHECKLIST_1.2.0.he.md`, `docs/SECURITY_REVIEW_1.2.0.md`, `docs/SUPPORT_OPERATIONS.md`, `docs/PRODUCT_DECISIONS_1.2.0_RC.md`, `docs/MONETIZATION_ACTIVATION_STRATEGY.md`.

## עקרונות

1. **כל שלב נפתח רק אחרי שהשלב הקודם נסגר עם ראיה.** אין דילוג ואין ביצוע במקביל של שלבים עם שער בעלים.
2. 🔒 **שער בעלים** = נדרש אישור מפורש וכתוב של הבעלים (הודעה/תגובה ב-PR עם תאריך). סוכן או מפתח אינם רשאים לאשר במקומו.
3. **שני בינאריים, שתי שכבות שנכשלות סגור.** `Release` (ברירת מחדל, `Monetization.Off.xcconfig`): כל מתגי ה-IAP `NO`, לא מוכר לעולם. `Release-IAP` (`Monetization.AppStoreIAP.xcconfig`): תקרת IAP פתוחה, **המכירה בפועל נפתחת רק בשרת** (`private.iap_sales_control` לכל סביבה + `iap_products.enabled`). זה הבינארי שנשלח ל-TestFlight ול-App Review עם ה-IAPs. `PT_AUTHORITATIVE_ECONOMY_ENABLED` נשאר `NO` **בשני** ה-Release ב-1.2.0. CI אוכף (`scripts/security/check-monetization-flags.sh` מודע לתצורה, ו-`scripts/qa/assert-built-flags.sh` על ה-Info.plist הבנוי).
4. ב-Supabase: `private.economy_configs.active` נשאר `false` ב-1.2.0. `private.iap_products.enabled` ומתג ה-Sandbox נפתחים רק לקראת App Review (שלב 11), ומתג Production רק אחרי שחרור ובאישור (שלב 13).
5. שום פקודה עם `--linked` / `db push` / `functions deploy` / `fastlane beta` לא רצה בלי השער שמעליה.
6. בכל שלב רושמים בטבלת "יומן שערים" בסוף המסמך: מי, מתי, SHA, ראיה.

## מפת השערים

| # | שלב | שער בעלים | ראיה לסגירה |
|---|---|---|---|
| 0 | Preflight: CI ירוק + QA matrix | — | כל jobs ב-CI ירוקים על ה-SHA; `docs/QA_1.2.0_MATRIX.md` מעודכן |
| 1 | אינטגרציית קוד (merge ל-`main`) | 🔒 G1 | PRs ממוזגים לפי הסדר, CI ירוק על `main` |
| 2 | אישור Model B (ערכי כלכלה) | 🔒 G2 | אישור כתוב לטבלת `balanced-premium-rc1` ולמדיניות refund |
| 3 | אישור מחירי IAP | 🔒 G3 | אישור כתוב ל-price tier של כל אחד מ-9 המוצרים |
| 4 | יצירת מוצרים ב-App Store Connect | 🔒 G4 | `fastlane iap_check` מראה 9/9 קיימים |
| 5 | Sign in with Apple + ASSN V2 URL | 🔒 G5 | Apple provider פעיל ב-Supabase, URL רשום ב-ASC, test notification התקבל |
| 6 | חזרה גנרלית (staging) | — / 🔒 אם נבחר פרויקט בתשלום | Supabase מקומי: כל המיגרציות + pgTAP + Edge Functions עברו; אופציונלי: פרויקט חד-פעמי משחזור גיבוי |
| 7 | Supabase production migration | 🔒 G7 | גיבוי מאומת + `--apply` + pgTAP/smoke ירוקים, catalog disabled |
| 8 | פריסת purchase backend ל-production | 🔒 G8 | `--apply-purchases`, catalog עדיין disabled |
| 9 | Sandbox QA על מכשיר פיזי | — (הבעלים מבצע) | 10 תרחישי `docs/STOREKIT_DEVICE_SANDBOX_QA.he.md` עברו על build `Release-IAP` |
| 10 | TestFlight | 🔒 G10 | build פנימי, QA ידני, אפס crash חדש |
| 11 | הגשה ל-App Review | 🔒 G11 | Submit ידני ב-ASC, Manual release |
| 12 | שחרור ידני לחנות | 🔒 G12 | Release ידני אחרי Approved |
| 13 | הפעלה מסחרית מבוקרת | 🔒 G13 (לכל שלב ramp) | catalog/config enabled בהדרגה, ניטור ירוק |
| 14 | ניטור שוטף | — | דשבורד יומי 14 יום |
| ∞ | כיבוי תשלומים מיידי / Incident | ללא המתנה לאישור | ראו סעיף 15 |

---

## 0. Preflight (לפני כל שער)

```bash
git fetch origin && git status                     # עץ נקי, SHA ידוע
scripts/security/check-monetization-flags.sh       # PASS
scripts/security/check-secret-files.sh             # PASS
scripts/security/check-backend-target.sh           # PASS (app ref == supabase/.perfecttap-ref)
scripts/qa/deno-functions.sh                       # ALL PASS
```
- CI על ה-SHA: `release-guards`, `secret-scan`, `edge-functions`, `backend` (pgTAP + integration), `ios-unit-tests`, `ios-storekit-tests`, `ios-release-build` — כולם ירוקים.
- `docs/QA_1.2.0_MATRIX.md`: אין שורה ב-FAILED; כל BLOCKED מוסבר ושייך לשלב מאוחר יותר (Sandbox/TestFlight).
- ביצועים: `docs/perf/FREEZE_STUTTER_REGRESSION.he.md` — perf gate עבר על ה-SHA.

## 1. אינטגרציית קוד — 🔒 G1

מצב מאומת 27.11.2026 (`gh pr view` + `git merge-base`):
- **PR #12** `docs/adhd-attention-research` → `main`, פתוח, head `777011b` (מסמכים בלבד).
- **PR #13** `hotfix/1.1.1-stability` → `main`, פתוח, head `a3ee906`.
- **PR #14** `release/1.2.0` → `main`, פתוח. `777011b` ו-`a3ee906` הם ancestors שלו, ולכן מיזוג #14 לבדו מכניס גם את #12 ו-#13, ו-GitHub יסמן אותם merged.
- ענפי הסוכנים כבר מוזגו ל-`release/1.2.0`, והתיקיות שלהם נמחקו. הענפים עצמם נשמרו, וכך גם `backup/codex-wip-2026-11-25` ב-remote.

סדר מומלץ: #12 (אם רוצים היסטוריה נפרדת למסמכים), #13 (רק אם 1.1.1 יוצא בנפרד; אחרת "נכלל ב-#14"), ואז #14. **כללים:** merge commit (לא squash) כדי לשמר את ה-SHAs; אין force-push ל-`main`; אחרי המיזוג `git tag v1.2.0-rc<N>` על ה-SHA שנבדק.

## 2. אישור Model B — 🔒 G2

- מקור: `docs/ECONOMY_1_2_0_EXECUTION.he.md`, `docs/ECONOMY_SERVICE_CONTRACT.md`.
- הבעלים מאשר בכתב: Daily, Wheel, Quests, Rewarded, נוסחת משחק, Season, מחירי 23 הפריטים, `gameplay_daily_cap`, ומדיניות refund/חוב (מומלץ: ניכוי עד אפס, `coin_debt` לא פעיל).
- ראיה: unit test + pgTAP שמצמידים את המספרים המשותפים (Swift `EconomyConfig.balancedPremiumRC1` == JSON בשרת) ירוקים.
- **לא** מפעילים את הקונפיגורציה בשלב זה — רק מאשרים ערכים.

## 3. אישור מחירי IAP — 🔒 G3

- מקור: `fastlane/iap/catalog.json` (9 מוצרים: coin packs consumable, `Remove Ads` ו-premium skins non-consumable).
- הבעלים מאשר price tier וטריטוריות לכל מוצר. מחירי `PerfectTap.storekit` הם מחירי בדיקה בלבד ואינם מחייבים.
- תנאי קדם ב-ASC: Paid Apps Agreement, מס ובנק — **Active** (בדיקה ידנית של הבעלים).

## 4. יצירת מוצרים ב-App Store Connect — 🔒 G4

1. `bundle exec fastlane iap_reconcile` (dry-run, ברירת מחדל). מצב 25.11: 9/9 `MISSING`, 175 טריטוריות, כל המחירים נמצאים במחירון.
2. **אחרי אישור כתוב של הבעלים בלבד:** `PT_CONFIRM=yes bundle exec fastlane iap_reconcile confirm_create:true`. יוצר את 9 המוצרים עם IDs זהים ל-`PerfectTap.storekit` ול-`fastlane/iap/catalog.json`, לוקליזציית en-US, מחיר USD, זמינות, צילום Review והערות Review (`fastlane/iap/review-notes.en-US.txt`), עם read-back. **פעולה בלתי הפיכה.**
3. הרצה חוזרת של `iap_reconcile` (dry-run) צריכה להחזיר 0 פעולות.
4. לצרף את המוצרים לגרסת 1.2.0 ב-ASC (In-App Purchases → Add). IAPs ראשונים חייבים להיות מצורפים לגרסה.

## 5. Sign in with Apple + App Store Server Notifications V2 — 🔒 G5

1. Apple Developer → Identifiers → `com.perfecttap.app` → capability **Sign in with Apple** (קיים ב-entitlements; לוודא ב-portal).
2. Services ID + Key ל-Sign in with Apple; הסוד נשמר **רק** ב-Supabase Dashboard (Auth → Providers → Apple). לא ב-git (`config.toml` נשאר `enabled = false` עם `env(...)`).
3. Supabase Auth: Apple provider פעיל, **Manual identity linking** פעיל (קישור חשבון אנונימי).
4. ASC → App Information → **App Store Server Notifications**: Version 2, URL ל-Production ול-Sandbox:
   `https://<prod-ref>.supabase.co/functions/v1/app-store-notifications`
   (הפונקציה רצה עם `verify_jwt = false`; האימות הוא שרשרת התעודות של Apple בתוך הפונקציה). ב-staging רושמים את URL ה-staging רק בשדה Sandbox.
5. ASC → "Request a Test Notification" → לוודא ב-logs של הפונקציה `TEST` נקלט וחתימה אומתה. (מתבצע רק אחרי שלב 8, כשהפונקציה פרוסה.)

## 6. חזרה גנרלית (staging)

ההחלטה והנימוק נמצאים ב-`docs/STAGING_AND_DEPLOY_PLAN_1.2.0.md` §1. בקצרה: פרויקט חינמי לא זמין (מכסת 2 פרויקטים חינמיים כבר מלאה), ולכן החזרה האוטומטית רצה על Supabase מקומי.
1. `supabase db reset --local`: כל 13 המיגרציות, ואחריהן `supabase test db --local` עם 8 סוויטות.
2. `supabase functions serve`: בדיקה שהפונקציות נכשלות סגור כשאין secrets.
3. Containment drill מקומי: `pt-support.sh contain economy|purchases`.
4. **אופציונלי, 🔒 עלות:** פרויקט חד-פעמי בארגון OYA Games ששוחזר מגיבוי של production. מריצים עליו `deploy-supabase.sh --apply`, אחר כך `reconcile_legacy_economy(true)`, ומוודאים אפס אובדן בעלות. אחר כך מוחקים אותו. `verify_perfecttap_target` מסרב ל-Corelim, לארגון אחר ולאזור שאינו EU.
5. אחרי כל החלפת ref: `scripts/use-supabase-project.sh <prod-ref>`, ואז `git diff ios/PerfectTap/project.yml supabase/.perfecttap-ref` חייב להיות ריק.

## 7. Supabase production migration — 🔒 G7

תנאים: שלב 6 עבר, G2 אושר, חלון תחזוקה מתואם.

1. **גיבוי**:
   - Dashboard → Database → Backups: גיבוי יומי/PITR קיים מהשעה האחרונה — לרשום timestamp.
   - בנוסף: `pg_dump` של schema + `public`/`private` למיקום מקומי מוצפן (לא ב-repo).
   - **אימות הגיבוי:** שחזור הגיבוי לפרויקט staging/זמני וספירת שורות ב-`profiles`, `private.economy`, ledger הרכישות — זהה למקור. גיבוי שלא שוחזר = אין גיבוי.
2. `./scripts/deploy-supabase.sh` (dry run) — לוודא ref = production, CLI 2.119.0.
3. `./scripts/deploy-supabase.sh --apply` — 7 מיגרציות (`20261122120000` purchase ledger, `20261125130443` ledger, `20261125200000` sources, `20261126090000` sales gate, `20261126120000` season calendar, `20261127110000` hardening, `20261127120000` support), secrets של Firebase, `claim-legacy-account`, `delete-account`, auth config, `db advisors`.
4. אימות מיידי:
   - `supabase/tests/cloud/smoke.test.ts` מול production.
   - SQL read-only: `select count(*) from private.iap_products where enabled;` → **0**. `select count(*) from private.economy_configs where active;` → **0**. `select public.get_iap_sales_status();` → שני הסביבות `salesEnabled:false`.
   - Build 1.1.x החי ממשיך לעבוד (התחברות, שמירת פרופיל, leaderboard, duel) — בדיקה ידנית על מכשיר עם הגרסה מהחנות.
5. Reconcile production במצב dry-run בלבד; תוצאות נשמרות; שום שינוי יתרה.
6. Rollback: אין "down migration". במקרה תקלה: `scripts/support/pt-support.sh contain purchases|economy <ticket> "<reason>"` (מריץ את סקריפטי ה-containment, משמר ledger ונרשם ב-`private.support_actions`). שחזור מלא מ-PITR רק בהחלטת בעלים.

## 8. פריסת purchase backend ל-production — 🔒 G8

```bash
PT_CONFIRM_PRODUCTION=yes APPLE_ROOT_CAS_B64=<...> APPLE_APP_APPLE_ID=6760975737 \
  ./scripts/deploy-supabase.sh --apply-purchases
```
- פורס את `verify-purchase`, `app-store-notifications` ו-`admob-ssv` עם `APPLE_ENABLED_ENVIRONMENTS=Production,Sandbox`.
- מומלץ להגדיר secret בשם `ADMOB_ALLOWED_AD_UNITS` עם מזהי ה-rewarded units של האפליקציה.
- הקטלוג בשרת נשאר **disabled**, ושני מתגי המכירה `false`. אחרי הפריסה: שלב 5.5 (Test Notification), ובקונסולת AdMob מגדירים את כתובת ה-SSV.

## 9. Sandbox QA על מכשיר פיזי

- נוהל: `docs/STOREKIT_DEVICE_SANDBOX_QA.he.md`, עם 10 תרחישים: אורח, non-consumable, restore, coins לאורח, קישור Apple, retry/duplicate, חשבון שגוי, מכשיר שני, Ask to Buy/pending, refund/revoke/reversal.
- Build: **`Release-IAP` מ-TestFlight פנימי** (שלב 10). לפני כן פותחים מכירה **ב-Sandbox בלבד** (`update private.iap_sales_control set sales_enabled = true where environment = 'Sandbox'`) ומפעילים את המוצרים שבבדיקה. Production נשאר סגור. אין שינוי ב-git.
- ראיות: צילומי מחיר Sandbox, transaction IDs, `pt-support.sh purchase <id>` שמראה "אין זיכוי כפול", ולוגי Edge Function. הכל נרשם ב-`docs/QA_1.2.0_MATRIX.md`.
- בנוסף: רגרסיית freeze/stutter על iPhone פיזי לפי `docs/perf/DEVICE_PROFILING_PROTOCOL.he.md`, כולל AirPods ופרסומת אמיתית.

## 10. TestFlight — 🔒 G10

```bash
bundle exec fastlane validate_release                                   # read-only
PT_CONFIRM_IAP_CEILING=yes bundle exec fastlane build configuration:Release-IAP
scripts/qa/assert-built-flags.sh --release-iap <Payload/PerfectTap.app> # AppStoreIAP profile, IAP ceiling YES, economy NO
PT_CONFIRM_IAP_CEILING=yes PT_CONFIRM=yes bundle exec fastlane beta configuration:Release-IAP   # 🔒 קבוצה פנימית בלבד
```
- QA ידני: 15 מצבי משחק, Game Over, רקע/חזית, AirPods, iPad, ATT, מודעות אמיתיות + revive, מעבר חשבון, duel. החנות כשמתג Sandbox סגור (אין כפתורי קנייה פעילים) וכשהוא פתוח (שלב 9).
- 48 שעות לפחות בלי crash חדש ב-Xcode Organizer / TestFlight crashes.

## 11. הגשה ל-App Review — 🔒 G11

- ב-ASC בלבד, ידני: בוחרים את **אותו build `Release-IAP`** שנבדק בשלב 10, מצרפים את ה-IAPs (שלב 4), מוסיפים Review Notes (`fastlane/iap/review-notes.en-US.txt`) ו-App Privacy כולל Purchase History.
- **לאורך כל ה-Review:** מתג Sandbox פתוח והמוצרים `enabled`, כי App Review בודק ב-Sandbox. מתג Production **סגור**. כך מוצר מצורף נגיש לבודק (מונע דחייה 2.1), ולקוחות אמיתיים עדיין לא יכולים לקנות.
- **Version Release = "Manually release this version"**.

## 12. שחרור ידני — 🔒 G12

- אחרי "Pending Developer Release": הבעלים לוחץ Release. מומלץ **Phased Release** (7 ימים) כדי שניתן יהיה לעצור.
- 1.1.x ממשיך לעבוד מול אותו backend (תאימות לאחור נבדקה בשלב 7.4).

## 13. הפעלה מסחרית מבוקרת — 🔒 G13 לכל צעד

כל צעד הוא אישור בעלים נפרד, עם 24–72 שעות ניטור ירוק לפני הצעד הבא. **אין צורך ב-build חדש** כדי למכור ב-1.2.0, כי הבינארי `Release-IAP` כבר בחנות:

| צעד | מה נדלק | איפה |
|---|---|---|
| 13.1 | `iap_sales_control` עבור Production, עם Remove Ads בלבד `enabled` | שרת |
| 13.2 | premium skins `enabled` | שרת |
| 13.3 | coin packs `enabled` (דורש Sign in with Apple, G5) | שרת |
| 13.4 (גרסה עתידית) | `economy_configs.active = true` (`approved_by`/`approved_at`), reconcile apply, טיפול בתור review, **גרסת מינימום מחייבת**, **חסימת הרשמה חדשה ל-Firebase** | שרת + גרסה |
| 13.5 (גרסה עתידית) | `PT_AUTHORITATIVE_ECONOMY_ENABLED` ב-build חדש, רק אחרי 13.4 | build |

- כיבוי: `sales_enabled = false` לסביבה, או `enabled = false` למוצר. עסקאות ששולמו ממשיכות להימסר ולהשתחזר.
- הדלקת `PT_AUTHORITATIVE_ECONOMY_ENABLED` ב-Release מחייבת שינוי מכוון ב-`check-monetization-flags.sh` ב-PR שהבעלים מאשר. אין עקיפה של הבדיקה.

## 14. ניטור (14 יום אחרי כל צעד, אח"כ שבועי)

| תחום | מקור | סף התראה |
|---|---|---|
| תשלומים | ASC Sales/Trends; `private.purchase_ledger` (ספירה לפי סטטוס) (יומי) | verify failure rate > 2%; עסקה מאומתת ללא grant; grant כפול (אותו `transaction_id`) > 0 |
| Refunds | ASSN V2 `REFUND`/`REVOKE`/`REFUND_REVERSED` ב-`private.economy_events`; ASC | refund rate > 5% לשבוע; notification שנכשל באימות; עיכוב > 1h |
| Crashes | Xcode Organizer, TestFlight, Firebase/Analytics | crash-free sessions < 99.5% או crash חדש בטופ 5 |
| Freeze/stutter | ביקורות/פניות "נתקע", Organizer Hangs | Hang rate עולה מול 1.1.1 |
| כלכלה | `earned/spent` יומי לפי source, balance p50/p90/p99, `capped`, `implausible_result`, `rate_limited`, תור `legacy_economy_reviews` | p99 balance קופץ ×3 ביום; `implausible_result` > 1% מהאירועים; תור review > 50 פתוחים |
| Edge Functions | Supabase logs: 5xx, latency של `verify-purchase`/`app-store-notifications` | 5xx > 1% / 15 דק׳ |

## 15. כיבוי תשלומים מיידי ו-Incident Response

**מי רשאי להפעיל:** כל מפתח on-call — בלי להמתין לאישור. מעדכנים את הבעלים מיד אחרי.

**טריגרים:** grant כפול/חסר, אימות JWS שבור, refund abuse, באג כלכלה שמייצר מטבעות, דליפת סוד, Edge Function שמחזירה 5xx רציף, הוראה של Apple.

**צעדים (לפי הסדר, כל אחד עצמאי):**
1. **עצירת מכירות בשרת (שניות):** `PT_CONFIRM=yes scripts/support/pt-support.sh contain purchases <ticket> "<reason>"`, או הרצת `supabase/rollback/20261122120000_purchase_containment.sql` ב-SQL Editor של פרויקט PerfectTap המאומת (ref נבדק מול `supabase/.perfecttap-ref`, **לא** Corelim). מכבה את כל `private.iap_products`, שולל `execute` מ-`service_role` על `record_verified_purchase` / `revoke_purchase` / `process_app_store_notification`, ורושם `purchase_backend_contained`. ה-ledger נשמר.
   - שימו לב: לאחר השלילה, notifications של Apple ייכשלו ו-Apple תנסה שוב (retry עד ~5 ימים) — זה רצוי; אחרי התיקון מחזירים `grant execute` ו-Apple תשלח שוב.
2. **עצירת כלכלה סמכותית:** `update private.economy_configs set active = false;` → RPCs מחזירים `economy_disabled`; הלקוח שומר outbox.
3. **ASC:** אם נדרש — "Remove from Sale" למוצר הבעייתי (In-App Purchases → מוצר → Cleared for Sale = off). לא מוחקים מוצרים.
4. **Phased Release:** Pause ב-ASC אם הבעיה בצד הלקוח.
5. **Build תיקון:** במקרה הצורך שולחים build `Release` (ללא IAP) או hotfix, דרך TestFlight, ו-Expedited Review אם צריך.
6. **תקשורת:** הודעה לבעלים מיד; אם נפגעו משתמשים — הודעה בתוך האפליקציה/תמיכה; goodwill לפי מדיניות שאושרה ב-G2.
7. **שחזור:** תיקון → staging → `grant execute ... to service_role` (הפוך מ-containment) → enable מוצר אחד → ניטור 24h → השאר. כל צעד חזרה = אישור בעלים.
8. **Postmortem** תוך 5 ימי עבודה: ציר זמן, השפעה (משתמשים/מטבעות/כסף), שורש, פעולות. בלי האשמה.

**דליפת סוד:** סיבוב מיידי (Supabase secret keys, Apple keys ב-ASC, Sign in with Apple key), `scripts/security/check-secret-files.sh` + gitleaks על ההיסטוריה, הסרה מהיסטוריית git רק בהחלטת בעלים.

## יומן שערים

| שער | תאריך | מאשר | SHA / build | ראיה (קישור) |
|---|---|---|---|---|
| G1 קוד | | | | |
| G2 Model B | | | | |
| G3 מחירים | | | | |
| G4 ASC products | | | | |
| G5 SiwA + ASSN | | | | |
| G7 prod migration | | | | |
| G8 purchase backend | | | | |
| G10 TestFlight | | | | |
| G11 App Review | | | | |
| G12 Release | | | | |
| G13.1–13.5 | | | | |
