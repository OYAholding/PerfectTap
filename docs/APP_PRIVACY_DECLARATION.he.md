# PerfectTap — הצהרת App Privacy (שאלון ב-App Store Connect)

> **סטטוס: פורסם ונבדק (13.11.2026, באישור הבעלים).** ‏11 סוגי מידע. Tracking רק ל-Device ID.
> Not Linked רק ל-Diagnostics. דף החנות הציבורי כבר מציג את התווית החדשה.
> **נמצא ותוקן בזמן הפרסום:** כשמוסיפים מטרות לסוג קיים, App Store Connect שומר את שאלת ה-Linked
> לכל מטרה בנפרד. ה-Product Interaction נשמר בהתחלה גם כ-"Not Linked", ותוקן ל-Linked.

## איפה ממלאים
App Store Connect → PerfectTap → **App Privacy** → Edit. השאלון הוא **לכל האפליקציה**, לא לגרסה מסוימת.
הוא מתעדכן בחנות מיד עם **Publish**, ולכן הוא חייב להיות נכון גם ל-1.0 החיה וגם ל-1.1.0.

## מה מופיע היום (נקרא ב-App Store Connect, 13.11.2026)
פורסם לפני 7 חודשים. 5 סוגים:
- **Name:** App Functionality, ‏Linked
- **Email Address:** App Functionality, ‏Linked
- **Device ID:** Third-Party Advertising + Analytics, ‏Linked, **Tracking**
- **Product Interaction:** Analytics, ‏Linked
- **Advertising Data:** Third-Party Advertising + Analytics, ‏Linked

**חסר**, גם ל-1.0 (שכבר כוללת AdMob ו-Firebase): ‏User ID, ‏Gameplay Content, ‏Coarse Location, ‏Diagnostics.
ב-Product Interaction חסרות המטרות Third-Party Advertising ו-App Functionality.
**שים לב:** ב-App Store Connect שמירת השינויים בסוגי המידע נגמרת בכפתור **Publish**, בלי שלב טיוטה.
לכן לא ביצעתי שינוי.

## האם האפליקציה מבצעת Tracking?
**כן, ב-1.1.0 רק אחרי אישור ATT.** כש-ATT מאושר, ‏Google Mobile Ads משתמש ב-IDFA למודעות מותאמות ולמדידה בין אפליקציות.
ה-manifest של Google מסמן את Device ID כ-tracking. התווית "Identifiers — Used to Track" **נכונה ונשארת**.
ב-1.0 לא הייתה בקשת ATT, ולכן iOS לא חשף שם את ה-IDFA (אפסים). זו בדיוק הסתירה שבגללה Apple דחתה את 1.01.

## התשובות הסופיות
| קטגוריה → סוג | Purposes | Linked | Tracking | מקור |
|---|---|---|---|---|
| Contact Info → **Name** | App Functionality | Yes | No | **להשאיר** (כבר מוצהר). שם המשתמש במשחק עשוי להיחשב שם |
| Identifiers → **Device ID** | Third-Party Advertising, Analytics | Yes | **Yes** | IDFA אחרי ATT, ‏IDFV. ‏AdMob ו-Firebase Analytics |
| Identifiers → **User ID** | App Functionality | Yes | No | מזהה חשבון ב-Supabase (ב-1.0: ‏Firebase UID) |
| Contact Info → **Email Address** | App Functionality | Yes | No | חשבונות אימייל ישנים (Firebase) שעוברים ב-claim. ‏Cloud Backup (כבוי כרגע) |
| User Content → **Gameplay Content** | App Functionality | Yes | No | שם משתמש, ניקוד, חברים, דו-קרבות, לוחות תוצאות |
| Location → **Coarse Location** | Third-Party Advertising, Analytics, App Functionality | Yes | No | נגזר מ-IP ב-AdMob. ‏UMP קובע לפיו אזור (App Functionality) |
| Usage Data → **Product Interaction** | Analytics, Third-Party Advertising, App Functionality | Yes | No | אירועי Firebase Analytics, ‏AdMob ו-UMP |
| Usage Data → **Advertising Data** | Third-Party Advertising, Analytics | Yes | No | חשיפות ולחיצות על מודעות (AdMob) |
| Diagnostics → **Crash Data** | Analytics | No | No | AdMob |
| Diagnostics → **Performance Data** | Analytics, Third-Party Advertising, App Functionality | No | No | AdMob ו-UMP |
| Diagnostics → **Other Diagnostic Data** | Analytics, Third-Party Advertising | No | No | AdMob |

**לא לסמן:**
- **Purchases:** אין IAP ב-App Store Connect, וה-UI כבוי.
- **Precise Location**, ‏**Health**, ‏**Financial**, ‏**Contacts**, ‏**Photos**, ‏**Audio**, ‏**Browsing / Search History**, ‏**Sensitive Info**: לא נאספים.
- **Push / Messaging:** ‏FirebaseMessaging הוסר ב-1.1.0. ב-1.0 הוא היה מקושר בלי הרשאת push, ולא מצאתי בו איסוף מידע שדורש הצהרה נפרדת.

## למה "Linked = Yes" במידע של Google
Apple מאחדת את כל ה-privacy manifests שבתוך ה-build. ה-manifest של Google Mobile Ads מסמן Device ID, ‏Coarse Location, ‏Product Interaction ו-Advertising Data כ-linked.
הצהרה שמרנית (Linked) לא תיצור סתירה מול ה-privacy report של Apple. הצהרה מקלה עלולה.

## אחרי Publish (בדיקה)
1. בדף החנות: "Data Used to Track You" = **Identifiers** בלבד.
2. "Data Linked to You": ‏Contact Info (Name, Email), ‏Identifiers, ‏Location, ‏User Content, ‏Usage Data.
3. "Data Not Linked to You": ‏Diagnostics.
4. Privacy Policy URL: ‏`https://oyaholding.github.io/PerfectTap/` (‏HTTP 200).

**אומת שוב ב-14.11.2026** בדף ה-App Store הציבורי (us): כל ארבעת הסעיפים תואמים. Track = Identifiers. ‏Not Linked = Diagnostics בלבד.

## AdMob: הודעת GDPR (13.11.2026)
- **פורסמה (13.11.2026, באישור הבעלים) ונבדקה באפליקציה:** "PerfectTap - GDPR consent (EEA, UK, CH)".
- **אפליקציה:** PerfectTap! בלבד (iOS, ‏6760975737). ‏Privacy URL: ‏`https://oyaholding.github.io/PerfectTap/`.
- **כפתורים:** Consent, ‏**Do not consent** (פעיל בכל 34 האזורים), ‏Manage options.
- **שותפי פרסום:** ברירת המחדל של Google.
- **נבדק ב-iPad Air 11 M3**, עם debug geography = EEA (`-PTUMPDebugEEA`, ‏DEBUG בלבד):
  - הטופס מופיע ראשון, ואחריו בקשת ATT.
  - אחרי Do not consent + Ask App Not to Track המשחק עובד.
  - Settings → Privacy מציג Ad Tracking: Not allowed ו-**Privacy Choices**, שפותח את הטופס מחדש (ביטול הסכמה).
- **אומת שוב ב-14.11.2026:** סטטוס "פורסמה", המתג פעיל, הודעה אחת פעילה (2 הצגות, שתיהן מבדיקות הסימולטור).
- 🧪 לא נבדק במכשיר אמיתי באזור EEA.
