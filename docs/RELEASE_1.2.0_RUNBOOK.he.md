# PerfectTap 1.2.0 — Runbook שחרור מבוקר (gated)

**גרסה:** 1.2.0 (build 6 ומעלה) · **תאריך:** 25.11.2026 · **בעלים:** OYA Holding · **מצב:** טיוטה תפעולית. שום שלב כאן לא בוצע מול Production.

## עקרונות

1. **כל שלב נפתח רק אחרי שהשלב הקודם נסגר עם ראיה.** אין דילוג ואין ביצוע במקביל של שלבים עם שער בעלים.
2. 🔒 **שער בעלים** = נדרש אישור מפורש וכתוב של הבעלים (הודעה/תגובה ב-PR עם תאריך). סוכן או מפתח אינם רשאים לאשר במקומו.
3. כל ששת המתגים נשארים `NO` ב-Release עד שלב 13: `PT_IAP_CATALOG_ENABLED`, `PT_IAP_SERVER_VERIFICATION_ENABLED`, `PT_IAP_COIN_PACKS_ENABLED`, `PT_IAP_REMOVE_ADS_ENABLED`, `PT_IAP_PREMIUM_SKINS_ENABLED`, `PT_AUTHORITATIVE_ECONOMY_ENABLED`. CI אוכף זאת (`scripts/security/check-monetization-flags.sh`, job `release-guards`, וגם `scripts/qa/assert-built-flags.sh` על ה-Info.plist הבנוי).
4. ב-Supabase: `private.economy_configs` (`active`) ו-`private.iap_products` (`enabled`) נשארים `false` עד שלב 13.
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
| 6 | Supabase staging dry-run | — (staging) | migration + reconcile dry-run על staging, 0 אובדן בעלות |
| 7 | Supabase production migration | 🔒 G7 | גיבוי מאומת + `--apply` + pgTAP/smoke ירוקים, catalog disabled |
| 8 | פריסת purchase backend ל-production | 🔒 G8 | `--apply-purchases`, catalog עדיין disabled |
| 9 | Sandbox QA על מכשיר פיזי | — | 10 תרחישי `docs/STOREKIT_DEVICE_SANDBOX_QA.he.md` עברו |
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

סדר מיזוג ל-`main` (נבדק ב-`git merge-tree`, ללא conflicts; ראו `docs/QA_1.2.0_MATRIX.md` §PR):

1. **PR #12** `docs/adhd-attention-research` (`777011b`, מסמכים בלבד).
2. **PR #13** `hotfix/1.1.1-stability` (`a3ee906`). רק אם מוציאים 1.1.1 בנפרד; אחרת אפשר לסגור אותו כ"נכלל ב-#14".
3. **PR #14** `release/1.2.0` — כולל את `777011b` ו-`a3ee906` כ-ancestors, ולכן מיזוגו לבדו ממזג גם את #12/#13 ו-GitHub יסמן אותם merged.
4. ענפי הסוכנים (`agent-a/ios-economy`, `agent-b/economy-backend`, `agent-c/storekit-asc`, `agent-d/qa-release`) ממוזגים קודם ל-`release/1.2.0` (לא ישירות ל-`main`), CI ירוק אחרי כל מיזוג, ורק אז #14.

**כללים:** merge commit (לא squash) כדי לשמר את ה-SHAs של #12/#13; אין force-push ל-`main`; אחרי המיזוג `git tag v1.2.0-rc<N>` על ה-SHA שנבדק.

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

1. `bundle exec fastlane iap_check` (read-only) — מצב התחלתי: 0/9.
2. יצירת 9 המוצרים ב-ASC עם **IDs זהים** ל-`PerfectTap.storekit` ול-`catalog.json`, reference name, לוקליזציית en-US, צילום Review (`fastlane/iap/screenshots`), Review Notes (`fastlane/iap/review-notes.en-US.txt`). הבעלים יוצר/מאשר; אין lane כותב.
3. `bundle exec fastlane iap_check` → 9/9; `bundle exec fastlane iap_submission_validate` → PASS.
4. לצרף לפחות consumable אחד ו-non-consumable אחד לגרסת 1.2.0 ב-ASC (In-App Purchases → Add).

