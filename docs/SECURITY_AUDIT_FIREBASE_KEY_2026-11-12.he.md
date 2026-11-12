# ביקורת אבטחה: Google API Key ב-`GoogleService-Info.plist` (12.11.2026)

התראה: GitHub Secret Scanning ‏#1. ‏`secret_type: google_api_key`, ‏`validity: unknown`, ‏`publicly_leaked: true`.

**מיקומים:**
- `PerfectTap/GoogleService-Info.plist` שורה 10, קומיט `c13d190` (Baseline).
- `ios/PerfectTap/GoogleService-Info.plist` שורה 10, קומיט `0f898b6` (אחרי הסידור מחדש).

סימון: **[נבדק]** = נבדק בפועל בבקשה או בכלי. **[ידני]** = צריך לבדוק או לשנות ב-Google Cloud Console (אין לי גישה ל-gcloud).

## 1. האם זה מפתח פרטי או ציבורי? ציבורי. [נבדק]
- **אותו מפתח בכל המקומות:** זה מפתח הלקוח של אפליקציית ה-iOS היחידה בפרויקט `perfecttap-48a08`. אותו ערך מופיע בשלושת העותקים של הקובץ.
  - App ID: ‏`1:826871089938:ios:75a28d391b2b99b17bc1cb`
  - Bundle: ‏`com.perfecttap.app`
  - ‏apiKeyId: ‏`ef41005e-ed6c-4480-af06-948e739888d8`
- **הוא כבר מופץ:** המפתח נמצא בכל עותק מותקן של האפליקציה (בתוך ה-IPA), ולכן היה ציבורי עוד לפני ה-repo.
- **לפי Firebase:** מפתחות כאלה הם *"Public by design"*, ולא צריך להתייחס אליהם כסוד כשהם מוגבלים לשירותי Firebase. הגישה לנתונים נשלטת על ידי Security Rules ו-App Check, לא על ידי המפתח.
- **זה לא credential בעל הרשאות:**
  - המפתח לא מעניק גישת admin.
  - בלי משתמש מחובר, Firestore מחזיר `Missing or insufficient permissions`. **[נבדק]**
  - בקוד אין service account, ולא נמצא אף סוד אחר. **[נבדק בסריקת gitleaks]**

## 2. ההגבלות הנוכחיות של המפתח [נבדק בהתנהגות]
| בדיקה | תוצאה | מסקנה |
|---|---|---|
| Identity Toolkit בלי bundle header | עובד | **אין הגבלת אפליקציה (Application restriction)** |
| Identity Toolkit עם `com.example.other` | עובד | המפתח לא קשור ל-Bundle ID |
| Gemini (Generative Language) | `API_KEY_SERVICE_BLOCKED` | **יש הגבלת API ברמת המפתח**, ככל הנראה רשימת ה-Firebase APIs שמוגדרת אוטומטית |
| Maps, ‏Translation, ‏YouTube | ה-API כבוי בפרויקט | אין שימוש בתשלום דרך המפתח |
| Firestore בלי token | נדחה על ידי ה-rules | הנתונים מוגנים על ידי ה-rules |
| `createAuthUri` | לא מחזיר `registered` | הגנה מפני email enumeration פעילה |

- **חיוב:** בפרויקט Firebase הוא **מבוטל** (תוכנית Spark). שימוש לרעה יכול לכל היותר למצות מכסות חינמיות (DoS), **לא ליצור חיוב**. **[נבדק]**
- **מה לא היה אפשר לאמת:** את רשימת ה-APIs המדויקת שמותרת במפתח. צריך לבדוק ידנית (סעיף 6).

