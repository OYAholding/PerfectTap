# PerfectTap — מעבר מ-Firebase ל-Supabase (נובמבר 2026)

> **עדכון 1.1.0:** Release עבר ל-Supabase, ונתוני Firestore יובאו ל-`legacy`. תוכנית השחרור וה-rollback: `docs/RELEASE_PLAN_1.1.0.he.md`.
>
> **מצב עדכני (12.11.2026):** ה-backend נפרס לפרויקט `pgvtaotdyspwnpqtxpju` (פרנקפורט) ואומת מול הענן. פרטים מלאים: `docs/STATUS_REPORT_2026-11-12.he.md`. סעיפים 0, 1 ו-13 שלמטה מתארים את המצב שלפני הפריסה.

סימון: **[אומת]** = הורץ בפועל, והתוצאה מתועדת כאן. **[לא אומת]** = מוכן, אבל לא הורץ מול הענן.

## 0. מצב בשורה אחת
ה-backend החדש בנוי ונבדק מקומית, והאפליקציה עובדת מולו בסימולטור **[אומת]**. שום דבר עוד לא נפרס לענן. הוחלט ליצור פרויקט חדש באירופה (§1). גרסת ה-Release עדיין רצה על Firebase, ו-Firebase לא שונה בכלל.

| רכיב | מצב |
|---|---|
| Schema + RLS + RPC (2 migrations) | עובר 66/66 בדיקות pgTAP **[אומת]** |
| Edge Functions (3) | עוברות 7/7 בדיקות אינטגרציה מקצה לקצה מול stack מקומי **[אומת]** |
| Supabase Security/Performance Advisors | נקי, 0 אזהרות **[אומת]** |
| אפליקציית iOS (Debug, Supabase) | נבנית ללא שגיאות או אזהרות ב-Xcode 26.6 / iOS 26.5 **[אומת]** |
| בדיקות יחידה ב-Swift | עוברות 29/29 **[אומת]** |
| משחק אמיתי בסימולטור מול Supabase מקומי | כניסה אנונימית, שם משתמש, דו-קרב, Realtime, ניקוד מאומת ותוצאה עובדים **[אומת]** |
| פריסה לענן | **[לא אומת]**: ממתין ליצירת הפרויקט באירופה |
| ייבוא נתוני Firestore אמיתיים | **[לא אומת]**: הסקריפט מוכן ונבדק על נתוני דוגמה |

## 1. יעד הפריסה ובידוד מ-Corelim
- **החלטה (12.11.2026): פרויקט חדש באירופה (`eu-central-1`)**, בארגון `OYA Games` (`byvwxcsrfmsqfwbxaeai`).
  - הפרויקט הראשון, `PerfectTap!` (`jhsihajewbhwbuytlrmn`), נמצא בסינגפור. לא פרסתי אליו כלום, אבל לא בדקתי מה כבר יש בו. כדאי להציץ בדשבורד לפני מחיקה.
  - האפליקציה כבר לא מצביעה עליו: ב-`project.yml` הערכים `SUPABASE_URL` ו-`SUPABASE_PUBLISHABLE_KEY` ריקים עד שמגדירים את הפרויקט החדש.
  - כשהם ריקים, build ב-Debug חוזר ל-Firebase.
- Corelim (`wjyougesuxfkucpmgoyx`) ו-Corelim Test (`ulrdeytlwqetfzishxuj`) נמצאים בארגון אחר (`OYA`). לא נגעתי בהם.
- ה-stack המקומי רץ עם `project_id = "perfecttap"` ועם פורטים 556xx, כדי לא להתנגש בקונטיינרים המקומיים של Corelim.
- **שומר יעד** (`scripts/lib/perfecttap-target.sh`, משותף ל-deploy ול-use-project). הוא מסרב לכל יעד ש:
  - הוא אחד משני ה-refs של Corelim;
  - נמצא מחוץ לארגון OYA Games;
  - נמצא מחוץ לאזור `eu-*`;
  - השם שלו לא מכיל "PerfectTap";
  - לא תואם למה שהאפליקציה מצביעה עליו.

  נבדק: מסרב לסינגפור, ל-Corelim Test, ל-ref לא קיים ולמצב בלי ref.
