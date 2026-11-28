# PerfectTap 1.2.0: נוהל בדיקה על מכשיר פיזי

הסימולטור עבר את מבחן הביצועים 3/3 ב-28.11 (`docs/perf/qa-1.2.0-idle-iphone16pro-run*.json`). זו ראיה ברמת סימולטור בלבד, ולכן הנוהל הזה סוגר את G9/G10 על חומרה אמיתית. הנוהל מאחד שלושה מסמכים קיימים ומפנה אליהם: `docs/perf/DEVICE_PROFILING_PROTOCOL.he.md`, ‏`docs/STOREKIT_DEVICE_SANDBOX_QA.he.md` ו-`docs/OWNER_CHECKLIST_1.2.0.he.md` (פרק ה׳).

## 0. ציוד ובילדים

| פריט | פירוט |
|---|---|
| מכשירים | חובה iPhone אחד. מומלץ שניים: ישן (11/12/SE 2–3, ‏60Hz) ו-ProMotion (15 Pro ומעלה). iPad לבדיקת פריסה. |
| Mac | Xcode 26 עם Instruments. **אף build או בדיקת ביצועים אחרת לא רצה במקביל** (בלי סשנים אחרים ובלי Docker CI). |
| אודיו | AirPods או אוזניות Bluetooth, ואוזניות חוטיות אם יש. |
| בילד A: פרופיילינג | Xcode → Product → **Profile** בתצורת **Release** על המכשיר (חתימת פיתוח). הדגלים כמו ב-App Store: מכירות כבויות. |
| בילד B: Sandbox | **Release-IAP** מ-TestFlight פנימי (runbook שלב 10). דורש אישור העלאה. |
| בילד C: קוסמטיקה (אופציונלי, QA-02 של PR #15) | Debug מהענף `feature/modular-cosmetic-studio`, שבו `PT_COSMETIC_STUDIO_ENABLED=YES`. נמדד רק כדי להשוות, ולא נחשב ראיית שחרור. |

לפני כל מדידה: סוללה מעל 50%, בלי Low Power Mode, המכשיר לא חם, וכל האפליקציות האחרות סגורות. מריצים כל תרחיש 3 פעמים.

## 1. ביצועים עם Instruments (בילד A)

תבניות: **Animation Hitches**, ‏**Time Profiler + Hangs**, ‏**Allocations**, ו-**Points of Interest** (signposts של subsystem `com.perfecttap.perf`: ‏`game.finish`, ‏`nav.roundEndToGameOver`, ‏`audio.musicSchedule`, ‏`audio.stopMusic`, ‏`audio.engineSetup`, ‏`game.viewBootstrap`).

תרחישים 1–8 לפי `DEVICE_PROFILING_PROTOCOL.he.md`: הפעלה קרה, Classic ×3 עם PLAY AGAIN, ‏Timed 60s עם מוזיקה, revive (רק ב-TestFlight), ‏AirPods, רקע/חזית, אופליין, ו-10 סבבים רצופים.

נוסף ל-1.2.0:
- **9. מעבר עונה:** משנים את תאריך המכשיר לעונה הבאה (קדימה בלבד) ופותחים את האפליקציה. ההתקדמות העונתית מתאפסת, מטבעות ופריטים נשמרים, ואין Hang בטעינה.
- **10. כל 15 המצבים:** סבב אחד בכל מצב. בודקים שאין קריסה ושאין hitch מעל 250ms.

### קריטריון קבלה (זהה לספי `scripts/qa/perf-gate.py`)

| מדד | גבול | מקור |
|---|---|---|
| Hang | אף אחד ≥ 250ms | Hangs |
| פריימים ≥ 250ms במשחק | 0 | Animation Hitches |
| פריימים ≥ 100ms במשחק | עד 2 לכל סשן | Animation Hitches |
| Hitch ratio | מתחת ל-0.6% (בערך 6ms/s) | Animation Hitches |
| `nav.roundEndToGameOver` | ממוצע < 150ms, מקסימום < 250ms, **על המכשיר הישן** | Points of Interest |
| `game.viewBootstrap` | < 50ms | Points of Interest |
| זיכרון אחרי 10 סבבים | < 150MB, בלי צמיחה מתמשכת | Allocations |
| Hitch מחזורי סביב 10.7s ב-Timed | אין | Animation Hitches |

רושמים את הטבלה מ-`DEVICE_PROFILING_PROTOCOL.he.md` לכל מכשיר. שומרים את קובצי ה-`.trace` מחוץ ל-git (הם גדולים), ומעתיקים את המספרים ל-`docs/QA_1.2.0_MATRIX.md`.

## 2. StoreKit Sandbox (בילד B)

תנאי פתיחה:
- ההסכמים פעילים, ו-9 המוצרים נוצרו ב-ASC (שתי הפעולות דורשות אישור).
- המיגרציות וה-Edge Functions נפרסו.
- `iap_sales_control` פתוח **ל-Sandbox בלבד**, ו-Production סגור.
- נוצר Sandbox Tester, והמכשיר מחובר אליו ב-Settings → App Store → Sandbox Account.

מבצעים את 14 התרחישים ב-`STOREKIT_DEVICE_SANDBOX_QA.he.md`: אורח, non-consumable, ‏Restore, מטבעות לאורח, קישור Apple, ‏retry/duplicate, חשבון שגוי, מכשיר שני, Ask to Buy, ‏refund, ‏kill switch, שרת לא זמין, refund reversal ו-Production סגור.

ראיות לכל עסקה:
- `transactionId`
- צילום מסך של המחיר
- הפלט של `scripts/support/pt-support.sh purchase <transactionId>`: שורת ledger אחת, ואין זיכוי כפול
- לוג `verify-purchase` / `app-store-notifications`

בנוסף, אחרי refund של coin pack: היתרה יורדת עד אפס ולא נוצר חוב (`coin_debt` כבוי).

## 3. אודיו

הקוד: `SoundEngine` משתמש ב-`AVAudioSession` עם `.ambient` + `.mixWithOthers`, ומטפל ב-interruption וב-`AVAudioEngineConfigurationChange`.

| # | תרחיש | מצופה |
|---|---|---|
| A1 | מתג שקט מופעל | אין צלילי משחק (התנהגות `.ambient`), וההפטיקה עובדת |
| A2 | Spotify/Music מנגן ברקע, ואז משחק | המוזיקה החיצונית ממשיכה ומתערבבת עם צלילי המשחק, ולא נעצרת |
| A3 | חיבור וניתוק AirPods באמצע Endless | הצליל עובר להתקן החדש בלי קפיאה. ההקשה הבאה מגיבה (`audio.engineSetup` < 50ms) |
| A4 | שיחת טלפון או FaceTime נכנסת, ואז ניתוק | אחרי החזרה הצלילים חוזרים בלי להפעיל מחדש את האפליקציה |
| A5 | Siri באמצע סבב | כמו A4 |
| A6 | נעילת מסך באמצע סבב, ואז פתיחה | המשחק מושהה, מגיעה ספירת 3-2-1, והצליל חוזר |
| A7 | עוצמה מינימלית ומקסימלית | אין עיוות או clipping בצלילי perfect ו-miss |
| A8 | פרסומת revive עם צליל, ואז חזרה | צלילי המשחק חוזרים, והמוזיקה לא מנגנת פעמיים |
| A9 | 10 סבבים רצופים עם מוזיקה | אין הצטברות של nodes או צלילים כפולים, והזיכרון יציב |

עם בילד C בלבד: חוזרים על A1–A3 עם חבילות הצלילים Quack Attack, ‏Purrfect Tap ו-Boom Mode.

## 4. סיום

הבדיקה עוברת כשכל השורות בפרקים 1–3 עוברות על לפחות מכשיר אחד, ופרק 1 עובר על המכשיר הישן. מעדכנים את `docs/QA_1.2.0_MATRIX.md` ואת PR #14. כל כשל נפתח כממצא עם קובץ trace ותרחיש מדויק.