## 3. Security Rules, ‏App Check ושימוש לרעה במכסות
- **Firestore rules שפרוסים:** זו הגרסה המוקשחת מנובמבר 2026. ברירת המחדל היא `deny` לכל השאר. אין Storage, אין Realtime Database, ואין Cloud Functions פרוסות. **[נבדק]**
- **הסיכון העיקרי (לא המפתח עצמו):** ב-`players` יש `allow read: if signedIn()`.
  - כל אחד יכול להתחבר אנונימית עם המפתח הציבורי ולקרוא את כל מסמכי השחקנים: מטבעות, קודי חברים, משימות.
  - כך הוא יכול גם למצות את מכסת הקריאות החינמית: ‏50K קריאות ביום ב-Spark.
  - **אי אפשר להחמיר את הכלל בלי לשבור גרסאות מותקנות:** לוח המובילים, חיפוש לפי קוד חבר ובדיקת ייחודיות של שם המשתמש מסתמכים עליו.
  - **הפתרון כבר קיים ב-Supabase:** שם הפרופיל מפוצל לחלק ציבורי ולחלק פרטי, וכל כתיבה עוברת ב-RPC עם rate limits. לכן ה-cutover הוא התיקון האמיתי.
- **App Check:** לא משולב באפליקציה (אין `FirebaseAppCheck` ב-`project.yml`).
  - **אסור להפעיל Enforcement.** כל הגרסאות המותקנות יפסיקו לעבוד מול Auth ו-Firestore.
  - בגלל המעבר ל-Supabase, לא מומלץ להשקיע בשילוב App Check ל-Firebase.
- **הגבלת אפליקציה לפי Bundle ID:** מבוססת על ה-header ‏`X-Ios-Bundle-Identifier`, שתוקף יכול לזייף. היא מונעת שימוש חוזר מזדמן במפתח, לא תוקף נחוש. לכן היא שכבת הגנה נוספת, לא פתרון.

## 4. האם ההגבלות המוצעות ישברו משהו?
| רכיב | הגבלת אפליקציה `iOS: com.perfecttap.app` | הגבלת API לרשימת Firebase |
|---|---|---|
| גרסאות מותקנות של האפליקציה (Release על Firebase) | ✅ ה-SDK שולח את ה-Bundle ID אוטומטית, וכל הגרסאות הן `com.perfecttap.app` | ✅ צריך Identity Toolkit, ‏Token Service, ‏Cloud Firestore, ‏Firebase Installations ו-FCM Registration (‏`FirebaseMessaging` מקושר באפליקציה) |
| Edge Function ‏`claim-legacy-account` (מעבר ל-Supabase) | ✅ שולחת `X-Ios-Bundle-Identifier: com.perfecttap.app` (נוסף מראש לשם כך) | ✅ משתמשת רק ב-Identity Toolkit |
| אימות token של Firebase ב-Edge Function | ✅ לא משתמש במפתח: JWKS ציבורי של Google | ✅ |
| Firebase CLI, ‏MCP, ‏emulators, בדיקות | ✅ לא משתמשים במפתח הזה | ✅ |
| Firebase Analytics | ✅ | ✅ עובד דרך Firebase Installations |

**אסור:**
- ❌ **למחוק או לסובב (rotate) את המפתח.** הוא מוטמע בגרסאות המותקנות, ומחיקה בלתי הפיכה תשבית מיד את ההתחברות ואת Firestore בכל הגרסאות. גם את ה-claim ל-Supabase.
- ❌ להוסיף את Gemini או כל API בתשלום לרשימת ה-APIs של המפתח.
- ❌ להפעיל App Check Enforcement.

## 5. מה לעשות ב-Google Cloud Console [ידני]
1. https://console.cloud.google.com/apis/credentials?project=perfecttap-48a08
   - לוודא שזה הפרויקט `perfecttap-48a08`, ולא פרויקט של Corelim.
2. לפתוח את המפתח שה-ID שלו `ef41005e-ed6c-4480-af06-948e739888d8`. בדרך כלל השם שלו "iOS key (auto created by Firebase)".
   - לוודא שהערך המוצג זהה ל-`API_KEY` ב-`GoogleService-Info.plist`.
3. **Application restrictions:**
   - לבחור **iOS apps**, ולהוסיף **`com.perfecttap.app`** בלבד.
   - **לפני השמירה** לוודא שאין עוד אפליקציה או אתר שמשתמשים במפתח הזה. לפי הבדיקה, אין.