- **לבדוק בדשבורד:** שהארגון `OYA Games` על תוכנית Free. ה-CLI לא מציג את התוכנית, ופרויקט בארגון בתשלום מחויב.

## 2. ארכיטקטורה

**לפני:**
```
SwiftUI ──► FirebaseService ──► Firebase Auth (anonymous + email link)
                         ├────► Firestore (players, duels, friendships, invites, guards…)
                         └────► Cloud Functions v2: startGame / submitScore (europe-west1)
```
רוב הכתיבות נעשו ישירות מהלקוח ל-Firestore, וההגנה היחידה הייתה Security Rules.

**אחרי:**
```
SwiftUI ──► Backend.shared (GameBackend protocol)
               ├─ FirebaseService  (Release – עד ה-cutover)
               └─ SupabaseService  (Debug היום; Release אחרי cutover)
                     ├─ Supabase Auth: anonymous + email/password
                     ├─ PostgREST: SELECT בלבד (RLS) + RPC (SECURITY DEFINER) לכל כתיבה
                     ├─ Realtime: Postgres Changes על duels / duel_invitations / friend_requests
                     └─ Edge Functions: claim-legacy-account, link-email, delete-account
```
- **אין צורך ב-Vercel, בשרת נוסף או ב-Redis.** כל ה-API הוא PostgREST ופונקציות Postgres, ושלוש Edge Functions מכסות את מה שדורש הרשאות admin.
- המשחק עצמו (CADisplayLink, קלט מגע ותזמון) נשאר מקומי לגמרי, ואף בקשת רשת לא נכנסת ללולאת הלחיצות. הרשת משמשת רק בתחילת הסשן, בשליחת הניקוד ובמצב חברתי.

## 3. מפת התלות ב-Firebase (ממצאי ה-audit)

| תלות | איפה | שימוש |
|---|---|---|
| FirebaseCore | `PerfectTapApp.swift` | `FirebaseApp.configure()` |
| FirebaseAuth | `FirebaseService` | אנונימי, קישור email/password, sign-in, מחיקה, re-auth |
| FirebaseFirestore | `FirebaseService` | כל הנתונים (ראו §4), 7 listeners, טרנזקציות |
| FirebaseFunctions | `FirebaseService` | `startGame`, `submitScore` (`functions/src`) |
| FirebaseAnalytics | `AnalyticsService` | אירועי משחק. **אין לו תחליף ב-Supabase והוא לא backend, לכן הושאר** |
| FirebaseMessaging | `project.yml` בלבד | **לא בשימוש בקוד.** אפשר להסיר (§14) |
| קונפיגורציה | 3 עותקים של `GoogleService-Info.plist`, `.firebaserc`, `firebase.json`, `firestore.rules`, `firestore.indexes.json`, `functions/`, `firestore-tests/` | |

## 4. מטריצת מיפוי של היכולות

| יכולת (Firebase) | Supabase | הערה |
|---|---|---|
| Auth אנונימי | `auth.signInAnonymously()` | הסשן נשמר ב-Keychain |
| קישור email ("Cloud Backup") | Edge Function `link-email` | בלי מייל אימות (§6) |
| כניסה עם email | `auth.signIn(email:password:)`, ואם נכשל, נדידה מ-Firebase | §6 |
| מחיקת חשבון | Edge Function `delete-account` | cascade מלא, כולל tombstone |
| `players/{uid}` | `public.profiles` (ציבורי) + `private.profile_data` (פרטי) | **שיפור:** מטבעות, רכישות ומשימות כבר לא גלויים לשחקנים אחרים |
| בדיקת ייחודיות username | `is_username_available` + unique index על `lower(username)` | השרת אוכף, לא רק הלקוח |
| server-day probe (כתיבת timestamp) | RPC `server_day()` | בלי כתיבה מיותרת |
| `duels` + listener | `public.duels` + Realtime | |
| create/join duel (טרנזקציה בלקוח) | `create_duel`, `join_duel` | נעילת שורה; קוד פתוח ייחודי |
| `submitDuelScore` (לקוח) | `submit_duel_score` | session מתוזמן בשרת, אידמפוטנטי |
| `game_sessions` + `startGame` | `private.game_sessions` + `start_game_session` | |
| `submitScore` callable | `submit_score` | פורט מלא של `scoring.ts` |
| `leaderboard/{mode}/scores` | `public.leaderboard_scores` | רק השרת כותב |
| `friend_requests` + `friend_request_state` | `friend_requests` + partial unique index | ה-guard הוא index ולא מסמך |
| `friendships` + מראת `players.friends` | `friendships (user_a < user_b)` | |
| `duel_invitations` + `duel_invite_state` | `duel_invitations` + `send/accept/reject/cancel/mark_*` | יצירת הדו-קרב וההזמנה בטרנזקציה אחת |
| 7 snapshot listeners | `RealtimeQueryListener` | אירוע גורם לטעינה מחדש של המצב המוסמך |