## 5. Sign in with Apple + App Store Server Notifications V2 — 🔒 G5

1. Apple Developer → Identifiers → `com.perfecttap.app` → capability **Sign in with Apple** (קיים ב-entitlements; לוודא ב-portal).
2. Services ID + Key ל-Sign in with Apple; הסוד נשמר **רק** ב-Supabase Dashboard (Auth → Providers → Apple). לא ב-git (`config.toml` נשאר `enabled = false` עם `env(...)`).
3. Supabase Auth: Apple provider פעיל, **Manual identity linking** פעיל (קישור חשבון אנונימי).
4. ASC → App Information → **App Store Server Notifications**: Version 2, URL ל-Production ול-Sandbox:
   `https://<prod-ref>.supabase.co/functions/v1/app-store-notifications`
   (הפונקציה רצה עם `verify_jwt = false`; האימות הוא שרשרת התעודות של Apple בתוך הפונקציה). ב-staging רושמים את URL ה-staging רק בשדה Sandbox.
5. ASC → "Request a Test Notification" → לוודא ב-logs של הפונקציה `TEST` נקלט וחתימה אומתה. (מתבצע רק אחרי שלב 8, כשהפונקציה פרוסה.)

## 6. Supabase staging dry-run

> staging = פרויקט PerfectTap נפרד ב-org OYA Games, אזור EU. `verify_perfecttap_target` מסרב לכל דבר אחר (Corelim, org אחר, אזור לא-EU).

1. **שים לב:** `deploy-supabase.sh` דורש ש-`project.yml` יצביע על אותו ref. לכן:
   ```bash
   scripts/use-supabase-project.sh <staging-ref>    # משנה project.yml + supabase/.perfecttap-ref (לא לעשות commit!)
   ./scripts/deploy-supabase.sh                     # dry run: CLI 2.119.0, target verified, תוכנית
   ./scripts/deploy-supabase.sh --apply             # db push + secrets + claim/delete functions + auth config
   ```
2. ייבוא snapshot אנונימי/מדגמי של נתוני production ל-staging (לא PII אמיתי אם אפשר).
3. **Reconcile dry-run**: הרצת ה-reconciliation של legacy balances במצב dry-run (אין שינוי יתרה) — התפלגות `accepted` / `review` / `rejected`; מדגם ידני של 20 חשבונות `review`; **אפס אובדן בעלות** (owned_items, Remove Ads, skins) מול snapshot.
4. pgTAP מול staging אינו זמין דרך CLI ללא `--linked` — מריצים את `supabase/tests/cloud/smoke.test.ts` מול staging.
5. `PT_CONFIRM_PRODUCTION` לא בשימוש כאן. `--apply-purchases` ל-staging רק עם Apple Sandbox בלבד.
6. **החזרה:** `scripts/use-supabase-project.sh <prod-ref>` ואז `git diff ios/PerfectTap/project.yml supabase/.perfecttap-ref` חייב להיות ריק. `PT_EXPECTED_PROD_REF=<prod-ref> scripts/security/check-backend-target.sh` → PASS.

## 7. Supabase production migration — 🔒 G7

תנאים: שלב 6 עבר, G2 אושר, חלון תחזוקה מתואם.

1. **גיבוי**:
   - Dashboard → Database → Backups: גיבוי יומי/PITR קיים מהשעה האחרונה — לרשום timestamp.
   - בנוסף: `pg_dump` של schema + `public`/`private` למיקום מקומי מוצפן (לא ב-repo).
   - **אימות הגיבוי:** שחזור הגיבוי לפרויקט staging/זמני וספירת שורות ב-`profiles`, `private.economy`, ledger הרכישות — זהה למקור. גיבוי שלא שוחזר = אין גיבוי.
