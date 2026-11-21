# פרוטוקול מדידת ביצועים על iPhone פיזי — PerfectTap

מטרה: לאשר (או להפריך) על מכשיר אמיתי את סיבות התקיעות שזוהו בקוד ואת שיפור 1.1.1.
הסימולטור רץ על מעבד ה-Mac ולכן **אינו** מוכיח שיעור hitch על iPhone. מדידות הסימולטור
(`docs/perf/*.json`) מראות עלות יחסית בלבד.

## מה צריך
- iPhone פיזי (עדיף שניים: אחד ישן כמו iPhone 11/12/SE 2/3, ואחד ProMotion 120Hz כמו iPhone 15 Pro ומעלה).
- Xcode 26 עם Instruments, כבל או רשת מקומית.
- שני בילדים מאותו מחשב: `1.1.0 (4)` (ענף `main`) ו-`1.1.1` (ענף `hotfix/1.1.1-stability`), בתצורת **Release** (Product › Profile).
- AirPods או אוזניות Bluetooth (לתרחיש 5).

## תבניות Instruments
| תבנית | מה מחפשים |
|---|---|
| **Animation Hitches** | Hitch time ratio (ms/s), hitches בודדים > 33ms בזמן משחק |
| **Hangs** (Time Profiler + Hangs) | כל Hang ≥ 250ms ובמיוחד במעבר סוף-סבב → Game Over |
| **Time Profiler** | ערימות קריאה במסגרות הארוכות: `finalizeAndReport`, `PlayerProfile.load/save`, `SoundEngine.scheduleMusicLoop`, `AVAudioPlayerNode.stop`, `HomeView.onAppear`, `GADMobileAds` |
| **os_signpost / Points of Interest** | המרווחים של subsystem `com.perfecttap.perf`: `game.finish`, `nav.roundEndToGameOver`, `audio.musicSchedule`, `audio.stopMusic`, `audio.engineSetup`, `haptics.setup`, `game.viewBootstrap` |
| **Allocations** | צמיחת זיכרון אחרי 10 סבבים רצופים (persistent bytes) |

## תרחישים (לכל בילד, אותו סדר, 3 חזרות)
1. **הפעלה קרה → משחק ראשון:** הרגו את האפליקציה, פתחו, PLAY › CLASSIC. מדדו את ההשהיה עד ה-3 הראשון ואת המסגרת הראשונה אחרי GO (הנעה ראשונה של מנוע הקול וההפטיקה).
2. **Classic ×3 עם PLAY AGAIN:** שחקו עד הפסד, PLAY AGAIN, שוב פעמיים. מדדו `nav.roundEndToGameOver` ו-Hangs בסוף כל סבב.
3. **Timed 60 שניות עם מוזיקה פועלת:** הקישו בקצב קבוע. חפשו hitch מחזורי כל ~10.7 שניות (`audio.musicSchedule`).
4. **Revive עם פרסומת אמיתית (TestFlight בלבד):** הפסידו ב-Classic, WATCH AD, סגרו את הפרסומת, המשיכו. בדקו שהמשחק לא נתקע ושהספירה 3-2-1 חלקה.
5. **חיבור AirPods באמצע משחק:** חברו/נתקו את האוזניות בזמן Endless. ההקשה הבאה לא אמורה להיתקע (`audio.engineStart`).
6. **רקע/חזית:** באמצע Endless החליקו מהפינה (Control Center), חזרו; ואז Home וחזרה. ודאו שהמשחק ממשיך (ספירה 3-2-1) ולא קפא.
7. **אופליין:** מצב טיסה, סבב Classic מלא, חזרה למצב רגיל. ודאו שאין תקיעה בסוף הסבב.
8. **10 סבבים רצופים** (Allocations): זיכרון יציב.

## מה לרשום (טבלה לדוח)
| תרחיש | בילד | Hitch ratio (ms/s) | Hitches > 100ms | Hang מקסימלי | `game.finish` (ms) | `nav.roundEndToGameOver` (ms) | `audio.musicSchedule` (ms) | זיכרון אחרי 10 סבבים |
|---|---|---|---|---|---|---|---|---|

## קריטריון קבלה ל-1.1.1
- אין Hang ≥ 250ms באף תרחיש.
- `nav.roundEndToGameOver` חציוני < 150ms על המכשיר הישן.
- אין hitch מחזורי סביב 10.7 שניות ב-Timed.
- תרחיש 4 ו-6: המשחק תמיד ממשיך, אף פעם לא נשאר מסך קפוא.

## הרצה חוזרת בסימולטור (אוטומטית)
```bash
PT_SIM_UDID=<udid> scripts/perf-run.sh <label>
```
הסקריפט מוחק את האפליקציה, מריץ `GameplayPerformanceTests` עם `-PTPerfProbe -PTUITestNoAds -PTUITestOfflineBackend`
(בלי רשת, בלי פרסומות, בלי כתיבה ל-Supabase האמיתי) ושומר `docs/perf/<label>.json`.