לא הושמטה אף יכולת קיימת.

## 5. היכן Firebase סמך על קלט לא מאומת

| בעיה | Firebase | Supabase |
|---|---|---|
| ניקוד דו-קרב | הלקוח כתב `host_score` כרצונו (הכללים בדקו רק טווח) | session מתוזמן בשרת וקשור לדו-קרב, וגבולות פיזיקליים (§8). ניקוד בלתי אפשרי נרשם כ-0 עם סימון |
| פרופיל (מטבעות, `no_ads`, שיאים) | נכתב ישירות; הכללים בדקו רק טיפוס וטווח | אותה רמת אמון (local-first), אבל דרך RPC עם ולידציה, מגבלת גודל ו-rate limit |
| קריאת פרופילים | כל משתמש קרא את כל המסמכים, כולל מטבעות | רק שדות ציבוריים |
| קריאת דו-קרבות | `allow read: if signedIn()` (כולם) | רק המשתתפים (RLS) |
| מראת `friends` לשחקן השני | נכשלה בשקט (הכללים חסמו) | לא נחוצה: `friendships` קנוני |
| ניחוש קודי דו-קרב / friend codes | ללא הגבלה | rate limit שנספר גם על ניסיון כושל (תוקן באג שבו כשל ביטל את הספירה) |
| זמני לקוח (`expires_at` של הזמנה) | הלקוח קבע | השרת (`now() + 10 min`) |

## 6. אסטרטגיית אימות
1. **אנונימי כברירת מחדל**, כמו היום. אין "חומת התחברות".
2. **נדידה עצלה (lazy) של משתמשים קיימים.** אין ייבוא סיסמאות ואין שינוי UID בכוח:
   - **בהפעלה הראשונה של בילד Supabase:** אם יש סשן Firebase במכשיר (Keychain), האפליקציה שולחת את ה-Firebase ID token ל-`claim-legacy-account`.
     - הפונקציה מאמתת חתימת RS256 מול ה-JWKS הציבורי של Google, וגם את ה-issuer, ה-audience וה-`auth_time`.
     - אחר כך היא מעבירה את הפרופיל, את הניקוד המאומת ואת החברויות (כשגם החבר כבר עבר) למשתמש ה-Supabase.
   - **שחקן email במכשיר חדש:** כניסת Supabase נכשלת, ואז האפליקציה נכנסת ל-Firebase עם אותם פרטים ושולחת token + סיסמה.
     - השרת מאמת את הסיסמה מול Firebase Identity Toolkit, מגדיר אותה ב-Supabase, ומכאן והלאה הכניסה ישירה.
   - הפעולה אידמפוטנטית ומוגנת מגניבה: חשבון שכבר נתבע לא עובר בלי סיסמה, וחשבון שנמחק מקבל tombstone ולא ניתן לשחזור.
   - נבדק מקצה לקצה עם מנפיק Firebase מדומה **[אומת]**. מול Firebase האמיתי **[לא אומת]**.
3. **Cloud Backup (קישור email):** נעשה בשרת (`link-email`), עם `email_confirm: true`.
   - **הסיבה:** ה-SMTP המובנה בתוכנית Free שולח רק לחברי הצוות, ועד 2 מיילים בשעה. לכן מייל אימות לשחקנים לא היה מגיע.
   - זו אותה רמת אמון כמו היום (Firebase לא אימת מיילים).
   - **ההמלצה בהמשך:** SMTP חינמי (למשל Resend עם 3,000 מיילים בחודש) והפעלת אימות.