2. `./scripts/deploy-supabase.sh` (dry run) — לוודא ref = production, CLI 2.119.0.
3. `./scripts/deploy-supabase.sh --apply` — מיגרציות (כולל `20261122120000_purchase_ledger_and_economy_guard`, `20261125130443_authoritative_economy_ledger`), secrets של Firebase, `claim-legacy-account`, `delete-account`, auth config, `db advisors`.
4. אימות מיידי:
   - `supabase/tests/cloud/smoke.test.ts` מול production.
   - SQL read-only: `select count(*) from private.iap_products where enabled;` → **0**. `select count(*) from private.economy_configs where active;` → **0**.
   - Build 1.1.x החי ממשיך לעבוד (התחברות, שמירת פרופיל, leaderboard, duel) — בדיקה ידנית על מכשיר עם הגרסה מהחנות.
5. Reconcile production במצב dry-run בלבד; תוצאות נשמרות; שום שינוי יתרה.
6. Rollback: אין "down migration". במקרה תקלה — `supabase/rollback/20261122120000_purchase_containment.sql` (מכבה רכישות, משמר ledger) ושחזור `save_profile` מגיבוי ה-schema; שחזור מלא מ-PITR רק בהחלטת בעלים.

## 8. פריסת purchase backend ל-production — 🔒 G8

```bash
PT_CONFIRM_PRODUCTION=yes APPLE_ROOT_CAS_B64=<...> APPLE_APP_APPLE_ID=6760975737 \
  ./scripts/deploy-supabase.sh --apply-purchases
```
- פורס `verify-purchase` + `app-store-notifications` עם `APPLE_ENABLED_ENVIRONMENTS=Production,Sandbox`.
- הקטלוג בשרת נשאר **disabled**. אחרי הפריסה: שלב 5.5 (Test Notification).
- אם נוספו פונקציות חדשות (למשל `admob-ssv` לפי חוזה הכלכלה) — הן **לא** נפרסות ע"י הסקריפט הנוכחי; צריך שינוי מאושר בסקריפט לפני השער.

## 9. Sandbox QA על מכשיר פיזי

- נוהל: `docs/STOREKIT_DEVICE_SANDBOX_QA.he.md` (10 תרחישים: אורח, non-consumable, restore, coins לאורח, קישור Apple, retry/duplicate, חשבון שגוי, מכשיר שני, Ask to Buy/pending, refund/revoke/reversal).
- build Debug/Development חתום עם המתגים **ON רק ב-Debug מקומי** (לא commit), או build TestFlight עם קטלוג staging. אסור לשנות את Release ב-git.
- קטלוג השרת מופעל **ב-staging בלבד** לבדיקה זו.
- ראיות: צילומי מחיר Sandbox, transaction IDs, תוצאת ledger "אין זיכוי כפול", לוגי Edge Function. נרשם ב-`docs/QA_1.2.0_MATRIX.md`.
- בנוסף: רגרסיית freeze/stutter על iPhone פיזי לפי `docs/perf/DEVICE_PROFILING_PROTOCOL.he.md` (כולל AirPods ופרסומת אמיתית).

## 10. TestFlight — 🔒 G10

```bash
bundle exec fastlane validate_release        # read-only
bundle exec fastlane build                   # IPA מקומי
scripts/qa/assert-built-flags.sh <Payload/PerfectTap.app מתוך ה-IPA>   # כל המתגים NO
PT_CONFIRM=yes bundle exec fastlane beta     # 🔒 קבוצה פנימית בלבד
```
- QA ידני: 15 מצבי משחק, Game Over, רקע/חזית, AirPods, iPad, ATT, מודעות אמיתיות + revive, החנות במצב "flags off" (אין מחירים/כפתורי קנייה פעילים), מעבר חשבון, duel.
- 48 שעות לפחות בלי crash חדש ב-Xcode Organizer / TestFlight crashes.

## 11. הגשה ל-App Review — 🔒 G11

