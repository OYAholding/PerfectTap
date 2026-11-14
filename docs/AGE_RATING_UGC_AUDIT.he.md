# PerfectTap — דירוג גיל ו-UGC: שמות משתמש פומביים (עודכן 14.11.2026)

> **בוצע (14.11.2026, באישור הבעלים):** ‏`User-Generated Content = Yes`, ‏`Social Media = No`, ‏`Messaging and Chat = No`.
> הדירוג נשאר **4+** (נבדק ב-API). רק ב-appInfo של 1.1.0. ה-appInfo של 1.0 החיה לא השתנה.
> **Social Media:** לפי Apple זו הפצה של UGC דרך feed, עם לייקים, תגובות או שיתופים. אין דבר כזה באפליקציה.
> Apple דורשת לענות על השאלה הזו יחד עם UGC.
> **סינון ומודרציה פרוסים ב-Supabase** (מיגרציה `20261114120000`). עמוד ה-Support עם דרך הדיווח חי.
> **תיקון לגרסה הקודמת של המסמך:** המלצתי שם על No, ונימקתי בין השאר ב"פחות דרישות review". זה לא נימוק תקף.
> ההצהרה צריכה לשקף את מה שהאפליקציה עושה.

## 1. מה מוצהר היום (API, 14.11.2026)
| שדה | ערך |
|---|---|
| `userGeneratedContent` | ~~`false`~~ → **`true`** (14.11.2026) |
| `socialMedia` | ריק → **`false`** (14.11.2026) |
| `messagingAndChat` | `false` (נכון) |
| `advertising` | `true` (נכון) |
| כל תיאורי התוכן | `NONE` (נכון) |
| `appStoreAgeRating` | ‏**FOUR_PLUS** (לא ישתנה) |

## 2. ההגדרות של Apple
מקור: [Age ratings values and definitions](https://developer.apple.com/help/app-store-connect/reference/app-information/age-ratings-values-and-definitions/).
הניסוחים כאן הם תקציר.
- **User-Generated Content:** הפצה רחבה של תוכן שמשתמשים יצרו, כחלק מחוויית האפליקציה. לדוגמה: סרטונים, תמונות, טקסט או אודיו.
- **Messaging and Chat:** תקשורת ישירה בין משתמשים, כמו צ'אט, הודעות או פרסום פומבי.
- **השפעה על הדירוג:** שתיהן ממופות ל-4+.
- **[Guideline 1.2](https://developer.apple.com/app-store/review/guidelines/#user-generated-content):** אפליקציה עם UGC צריכה:
  - סינון תוכן פוגעני;
  - מנגנון דיווח ותגובה בזמן סביר;
  - חסימת משתמשים פוגעניים מהשירות;
  - פרטי קשר מפורסמים.
- Apple לא אומרת במפורש אם כינויים בלוח מובילים נחשבים UGC.

## 3. מה האפליקציה עושה
| יכולת | נמצא | ראיה |
|---|---|---|
| טקסט שהמשתמש בוחר וכל השחקנים רואים | **כן**: שם משתמש בלוח המובילים הגלובלי, אצל חברים ובדו-קרבות | ‏`leaderboard_scores` קריא לכל שחקן מחובר. ‏`get_leaderboard` מחזיר `username` |
| הגבלות | ‏2–20 תווים, ‏`[A-Za-z0-9_]`, ייחודי, קבוע | ‏`profiles` check, ‏`username_immutable` |
| טקסט חופשי נוסף, צ'אט או מדיה | **לא** | אין שדות כאלה. אווטרים מקטלוג קבוע |
| תקשורת ישירה | **לא** | בקשות חברות והזמנות הן פעולות בלי טקסט |

## 4. מסקנה
- שם משתמש הוא **טקסט שמשתמש יצר ושמוצג לכל השחקנים** בלוח מובילים גלובלי. זה תואם את ההגדרה "הפצה רחבה של תוכן שנוצר על ידי משתמשים" (טקסט).
- ההגבלה ל-20 תווים מצמצמת את הסיכון, אבל לא משנה את המהות. אפשר לכתוב מילה פוגענית שכל השחקנים יראו.
- **לכן: UGC = Yes.** אין צ'אט ואין תקשורת ישירה, לכן **Messaging = No**.

## 5. מה הוכן כדי לעמוד ב-1.2 (בצד השרת, בלי build חדש)
מיגרציה: ‏`20261114120000_jit_legacy_claim_and_username_moderation.sql`. נבדקה ב-stack המקומי, **ופרוסה בענן** (14.11.2026). בענן אין אף שם קיים שנחסם.

| דרישה | מימוש | נבדק |
|---|---|---|
| **סינון** | רשימת מונחים חסומים (`private.blocked_username_terms`) עם נרמול (‏`sh1t`, ‏`fuuuck`, ‏`B1TCH`) ושמות שמורים (admin, ‏support, ‏perfecttap…). <br>‏`is_username_available` מחזיר false, והאפליקציה הקיימת מציגה "That username is already taken". <br>שם חסום שמגיע בכל זאת (לקוח ישן או offline) מוחלף בשם ניטרלי `Player_xxxx`, **בלי לשבור סנכרון**. <br>שם חסום מ-Firebase ב-claim → השחקן מתבקש לבחור שם חדש | ✅ E2E |
| **דיווח** | **היום:** בעמוד Support נוסף "How do I report an offensive player name?": מייל, ותגובה תוך 48 שעות. <br>**מוכן ל-1.1.1:** ‏RPC ‏`report_player` (שומר דיווח פעם אחת לכל זוג, ‏rate limit) לכפתור Report באפליקציה | ✅ E2E |
| **חסימה / הסרה** | `private.moderate_username(user, reason)`, מ-SQL Editor בלבד. משנה את השם ל-`Player_xxxx` בכל מקום: פרופיל, לוח מובילים, דו-קרבות, הזמנות ובקשות. ההתקדמות נשמרת, ושמירות הבאות עם השם הישן לא נכשלות. נרשם ב-`private.moderation_log` | ✅ E2E |
| **פרטי קשר** | `PerfectTap@oyaholding.com` בעמוד Support ובאפליקציה (Settings → Support) | ✅ קיים |

**נבדק שאין false positives:** ‏Grapefruit, ‏class_pass, ‏Scott99, ‏Hancock ו-Therapist עוברים.

## 6. סיכון שנשאר
- אין כפתור Report **בתוך** האפליקציה. הדיווח היום הוא דרך Settings → Support (עמוד ה-Support) ובמייל.
- Apple עלולה לבקש מנגנון בתוך האפליקציה. אם זה יקרה: כפתור Report בשורת לוח המובילים שקורא ל-`report_player` (מוכן בשרת), ו-build 4.
- **ההמלצה שלי:** לא להעלות build 4 מראש. הסינון, ההסרה ופרטי הקשר פועלים בשרת, והתוכן מוגבל מאוד. את כפתור הדיווח להוסיף ב-1.1.1 בכל מקרה.

## 7. תפעול שוטף
- **דיווח במייל:** ב-SQL Editor, למצוא את המשתמש לפי השם:
  `select id from public.profiles where lower(username)=lower('<name>');`
  ואז: `select private.moderate_username('<id>', 'email report <date>');`
- **מונח חדש לחסימה:** `insert into private.blocked_username_terms (term, kind) values ('<term>', 'contains');`
- **דיווחים מהאפליקציה (1.1.1 והלאה):** `select * from private.player_reports where resolved_at is null;`