4. **אובדן חשבון אנונימי:** הסשן נשמר ב-Keychain, ולכן שורד התקנה מחדש באותו מכשיר.
   - במכשיר חדש החשבון האנונימי אובד, כמו ב-Firebase. הפתרון הקיים, קישור email, ממשיך לעבוד.
5. **נבחנה ונדחתה:** Supabase "Third-party auth: Firebase" (להשאיר את Firebase Auth). זה היה משאיר תלות מלאה ב-Firebase, וה-UID לא בפורמט UUID.

## 7. Realtime: Postgres Changes או Broadcast
- **התנועה:** דו-קרב הוא אסינכרוני. כל שחקן משחק לבד ורק התוצאות משתוות, ויש כ-4–6 שינויי שורה לדו-קרב. אין סנכרון לחיצות בזמן אמת.
- **ההחלטה: Postgres Changes.** RLS חל אוטומטית על האירועים, אין צורך ב-triggers או ב-policies על `realtime.messages`, והנפח רחוק מהמגבלות.
- **Broadcast-from-DB** יהיה נכון אם יתווסף בעתיד מצב חי (למשל צופים או סנכרון לחיצות).
- **עמידות:**
  - כל אירוע הוא רק אות לטעינה מחדש של השורות המוסמכות. לכן אירועים כפולים או בסדר שגוי לא משבשים את ה-UI.
  - בכל subscribe מחדש (חזרה לרשת) מתבצעת טעינה מלאה.
  - polling איטי (20 שניות) רץ **רק** כשהערוץ מנותק. ערוץ תקין אף פעם לא עושה poll.
- **[אומת]:**
  - המארח רואה הצטרפות ובקשת השלמה בזמן אמת.
  - משתמש זר לא מקבל אף אירוע.
  - באפליקציה: "ScriptGuest joined!" הופיע בלי רענון.

## 8. אבטחה בצד השרת
- RLS פעיל על **כל** טבלה, כולל ב-`private` וב-`legacy`, שאינן חשופות כלל ל-API.
- אין `INSERT/UPDATE/DELETE` לתפקידי `anon` ו-`authenticated`. כל כתיבה עוברת דרך RPC שמחלץ את המשתמש מ-`auth.uid()`.
- ל-`anon` אין EXECUTE על אף RPC.
- `search_path=''` בכל הפונקציות, ו-default privileges מונעים חשיפה בטעות בעתיד.
- **אטומיות:**
  - `SELECT … FOR UPDATE` על דו-קרבות, הזמנות ו-sessions.
  - partial unique indexes: קוד פתוח אחד, בקשה ממתינה אחת לזוג, הזמנה ממתינה אחת לזוג.
  - advisory lock על claim.
- **כפילויות:** session חד-פעמי. ניקוד דו-קרב כפול מחזיר `duplicate:true` ולא דורס. 5 שליחות מקבילות הניבו בדיוק כתיבה אחת **[אומת]**.
- **Rate limits** (חלון קבוע, `private.rate_limits`):

  | פעולה | מגבלה |
  |---|---|
  | `start_game` | 20 לדקה |
  | `submit_*` | 30 לדקה |
  | `join_duel` / `create_duel` | 10 לדקה |
  | `friend_request` / `duel_invite` | 10 לדקה |
  | `save_profile` | 120 לדקה |
  | claim / link / delete | 10 / 5 / 5 לשעה |

  מעבר לזה, Supabase Auth מגביל כניסות אנונימיות ל-30 בשעה לכל IP.
- **ולידציה:**
  - payload פרופיל עד 256KB.
  - טווחי מספרים: מטבעות 0–10⁸, ניקוד 0–10⁷, רמה 1–10⁴.
  - פורמט username וקוד דו-קרב. גוף Edge Function עד 16KB, ו-token עד 4KB.
