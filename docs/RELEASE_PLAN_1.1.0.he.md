# PerfectTap 1.1.0 (build 2) — תוכנית שחרור, מעבר ו-Rollback (12.11.2026)

סימון: **[ענן]** = אומת מול Supabase פרנקפורט / Firebase אמיתי. **[מקומי]** = אומת ב-stack מקומי. **[ידני]** = דורש פעולה שלך. **[לא אומת]** = לא הורץ.

> המסמך בריפו ציבורי: יש בו ספירות בלבד. אין בו UID, שמות משתמש או כתובות מייל.

## 1. מה משתנה ב-1.1.0
- **Release → Supabase** (`PT_BACKEND: supabase`). הפרויקט: `pgvtaotdyspwnpqtxpju`, ‏`eu-central-1`.
- **Firebase נשאר פעיל ולא שונה.** גרסאות 1.0.x מהחנות ממשיכות לעבוד מולו.
- **Cloud Backup (יצירת גיבוי במייל) כבוי זמנית**, עם הודעה ברורה במסך (`PT_EMAIL_OTP_ENABLED=NO`), כי אין SMTP שמאפשר לשלוח קודי אימות לשחקנים (§5). אימות המייל **לא** עוקף.
- Privacy, ‏Terms ו-Support באפליקציה פותחים את עמודי GitHub Pages. כתובת הקשר: `PerfectTap@oyaholding.com`.
- תיקון באג במעבר: אחרי claim האפליקציה מאמצת מהשרת את שם המשתמש ואת קוד החבר (§3.3).
- **Invisible Zone:** תוויות האזורים (PERFECT/GREAT/GOOD) היו מוסתרות רק ב-opacity, ולכן VoiceOver ובדיקות אוטומטיות עדיין "ראו" אותן. עכשיו הן לא מרונדרות במצב הזה, והפריסה לא משתנה.
- **בדיקות UI:** נוסף scheme ‏`PerfectTapUITests` ונוסף מתג DEBUG בלבד, `-PTUITestNoAds`. בלעדיו פרסומת מלאה אמיתית עצרה את הריצה, כי XCUITest לא יכול לסגור אותה. ב-Release המתג לא קיים.

## 2. מלאי Firebase (קריאה בלבד, 12.11.2026) [ענן]
| נתון | כמות |
|---|---|
| משתמשי Firebase Auth | 26, **כולם אנונימיים** (0 עם מייל או סיסמה) |
| מסמכי `players` | ‏19 (לכל אחד יש משתמש Auth; ל-7 משתמשי Auth אין פרופיל) |
| `friendships` (קנוני) | 1 |
| חברויות שקיימות רק במערכי `players.friends` (גרסאות ישנות, הדדיות) | 1 |
| `leaderboard/*/scores` | **0**: האוסף לא קיים. השיאים נמצאים בשדות `best_*` של הפרופיל |
| `duels` / `duel_invitations` / `friend_requests` | ‏20 / 16 / 1. קצרי חיים, לא מועברים (מתועד) |
| `game_sessions`, ‏Storage, ‏RTDB | אין |
| רכישות IAP אמיתיות (`no_ads`, ‏`season_premium`) | **0**. ‏`owned_items` אצל שחקן אחד = פריטים שנקנו במטבעות |
| סה"כ מטבעות | ‏4,943 |
| כפילויות | 2 פרופילים עם אותו שם משתמש **ואותו קוד חבר** |

**נתונים שלא עוברים אוטומטית:**
- דו-קרבות, הזמנות ובקשות פתוחות (קצרי חיים).
- היסטוריית לוח מובילים מאומתת (לא קיימת).
- שחקן שאיבד את ה-session האנונימי של Firebase (מחק את האפליקציה ואיפס את המכשיר, או עבר למכשיר אחר). בלי token של Firebase אין דרך מאובטחת להוכיח בעלות. אותו מצב קיים היום ב-Firebase.
- השחקן השני מבין שני בעלי השם הכפול מקבל בקשה לבחור שם חדש. קוד החבר שלו מתחדש.