- ב-ASC בלבד, ידני: בחירת build, IAPs מצורפים (שלב 4), Review Notes, App Privacy כולל Purchase History.
- **Version Release = "Manually release this version"**.
- בהערות ל-Review: איך להגיע לחנות; אם הקטלוג כבוי ב-build — לציין שהרכישות יופעלו בשרת אחרי אישור, ולצרף את צילומי ה-Review (Apple בודקת IAPs שצורפו — ראו סיכון: מוצר מצורף שאינו נגיש ב-build עלול לגרום לדחייה 2.1; להחליט עם הבעלים אם ה-build ל-Review נשלח עם קטגוריות מסוימות דולקות, ואז G13 חלקי מוקדם — החלטה נפרדת ומתועדת).

## 12. שחרור ידני — 🔒 G12

- אחרי "Pending Developer Release": הבעלים לוחץ Release. מומלץ **Phased Release** (7 ימים) כדי שניתן יהיה לעצור.
- 1.1.x ממשיך לעבוד מול אותו backend (תאימות לאחור נבדקה בשלב 7.4).

## 13. הפעלה מסחרית מבוקרת — 🔒 G13 לכל צעד

כל צעד = אישור בעלים נפרד, 24–72 שעות ניטור ירוק לפני הבא:

| צעד | מה נדלק | איפה |
|---|---|---|
| 13.1 | `PT_IAP_CATALOG_ENABLED` + `PT_IAP_SERVER_VERIFICATION_ENABLED` + `PT_IAP_REMOVE_ADS_ENABLED` ב-build חדש; `private.iap_products` של Remove Ads `enabled=true` | build TestFlight → Review |
| 13.2 | `PT_IAP_PREMIUM_SKINS_ENABLED`; מוצרי skins enabled | שרת + build |
| 13.3 | `PT_IAP_COIN_PACKS_ENABLED`; coin packs enabled (דורש Sign in with Apple) | שרת + build |
| 13.4 | `private.economy_configs.active = true` (עם `approved_by`/`approved_at` — נאכף ב-check constraint) (`balanced-premium-rc1` מאושר); reconcile apply לחשבונות `accepted` בלבד | שרת |
| 13.5 | `PT_AUTHORITATIVE_ECONOMY_ENABLED` — **רק** אחרי שכל grant חוזר (gameplay, quest, wheel, daily, rewarded/SSV) נרשם ב-ledger | build |

- הדלקת flag ב-Release מחייבת commit ייעודי + עדכון מכוון של `check-monetization-flags.sh` (רשימת allow מפורשת לכל flag) — כלומר שינוי שה-CI מזהה ושהבעלים מאשר ב-PR. אין עקיפה של הבדיקה.
- השרת הוא מתג ההפעלה האמיתי: גם כש-flag דולק ב-build, מוצר עם `enabled=false` לא נמכר.

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
1. **עצירת מכירות בשרת (שניות):** הרצת `supabase/rollback/20261122120000_purchase_containment.sql` ב-SQL Editor של פרויקט PerfectTap המאומת (ref נבדק מול `supabase/.perfecttap-ref`, **לא** Corelim). מכבה את כל `private.iap_products`, שולל `execute` מ-`service_role` על `record_verified_purchase` / `revoke_purchase` / `process_app_store_notification`, ורושם `purchase_backend_contained`. ה-ledger נשמר.
   - שימו לב: לאחר השלילה, notifications של Apple ייכשלו ו-Apple תנסה שוב (retry עד ~5 ימים) — זה רצוי; אחרי התיקון מחזירים `grant execute` ו-Apple תשלח שוב.
2. **עצירת כלכלה סמכותית:** `update private.economy_configs set active = false;` → RPCs מחזירים `economy_disabled`; הלקוח שומר outbox.
3. **ASC:** אם נדרש — "Remove from Sale" למוצר הבעייתי (In-App Purchases → מוצר → Cleared for Sale = off). לא מוחקים מוצרים.
4. **Phased Release:** Pause ב-ASC אם הבעיה בצד הלקוח.
5. **Build תיקון:** flags ל-`NO`, hotfix, TestFlight, Expedited Review אם צריך.
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