- **שגיאות בטוחות:** השרת מחזיר רק קודים יציבים (`duel_not_found`, `rate_limited`…), והאפליקציה ממפה אותם לטקסט. שגיאות פנימיות מוצגות כ"Something went wrong".
- **לוגים:** `raise log` רושם uid, מצב וסיבה לדחיית ניקוד. לא נרשמים tokens, סיסמאות או מפתחות.
- **מפתחות:** באפליקציה יש רק `sb_publishable_…`. `SupabaseConfig` מסרב לטעון מפתח שמתחיל ב-`sb_secret_`. מפתח ה-service role קיים רק בתוך Edge Functions (הזרקה אוטומטית).
- **גבולות האימות במשחק תגובה (חשוב):**
  - **מה השרת כן יכול להוכיח:**
    - שהניקוד אפשרי פיזית בזמן האמיתי שעבר מתחילת ה-session (לפי שעון השרת).
    - שקצב הלחיצות לא עולה על 12 בשנייה.
    - ש-perfects ≤ taps, ש-combo ≤ taps, ושהניקוד לא עולה על taps × ‎100 × מכפיל המצב.
  - **מה הוא לא יכול להוכיח:**
    - שכל לחיצה הייתה מדויקת באמת.
    - שהזמנים שהלקוח מדווח הם אמיתיים: בוט או אפליקציה מתוקנת יכולים "לשחק מושלם" בתוך הגבולות.
  - **החיזוק הבא שלא דורש תשתית בתשלום:** שליחת לוג לחיצות (offset לכל לחיצה, כמה KB) ו-replay דטרמיניסטי של מנוע התזמון ב-Edge Function. זה עדיין לא מונע בוט מושלם.
  - App Attest של Apple יכול להוסיף שכבה (חינם, דורש עבודה).

## 9. שינויים ב-SwiftUI
- **חדשים:**

  | קובץ | תוכן |
  |---|---|
  | `Services/Backend/GameBackend.swift` | פרוטוקול, טיפוסים משותפים, בחירת backend לפי `PT_BACKEND` |
  | `Services/Backend/BackendCodec.swift` | המיפוי של `FirebaseService` הועבר לכאן ללא שינוי, ונוסף parsing של timestamptz |
  | `Services/Backend/SupabaseService.swift` | המימוש, `SupabaseConfig` ו-`RealtimeQueryListener` |
  | `PerfectTapTests/BackendCodecTests.swift` | בדיקות יחידה |

- **שונו (מינימום):**
  - כל `FirebaseService.shared` הפך ל-`Backend.shared`, ב-13 קבצים.
  - `signOut()` הפך ל-async, כדי שהכניסה האנונימית החדשה תקרה רק אחרי היציאה.
  - `GameViewModel` פותח session שני שקשור לדו-קרב ושולח taps ו-perfects.
  - `LeaderboardView` (חברים) משתמש בחברויות הקנוניות.
  - `AuthViewModel` מזהה `BackendError.emailInUse`.
- **לא שונו:** מסכים, עיצוב, ניווט ולולאת המשחק.
- **SDK:** ‏`supabase-swift` 2.55.6 (exact, SPM). דורש iOS 16, שהוא בדיוק המינימום של הפרויקט.
- **Concurrency:**
  - `@MainActor` על השירות ועל ה-listeners. ה-callbacks מגיעים ל-main.
  - ניקוי ה-listeners מבוצע ב-`cancel()`, שמבטל את ה-Task ומסיר את הערוץ, ובנוסף ב-`deinit`.
  - שמירות פרופיל עוברות בשרשרת סדרתית.
  - retry עם backoff רק לשגיאות רשת. החזרות בטוחות כי השרת אידמפוטנטי.
- **קונפיגורציה:** `project.yml` מגדיר `SUPABASE_URL` ו-`SUPABASE_PUBLISHABLE_KEY` (ציבוריים), ו-`PT_BACKEND`: ‏Debug=`supabase`, ‏Release=`firebase`.
  - ב-DEBUG אפשר לעקוף דרך env: `SIMCTL_CHILD_SUPABASE_URL=http://127.0.0.1:55621`.

## 10. בדיקות ותוצאות בפועל