## 3. אימות המעבר
### 3.1 ייצוא
- הייצוא נעשה מ-Firestore דרך REST, עם token קריאה בלבד של Firebase CLI. נכתב ל-scratchpad מקומי (0600), לא לריפו.
- `scripts/migration/export-firestore.mjs` עודכן: מערכי `players.friends` **הדדיים** מיוצאים עכשיו כ-`friendships` (`mirror:…`). רשומה חד-צדדית לא מועברת.

### 3.2 Dry run
| שלב | תוצאה |
|---|---|
| מקומי: ‏`ingest` | ‏19 שחקנים, 2 חברויות. הרצה שנייה: 0 שינויים (אידמפוטנטי) **[מקומי]** |
| מקומי: claim מדומה לכל 19 השחקנים | ‏19/19 `claimed`; מטבעות, רמה, סטטיסטיקות, הישגים ופריטים תואמים 19/19; 2/2 חברויות שוחזרו; התנגשות שם אחת בדיוק **[מקומי]** |
| מקומי: מקרי קצה | UID לא מוכר → `no_legacy_data`; מכשיר שני → `claimed_elsewhere`; מחיקה → tombstone, וייבוא חוזר לא מחזיר את השחקן **[מקומי]** |
| ענן: ייבוא בתוך טרנזקציה עם ROLLBACK | ‏19/2, מטבעות 4,943; אחרי ROLLBACK ‏0 שורות **[ענן]** |
| **ענן: ייבוא אמיתי ל-`legacy`** | ‏19 שחקנים, 2 חברויות, 4,943 מטבעות, 0 claims, ‏0 משתמשים **[ענן]** |

- הסכימה `legacy` לא חשופה ל-API (‏PGRST106). אפשר לבטל את הייבוא עם `truncate legacy.raw_docs, legacy.players, legacy.friendships, legacy.leaderboard` (בתנאי שאין claims).
- **לייבא שוב** ממש לפני השחרור הפומבי ושבועיים-שלושה אחריו. ‏`ingest` מעדכן רק שחקנים שעוד לא עברו.

### 3.3 באג שנמצא ותוקן: התנגשות זהות אחרי claim
- **התרחיש:** כש-claim מוותר על שם משתמש או קוד חבר שכבר תפוס, השרת שומר ריק. האפליקציה, שעדיין מחזיקה את העותק מתקופת Firebase, שמרה אותו מחדש מיד אחרי הכניסה.
- **התוצאה:** כל `save_profile` נכשל (`username_taken` / `friend_code_taken`), וההתקדמות הפסיקה להסתנכרן בלי שום הודעה.
- **התיקון:** `SupabaseService.adoptServerIdentityAfterClaim()`. שם המשתמש וקוד החבר נלקחים מהשרת. שם ריק מפנה למסך בחירת שם. ההתקדמות המקומית לא משתנה. אם קריאת השרת נכשלת, הניסיון חוזר בהפעלה הבאה (ה-claim אידמפוטנטי).
- **בדיקות:** `LegacyClaimIdentityTests`.

### 3.4 שדרוג משתמש קיים אמיתי [ענן]
- **הבדיקה:** build ה-Supabase הותקן בסימולטור שבו נשמר ב-Keychain ה-session של חשבון QA קיים ב-Firebase (שחקן בדיקה מנובמבר). ה-Keychain שורד מחיקת אפליקציה.
- **מה קרה:**
  - בהפעלה הראשונה האפליקציה שלחה Firebase ID token אמיתי ל-`claim-legacy-account`.
  - נוצר `legacy_claims` אחד בענן.
  - שם המשתמש, קוד החבר והשיא ב-Classic נשמרו.
  - ההתקדמות החדשה (14 מצבי משחק) נצברה מעל הנתונים הישנים, בלי כפילות שחקן.
