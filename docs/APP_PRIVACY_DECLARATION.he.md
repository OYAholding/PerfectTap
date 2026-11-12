# PerfectTap — הצהרת App Privacy (שאלון ב-App Store Connect)

ה-API של App Store Connect **לא מאפשר** לקרוא או לעדכן את השאלון. ממלא אותו Account Holder / Admin / App Manager,
ב-App Store Connect → PerfectTap → **App Privacy** → Edit. השאלון לא נשמר עד ללחיצה על **Publish**.

המקור לטבלה: הקוד ב-1.1.0, ‏`PrivacyInfo.xcprivacy` של האפליקציה, וה-privacy manifests של Google Mobile Ads ‏(12.14) ו-UMP ‏(3.1), כפי שהם ב-build.
אם מוסיפים SDK או אוסף מידע חדש, צריך לעדכן גם את הטבלה וגם את השאלון.

## האם האפליקציה מבצעת Tracking?
**כן**, ורק אחרי אישור ATT. כש-ATT מאושר, ‏Google Mobile Ads משתמש ב-IDFA למודעות מותאמות אישית ולמדידה בין אפליקציות.
ה-manifest של Google מסמן את Device ID כ-"used for tracking". בלי אישור אין גישה ל-IDFA והמודעות לא מותאמות אישית.
כלומר ההצהרה "Device ID — used to track" **נכונה**. מה שחסר ב-1.01 היה בקשת ATT, וזה תוקן ב-1.1.0.

## מה לסמן
| קטגוריה → סוג | מטרות (Purposes) | Linked to user | Used for tracking |
|---|---|---|---|
| Identifiers → **Device ID** | Third-Party Advertising, Analytics | Yes | **Yes** |
| Identifiers → **User ID** | App Functionality | Yes | No |
| Contact Info → **Email Address** | App Functionality | Yes | No |
| User Content → **Gameplay Content** | App Functionality | Yes | No |
| Location → **Coarse Location** | Third-Party Advertising, Analytics | Yes | No |
| Usage Data → **Product Interaction** | Analytics, Third-Party Advertising | Yes | No |
| Usage Data → **Advertising Data** | Third-Party Advertising, Analytics | Yes | No |
| Diagnostics → **Crash Data** | Analytics | No | No |
| Diagnostics → **Performance Data** | Analytics, Third-Party Advertising | No | No |
| Diagnostics → **Other Diagnostic Data** | Analytics, Third-Party Advertising | No | No |

הערות:
- **Email Address:** רק אם Cloud Backup או חשבונות אימייל ישנים (Firebase) פעילים. ב-1.1.0 ‏`PT_EMAIL_OTP_ENABLED=NO`, אבל חשבונות ישנים עוברים דרך claim. לכן מסמנים.
- **Purchases:** לא לסמן. ‏IAP כבוי ב-UI ‏(`iapEnabled = false`), ואין מוצרים ב-App Store Connect.
- **Name:** לא לסמן. שם המשתמש במשחק הוא כינוי ונכנס תחת Gameplay Content.
- **Linked = Yes** אצל Google הוא ההגדרה של Google ב-manifest שלה. Apple מאחדת את כל ה-manifests, ולכן כדאי להתאים.

## אחרי השמירה
1. לבדוק שכרטיס "Data Used to Track You" מציג רק **Identifiers**.
2. Privacy Policy URL: ‏`https://oyaholding.github.io/PerfectTap/` (עודכן ב-1.01, ‏HTTP 200).
3. **Publish**. רק אז ההצהרה מעודכנת. לא לדווח "עודכן" לפני שבדקת שזה נשמר.