| # | תרחיש | איפה | תוצאה |
|---|---|---|---|
| 1 | הפעלה ו-auth אנונימי | אינטגרציה + סימולטור | ✅ |
| 2 | יצירת דו-קרב | pgTAP + אינטגרציה + סימולטור | ✅ |
| 3 | הצטרפות (כולל אותיות קטנות) | pgTAP + סימולטור | ✅ |
| 4 | סנכרון בין 2 שחקנים (Realtime) | אינטגרציה + סימולטור | ✅ |
| 5 | ניקוד תקין (מאומת עם session) | pgTAP + סימולטור (host_verified=true, ‏33 שניות) | ✅ |
| 6 | דחיית ניקוד בלתי אפשרי | pgTAP (`score_exceeds_taps`, `too_many_taps_for_time`) | ✅ |
| 7 | שליחה כפולה | pgTAP + אינטגרציה (5 במקביל, כתיבה אחת) | ✅ |
| 8 | הצטרפות לדו-קרב מלא או שהושלם | pgTAP | ✅ |
| 9 | 4 הצטרפויות בו-זמנית | אינטגרציה (בדיוק אחת מצליחה) | ✅ |
| 10 | ניתוק וחיבור מחדש | אינטגרציה (טעינה מוסמכת מלקוח חדש); הלוגיקה בקוד | ✅ חלקי: לא נבדק עם ניתוק רשת אמיתי במכשיר |
| 11 | גישה בלי הרשאה (anon, כתיבה ישירה) | pgTAP + אינטגרציה | ✅ |
| 12 | גישה לנתוני משתמש אחר | pgTAP + אינטגרציה (מטבעות, דו-קרב, אירועי Realtime) | ✅ |
| 13 | עדכוני ניקוד מקבילים | אינטגרציה | ✅ |
| 14 | כשלי רשת | retry/backoff בקוד; claim שנכשל (503) נדחה לפעם הבאה, נצפה בסימולטור | ✅ חלקי |
| 15 | סיום משחק ושמירת תוצאה | סימולטור ("YOU WIN!", ‏`duelWins=1` נשמר) | ✅ |
| 16 | שימוש במשאבי Free | הערכה בלבד (§11) | ⏳ |
| + | claim מ-Firebase, קישור email, מחיקה ו-tombstone | אינטגרציה | ✅ |
| + | rate limit על ניחוש קודים | אינטגרציה | ✅ |

**באגים שהבדיקות תפסו ותוקנו:**
1. ה-rate limit לא נספר על ניסיון כושל, כי ה-exception ביטל את הספירה.
2. ניקוד דו-קרב בלי session קרס בחיבור DB חדש (`record "cs" is not assigned`). זה נמצא רק בהרצה מהאפליקציה האמיתית, ונוספה בדיקת רגרסיה.
3. ייבוא חוזר היה מחזיר שחקן שמחק את החשבון שלו.
4. email כפול החזיר 500 במקום 409.

**הרצה:**
```bash
supabase start && supabase test db --local      # pgTAP
./supabase/tests/integration/run.sh             # end-to-end (מקומי בלבד)
cd ios/PerfectTap && xcodebuild test -scheme PerfectTap -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```
- **לא הורצו:** בדיקת ה-UI ‏(`ModeRuntimeQATests`) ובדיקות ה-emulator הישנות של Firestore.

## 11. עלות חודשית ומגבלות Free (נבדק מול supabase.com/pricing, 12.11.2026)

| משאב | מגבלת Free | הערכה ל-100 שחקנים פעילים ביום |
|---|---|---|
| DB | ‏500MB | פרופיל ≈ ‏5–20KB, כלומר מקום ל-25K–100K שחקנים. דו-קרבות נמחקים אחרי 180 יום |
| Egress | ‏5GB | כ-‏30 RPC לשחקן ביום × ‏2KB, כלומר ≈ ‏0.2GB בחודש |
| Auth MAU | ‏50,000 | אנונימיים נספרים |
| Edge Functions | ‏500K הפעלות | רק claim, link ו-delete: מעט מאוד |
| Realtime | ‏2M הודעות, **200 חיבורים במקביל** | ≈ ‏10K הודעות בחודש |
| השהיה | אחרי **7 ימים** בלי פעילות | |

- **העלות: ‎$0.** אין Vercel ואין שירותים בתשלום. Firebase (Spark) ממשיך עד ה-cutover.
- **צוואר הבקבוק הראשון:** **200 חיבורי Realtime במקביל.**
  - כל אפליקציה פתוחה במסך הבית מחזיקה WebSocket, בשביל ה-badges.
  - כשיהיו מעל כ-200 שחקנים מחוברים בו-זמנית:
    - להעביר את ה-listeners של הבית ל-fetch בעת כניסה למסך.
    - להשאיר Realtime רק במסכי דו-קרב.