4. **API restrictions:** לוודא שמסומן **Restrict key**, ושמותרים לפחות:
   - Identity Toolkit API
   - Token Service API
   - Cloud Firestore API
   - Firebase Installations API
   - FCM Registration API
   - Firebase App Check API (לא חובה; כלול ברשימת ברירת המחדל של Firebase)

   אם יש עוד APIs מרשימת ברירת המחדל של Firebase, אפשר להשאיר אותם. אסור שיופיעו Generative Language / Gemini, ‏Maps או כל API בתשלום.
5. **Save.** השינוי נכנס לתוקף תוך דקות.
6. **אימות:** `./scripts/security/probe-firebase-key.sh`. התוצאה הצפויה:

   | בדיקה | צפוי |
   |---|---|
   | בלי header | `BLOCKED` |
   | `com.perfecttap.app` | `OK` |
   | Bundle אחר | `BLOCKED` |
   | Gemini | `BLOCKED` |

   אחר כך: להפעיל בסימולטור build ‏Release (Firebase), ולוודא כניסה ושמירת פרופיל.
7. **Firebase Console → Authentication → Settings:**
   - לבדוק את **User account management / Sign-up quota** (מכסת הרשמות לכל IP), ולהשאיר אותה נמוכה.
   - לוודא ש-**Email enumeration protection** פעיל. כרגע הוא פעיל.
8. **להשאיר את החיוב כבוי** (Spark). אם בעתיד עוברים ל-Blaze, צריך להגדיר Budget alert.

**Rollback להגבלת האפליקציה:** לחזור ל-Application restrictions → **None**. אין לזה השפעה על הנתונים.

## 6. סגירת ההתראה ב-GitHub
**רק אחרי שסעיף 5 בוצע והבדיקה עברה:**
- **בממשק:** https://github.com/OYAholding/PerfectTap/security/secret-scanning/1 → **Close as → "Won't fix"**, עם ההערה:
  > Public Firebase iOS client API key (by design, embedded in the shipped app). Restricted to iOS bundle com.perfecttap.app and Firebase APIs; data protected by Firestore Security Rules; billing disabled. Not rotated: rotation would break installed app versions. Verified 2026-11-12 with scripts/security/probe-firebase-key.sh.
- **או ב-CLI:**
  ```bash
  gh api -X PATCH repos/OYAholding/PerfectTap/secret-scanning/alerts/1 -f state=resolved -f resolution=wont_fix -f resolution_comment="Public Firebase iOS client key; restricted to com.perfecttap.app + Firebase APIs; rules enforced; billing off. See docs/SECURITY_AUDIT_FIREBASE_KEY_2026-11-12.he.md"
  ```

**לא לבחור "Revoked":** המפתח לא בוטל, והסימון יהיה מטעה. **לא לבחור "False positive":** זה באמת מפתח Google API, רק שהוא ציבורי בכוונה.

**לא לשכתב היסטוריה כדי להסתיר את המפתח:**
- המפתח כבר ציבורי באפליקציה עצמה. GitHub מסמן `publicly_leaked`.
- שכתוב היה דורש force-push, ולא מחזיר שום סודיות.

## 7. סיכום הפעולות
| עדיפות | פעולה | מי |
|---|---|---|
| 1 | הגבלת אפליקציה `iOS: com.perfecttap.app` והגבלת API לרשימת Firebase (סעיף 5) | אתה, ב-Google Cloud Console |
| 2 | הרצת `probe-firebase-key.sh`, ובדיקת build ‏Release בסימולטור | אתה או אני, אחרי השינוי |
| 3 | סגירת ההתראה כ-"Won't fix" עם הערה | אתה |
| 4 | בדיקת מכסת ההרשמות ב-Firebase Auth | אתה |
| 5 | Cutover ל-Supabase: הוא סוגר את קריאת כל מסמכי `players` | לפי `docs/SUPABASE_MIGRATION.he.md` |