- **Firebase לא נכתב:** ה-`updateTime` של המסמך ב-Firestore נשאר 08.11.2026.
- **עדיין לא נבדק:** שדרוג ממכשיר אמיתי עם גרסת החנות 1.0.2 (§6 #1).

## 4. אבטחה
| נושא | מצב |
|---|---|
| RLS | פעיל על כל הטבלאות ב-`public`, ‏`private` ו-`legacy` **[ענן]** |
| הרשאות כתיבה ל-anon/authenticated | אין **[ענן]** |
| פונקציות SECURITY DEFINER ב-public | 5. לאף אחת אין EXECUTE ל-anon **[ענן]** |
| סכימות חשופות | `public` ו-`graphql_public` בלבד **[ענן]** |
| Advisors | רק `0012 anonymous sign-ins` (מכוון) **[ענן]** |
| Auth | אנונימי פעיל, `mailer_autoconfirm=false`, ‏30 כניסות אנונימיות לשעה לכל IP, ‏CAPTCHA כבוי |
| Edge Functions | `claim-legacy-account` ו-`delete-account`, ‏`verify_jwt=true`. בלי JWT → ‏401 **[ענן]** |
| Secrets | רק שמות מוכרים. ל-Firebase רק מפתח ציבורי. אין סוד בריפו (gitleaks) |
| Rate limits | ב-DB (`private.rate_limits`), ראו `SUPABASE_MIGRATION.he.md` §8 |
| מפתח Firebase | ‏probe מ-12.11: **אין עדיין הגבלת אפליקציה**. הגבלת API פעילה (Gemini חסום). צריך לבצע ידנית לפי `SECURITY_AUDIT_FIREBASE_KEY_2026-11-12.he.md` §5 **[ידני]**. תואם לכל הגרסאות ול-claim |
| App Check | לא לאכוף, כי זה ישבור את גרסאות 1.0.x |

**חשיפת Firestore עד ה-cutover (סיכון פתוח):**
- כל משתמש מחובר, כולל אנונימי שנוצר עם המפתח הציבורי, יכול לקרוא את כל 19 מסמכי `players`: מטבעות, קודי חברים ופריטים. **אין במסמכים מייל או שם אמיתי.**
- `duels` ו-`duel_invitations` קריאים לכל משתמש מחובר.
- אי אפשר להחמיר את הכללים בלי לשבור את 1.0.x (לוח מובילים, חיפוש לפי קוד, ייחודיות שם).
- **מקטין את הסיכון:** הגבלת האפליקציה לפי Bundle ID, ומכסת הרשמות נמוכה ב-Firebase Auth.
- **סוגר את הסיכון:** פרישת 1.0.x (§9), ואחריה כללי `deny` ל-Firestore.

## 5. Email / Cloud Backup
- **מצב:** אין SMTP מותאם (`smtp_host` ריק). ה-SMTP המובנה שולח רק לחברי הצוות, עד 2 מיילים בשעה. אי אפשר לשלוח קוד אימות לשחקנים.
- **אפשרות חינמית:**
  - ספק עם שכבה חינמית, למשל Resend (‏3,000 מיילים בחודש) או Brevo (‏300 ביום).
  - דורש יצירת חשבון ואימות דומיין (רשומות DNS ל-`oyaholding.com`). את זה אתה צריך לעשות. לא יצרתי חשבונות.
- **עד אז:** מסך Cloud Backup מציג הודעה ש-"Cloud Backup is temporarily unavailable" במקום טופס ההרשמה. "Sign in" נשאר (לא דורש שליחת מייל).
- **הפעלה:**
  1. להגדיר SMTP בדשבורד (Auth → SMTP).
  2. `PUSH_EMAIL_TEMPLATES=1 ./scripts/push-auth-config.sh`
  3. לבדוק קוד אמיתי לתיבה חיצונית.
  4. `PT_EMAIL_OTP_ENABLED: "YES"` ב-`project.yml`, ו-build חדש.
- **ללא שינוי:** מחיקת חשבון (Edge Function, ‏tombstone) ושחזור session מה-Keychain עובדים. כרגע אין שחזור חשבון במכשיר חדש, כמו ב-Firebase האנונימי.

## 6. TestFlight: התקנה ובדיקות
**שלב 0: לפני העלאה [ידני]**
- להגביל את מפתח Firebase (§4) ולהריץ `./scripts/security/probe-firebase-key.sh`.
- לייבא שוב (§3.2).
- לוודא ב-App Store Connect שהגרסה האחרונה היא 1.0.2 ושלא הועלה build גבוה מ-1.

**שלב 1: Internal Testing בלבד.** לא External ולא Public Link בלי אישורך.

**תרחישים:**
| # | תרחיש | צפוי |
|---|---|---|
| 1 | **שדרוג:** מכשיר עם 1.0.2 מהחנות ← התקנת TestFlight 1.1.0 | אותו שם, מטבעות, רמה, פריטים ושיאים. בלוג: `legacy claim: claimed` |
| 2 | מכשיר נקי (התקנה ראשונה) | שחקן אנונימי חדש ומסך בחירת שם |
| 3 | הפעלה שנייה אחרי שדרוג | בלי claim נוסף (`already_claimed` או דילוג), בלי כפילות שחקן |
| 4 | Classic, ‏Timed, ‏Sudden, ‏Endless, ‏Combo Frenzy | ניקוד נשמר; שיא מאומת בלוח המובילים |
| 5 | Duel בין 2 מכשירים, כולל הזמנה מחבר | "joined" בזמן אמת, תוצאה פעם אחת |
| 6 | מצב טיסה באמצע דו-קרב, ואחר כך חזרה | ניקוד ממתין נשלח מהבית (`PendingDuelStore`) |
| 7 | פרסומת interstitial ו-rewarded (revive, שבוע עונה) | מוצגת; revive רק אחרי צפייה מלאה |
| 8 | רכישת IAP ב-Sandbox ו-Restore Purchases | `no_ads` נשמר ושורד התקנה מחדש |
| 9 | Cloud Backup | הודעת "temporarily unavailable"; אין טופס הרשמה |
| 10 | Settings ← Privacy / Terms / Support | נפתחים עמודי GitHub Pages |
| 11 | Delete Account | נמחק בשרת; בהפעלה הבאה שחקן חדש; ה-claim לא משחזר את הישן |
| 12 | חזרה ל-1.0.2 מהחנות אחרי בדיקה | עובד מול Firebase, אבל **בלי** ההתקדמות שנצברה ב-1.1.0 (§8) |

## 7. ניטור
- **Supabase Dashboard:**
  - Reports: Auth, ‏API ו-Realtime connections (סף Free: ‏200 במקביל).
  - Logs Explorer: שגיאות 4xx/5xx.
  - Edge Function logs: `claim-legacy-account`, ‏`delete-account`.
- **בדיקות SQL יומיות** בשבוע הראשון (SQL Editor):
  ```sql
  select (select count(*) from private.legacy_claims) claims,
         (select count(*) from legacy.players) legacy_players,
         (select count(*) from auth.users) users,
         (select count(*) from public.profiles where username = '') no_username;
  -- claims כפולים אינם אפשריים (PK + unique), אבל לוודא:
  select user_id, count(*) from private.legacy_claims group by 1 having count(*) > 1;
  ```
- **קריסות:** Xcode Organizer → Crashes ו-TestFlight Feedback. אין Crashlytics באפליקציה.
- **שגיאות Auth:** Supabase → Auth logs. ספייק של `over_request_rate_limit` = מגבלת 30 כניסות אנונימיות לשעה לכל IP.
- **השהיה:** פרויקט Free מושהה אחרי 7 ימים בלי פעילות. בזמן הבדיקות צריך לפתוח אותו לפחות פעם בשבוע.

## 8. Rollback: מה אפשר ומה לא
- **אפשר:** להחזיר `PT_BACKEND: firebase` ב-Release ולשחרר build חדש. ‏`FirebaseService` לא נמחק, ו-Firebase לא שונה.
- **לא אפשרי ב-flag בלבד:**
  - **כל מה ששחקן כתב ל-Supabase אחרי השדרוג לא חוזר ל-Firestore.** מטבעות, רמות, שיאים, חברויות ודו-קרבות חדשים.
  - חזרה ל-Firebase תחזיר אותו למצב שלפני השדרוג.
  - שחקן חדש שנוצר ב-Supabase לא קיים ב-Firebase בכלל.
  - אם יידרש, צריך לכתוב ולבדוק סקריפט export הפוך לפני Rollback. הסקריפט עדיין לא קיים.
- **החלון:** ב-TestFlight בלבד, Rollback כמעט חסר עלות (רק בודקים). אחרי שחרור לחנות, העלות גדלה עם כל יום.
- **קריטריונים ל-Rollback / עצירה:**
  - שיעור קריסה גבוה משמעותית מ-1.0.2.
  - claim שנכשל או מאבד התקדמות אצל בודק כלשהו.
  - שגיאות `save_profile` חוזרות.
  - Realtime או דו-קרב לא אמינים.
  - מגבלות Free נחצות.
- **Phased Release:** ב-App Store להפעיל שחרור הדרגתי (7 ימים). אפשר לעצור אותו (Pause) בלי build חדש.

## 9. תנאים לפרישת Firebase (לא לפני)
1. 1.1.0 או גרסה חדשה ממנה היא הגרסה היחידה שמותקנת בפועל. אפשר לכפות עדכון רק בגרסה עתידית (מנגנון minimum-version), כי ל-1.0.x אין מנגנון כזה.
2. ייבוא אחרון אחרי שלא נרשמה כתיבה חדשה ל-Firestore במשך 30 יום (`updateTime` מקסימלי).
3. אין לוגים של claim חדש במשך 30 יום.
4. SMTP פעיל ונבדק, כדי שלשחקנים תהיה דרך לשחזר חשבון.
5. רק אז: כללי `deny` ל-Firestore. הסרת FirebaseAuth, ‏Firestore ו-Functions מהאפליקציה רק אחרי זה, כי הסרת FirebaseAuth משביתה את ה-claim.
6. **לא למחוק** את פרויקט Firebase או Google Cloud. Analytics נשאר.

## 9א. שאלת מוצר פתוחה (לא שיניתי)
- **Focus** מקבל 3 חיים ו-revive, כברירת המחדל של `GameMode.initialLives`, אבל ה-HUD שלו מוסתר. השחקן לא רואה כמה חיים נשארו, והמשחק נגמר בהפתעה.
- בדיקת ה-UI נכתבה בהנחה ש-Focus חופשי מכישלון, כמו Zen.
- **צריך להחליט:**
  - (א) Focus בלי חיים, כמו Zen; או
  - (ב) להציג מחוון חיים מינימלי.
- זה שינוי גיימפליי, ולכן לא ביצעתי אותו.

## 9ב. סדר השחרור הסופי (נוסף 13.11.2026)
ההגדרות ב-App Store Connect כבר מוכנות: גרסה 1.1.0 עם **Release: Manual** ו-**Phased Release** (7 ימים, `INACTIVE`).
אישור של Apple **לא** משחרר את הגרסה אוטומטית.

| # | שלב | מי |
|---|---|---|
| 1 | אחרי Approved: ייצוא Firestore טרי (`scripts/migration/export-firestore.mjs`) וייבוא חוזר (`EXPECTED_REF=pgvtaotdyspwnpqtxpju ./import-legacy.sh`). ‏`ingest` מעדכן רק שחקנים שעוד לא עברו | 👤 אישור (כתיבה ל-DB בענן) |
| 2 | בדיקת SQL מסעיף 7, לפני ואחרי | בודק |
| 3 | App Store Connect → 1.1.0 → **Release This Version** (מתחיל phased release) | 👤 |
| 4 | יום 1–7: ניטור לפי סעיף 7, ‏`bundle exec fastlane asc_check` (סטטוס), Xcode Organizer → Crashes | בודק |
| 5 | בעיה לפי קריטריוני סעיף 8 → **Pause Phased Release** (אין צורך ב-build חדש), ואז תיקון ב-build חדש | 👤 |
| 6 | שבועיים-שלושה אחרי: ייבוא חוזר נוסף. Firebase נשאר פעיל לפי סעיף 9 | 👤 אישור |

**ניטור הסכמה:** אין טלמטריה ל-UMP/ATT באפליקציה (בכוונה, בלי SDK נוסף).
סימנים לבעיה: ירידה חדה בהכנסות AdMob באזור EEA (טופס UMP לא פורסם, ראו `RELEASE_1.1.0_READINESS.he.md`),
או דיווחי TestFlight / ביקורות על בקשת מעקב חוזרת.

## 10. עלויות
‎$0. ‏Supabase Free, ‏Firebase Spark (חיוב כבוי), ‏GitHub Pages ו-Actions ב-repo ציבורי. לא הופעל אף שירות בתשלום.