- **בשלב הבדיקות:** פרויקט שאין בו פעילות יושהה אחרי 7 ימים (מחזירים אותו בלחיצה בדשבורד).

## 12. סיכונים פתוחים
1. **אזור:** הוחלט על EU (§1). עד שהפרויקט הישן בסינגפור יימחק או יושהה, הוא נספר במכסה של 2 פרויקטים פעילים בתוכנית Free.
2. ייבוא Firestore האמיתי לא הורץ. הוא דורש service account או `gcloud auth application-default login` ל-`perfecttap-48a08`.
3. ניקוד דו-קרב בלי session (כשהרשת נפלה בתחילת המשחק) מתקבל עם `*_verified=false` ובבדיקות סטטיות בלבד.
4. מצב local-first של הפרופיל: מטבעות, רכישות ו-`no_ads` עדיין בסמכות הלקוח, כמו קודם, אבל בגבולות.
   - **ההמלצה:** אימות רכישות StoreKit בשרת (App Store Server API). אפשר בחינם, ב-Edge Function.
5. אין CAPTCHA על כניסה אנונימית. Supabase ממליץ על Turnstile (חינם).
6. קישור email בלי אימות, כמו היום (§6).
7. Firebase UID של חבר שעוד לא עבר: החברות נוצרת רק כששני הצדדים עברו. בקשות והזמנות ממתינות לא מועברות, כי הן קצרות חיים.
8. מכשיר חדש עם claim אנונימי שכבר נתבע במכשיר אחר: מקבל חשבון חדש (409 `claimed_elsewhere`), כמו אובדן חשבון אנונימי היום.
9. ה-CLI המותקן הוא v2.119.0 (קיים v3.1.0). ב-v3, `db push` מכוון כברירת מחדל ל-local, וצריך `--remote --yes`. הסקריפט כתוב ל-v2 עם `--linked`, שעדיין נתמך ב-v3 עם אזהרה.

## 13. פריסה והגדרות סביבה
1. **יצירת הפרויקט באירופה (אתה מריץ, כי זה מגדיר סיסמת DB):** דרך הדשבורד, ארגון OYA Games, שם `PerfectTap`, אזור Central EU (Frankfurt). או ב-CLI:
   ```bash
   supabase projects create PerfectTap --org-id byvwxcsrfmsqfwbxaeai --region eu-central-1
   ```
   ה-CLI ישאל על סיסמת DB. את הסיסמה כדאי לשמור במנהל סיסמאות, לא בריפו.
2. **חיבור הריפו והאפליקציה לפרויקט החדש** (קורא רק את המפתח הציבורי, מעדכן את `project.yml` ומייצר מחדש את פרויקט ה-Xcode):
   ```bash
   ./scripts/use-supabase-project.sh <new-ref>
   ```
3. בדשבורד → Authentication → Sign In / Providers: להפעיל **Allow anonymous sign-ins**. מומלץ גם להפעיל CAPTCHA (Turnstile).
4. פריסה:
   ```bash
   ./scripts/deploy-supabase.sh            # בדיקת יעד + תוכנית (dry run)
   ./scripts/deploy-supabase.sh --apply    # link (מבקש סיסמת DB) → db push → secrets → functions deploy → advisors
   ```
5. **הפרויקט הישן בסינגפור** (`jhsihajewbhwbuytlrmn`): למחוק או להשהות בדשבורד, כדי לפנות את המכסה. זו פעולה בלתי הפיכה, ולכן אתה מבצע אותה.
6. ייבוא נתונים:
   ```bash
   cd scripts/migration && npm ci
   GOOGLE_APPLICATION_CREDENTIALS=… node export-firestore.mjs ./firestore-export.csv     # קריאה בלבד
   SUPABASE_DB_URL='postgresql://…' EXPECTED_REF=<new-ref> ./import-legacy.sh firestore-export.csv
   ```
   - `*.csv` נמצא ב-gitignore. הקובץ מכיל נתוני שחקנים, אז אסור לעשות לו commit.
   - מומלץ לייצא מחדש ממש לפני ה-cutover. `ingest()` אידמפוטנטי ולא דורס שחקנים שכבר עברו.

## 14. Cutover, rollback וניקוי
**Cutover מבוקר:**
1. פריסה (§13), ואחריה בדיקת עשן מול הענן: build ב-Debug עם `PT_BACKEND=supabase`, ומשחק בין שני מכשירים.
2. ייצוא Firestore וייבוא ל-legacy. בדיקה ב-SQL שמספר השחקנים זהה לספירה ב-Firestore.
3. TestFlight עם Release ו-`PT_BACKEND: supabase`.
4. שחרור ל-App Store, אם אפשר בהדרגה (Phased Release).
5. Firebase נשאר פעיל: משתמשים בגרסאות ישנות ממשיכים לעבוד מולו, ו-claim מעביר כל משתמש שמעדכן.
6. אחרי שבועיים-שלושה, ייצוא חוזר וייבוא כדי לתפוס התקדמות שנצברה בגרסה הישנה. ‏`ingest` מעדכן רק מי שעוד לא עבר.

**Rollback:**
- **באפליקציה:** להחזיר את `PT_BACKEND: firebase` ב-Release ולשחרר build. ‏`FirebaseService` נשאר שלם ועובד.
- **בענן:** כלום לא נמחק ב-Firebase, ו-Firestore ממשיך לקבל כתיבות מגרסאות ישנות.
- נתונים שנצברו רק ב-Supabase אחרי ה-cutover לא חוזרים אוטומטית ל-Firestore. אם צריך, אפשר להוסיף סקריפט export הפוך.
- **בפרויקט Supabase:** ‏`supabase db reset --linked` או מחיקת הפרויקט. לא נוגע בשום דבר אחר.

**ניקוי (רק אחרי אימות, ורק באישורך):**
- להסיר את `FirebaseMessaging` מ-`project.yml` (לא בשימוש). אפשר כבר עכשיו.
- אחרי חלון הנדידה (כמה חודשים):
  - להסיר את `FirebaseFirestore`, ‏`FirebaseFunctions` ו-`FirebaseService.swift`.
  - להסיר את `FirebaseAuth`. זה ישבית את ה-claim, אז רק אחרי שרוב המשתמשים עברו.
  - להסיר את `functions/`, ‏`firestore.rules`, ‏`firestore.indexes.json`, ‏`firestore-tests/`, ‏`.firebaserc` ו-`firebase.json`.
- להשאיר את `FirebaseCore` ו-`FirebaseAnalytics` אם ממשיכים עם Analytics, ואת `GoogleService-Info.plist` איתם.
- **לא למחוק** את פרויקט Firebase ‏`perfecttap-48a08` ואת הנתונים שלו בלי אישור מפורש.

## 15. Checklist סופי
- [x] Audit מלא ומפת תלות
- [x] Schema, ‏RLS, ‏RPC ו-migrations ב-version control
- [x] Edge Functions ‏(3)
- [x] אינטגרציית Swift עם backend כפול
- [x] pgTAP ‏66/66, אינטגרציה ‏7/7, ‏Swift ‏29/29, ‏advisors נקי, build מצליח
- [x] משחק דו-קרב מלא באפליקציה מול Supabase מקומי
- [x] החלטה על האזור: EU
- [x] יצירת פרויקט ב-`eu-central-1` + `use-supabase-project.sh <ref>`
- [ ] מחיקה או השהיה של פרויקט סינגפור
- [ ] הפעלת anonymous sign-ins (ו-CAPTCHA) בדשבורד
- [x] `deploy-supabase.sh --apply`
- [ ] בדיקת עשן מול הענן משני מכשירים
- [x] ייצוא וייבוא Firestore ואימות ספירות (12.11.2026: ‏19 שחקנים, 2 חברויות; `docs/RELEASE_PLAN_1.1.0.he.md` §3)
- [ ] TestFlight עם Release=`supabase` (build ‏1.1.0 (2) מוכן; העלאה ידנית, `RELEASE_PLAN_1.1.0.he.md` §6)
- [ ] שחרור הדרגתי
- [ ] ייבוא חוזר אחרי 2–3 שבועות
- [ ] ניקוי Firebase (באישור)
