# Freeze / Stutter — רשימת רגרסיה ונוהל אימות ביצועים (1.2.0)

**מטרה:** לוודא ש-1.2.0 (וכל ענף שממוזג אליו — כלכלה, StoreKit, חנות, סקינים) לא מחזיר את תקיעות 1.1.0 שתוקנו ב-1.1.1 (`a3ee906`).
**מקורות:** `docs/perf/RESULTS_1.1.1.he.md`, `docs/perf/DEVICE_PROFILING_PROTOCOL.he.md`, `docs/REPORT_1.1.1_1.2.0.he.md` §2.3, `git show a3ee906`.

## A. רשימת רגרסיה — לכל תיקון של 1.1.1, איך מוודאים שהוא עדיין שם

| # | תיקון 1.1.1 | קוד (read-only) | בדיקה אוטומטית | בדיקה ידנית / probe | סימן רגרסיה |
|---|---|---|---|---|---|
| F1 | מוזיקה: באפר לולאה אחד מרונדר מראש, כל עבודת `AVAudioEngine` על תור סדרתי | `Services/SoundEngine.swift` | — | probe: `audio.musicStart.main` max < 5ms; אין span `audio.musicSchedule` מחזורי | hitch כל ~10.7 ש׳ ב-Timed |
| F2 | הקמת מנוע קול בהפעלה, מחוץ ל-main | `PerfectTapApp.swift`, `SoundEngine` | — | probe: `audio.graphSetup.offMain` קיים (רץ off-main); אין stall ב-onAppear של משחק ראשון | stall 300ms+ בפתיחת המשחק הראשון |
| F3 | סוף סבב: `replaceStack` בפעולה אחת (בית לא נטען מחדש) | `Utils/AppRouter.swift`, `GameView`/`GameOverView` | `StabilityRegressionTests.testRoundEndReplacesStackWithoutExposingHome`, `testIsGameOnStack` | probe: `nav.roundEndToGameOver` avg < 150ms (1.2.0: 55–58ms) | Home מהבהב בסוף סבב; avg > 150ms |
| F4 | מטמון `PlayerProfile` בזיכרון | `Models/PlayerProfile.swift` | `testProfileCacheStaysInSyncWithSaveAndClear` | — | `game.finish` > 25ms |
| F5 | תוכן המשחק טעון מתחת לספירה + warm-up של סרגל ההקשה **ב-theme הנוכחי** | `GameView.swift`, `TapBarView.swift`, `PerfectTapApp.swift` | — | probe עם `PT_PERF_THEME=glitch`: אין stall ≥250ms ב-`countdown:*` | פריים 500–700ms ב-GO של סבב ראשון (עם/בלי סקין) |
| F6 | המשך סבב אחרי כיסוי מסך מלא (consent/ad) — 3-2-1 | `GameViewModel.swift` | `testGameResumesAfterViewReappearsWithStoppedClock` | ידני: פרסומת revive אמיתית (TestFlight) | מסך קפוא לצמיתות |
| F7 | UMP/ATT לא מוצגים באמצע סבב | `ConsentManager.swift` | `testConsentFlowDoesNotPromptWhileBlockedAndRetriesLater` | `TrackingConsentUITests` | טופס הסכמה מעל משחק רץ |
| F8 | טעינת פרסומות נדחית לסוף סבב | `AdManager.swift` | `testAdReloadIsDeferredWhileGameplayIsActive`, `testInterstitialReloadWaitsForNextRoundEnd`, `testRoundLifecycleDrivesAdGameplayFlag` | ידני TestFlight | hitch בתחילת סבב אחרי revive |
| F9 | `timeLeft` מתפרסם 1×/ש׳; רק האינדיקטור ב-60Hz | `GameViewModel`, `TapBarView` | `testTimedModePublishesTimeLeftOncePerDisplayedSecond` | probe: p99 = 16.7ms | p99 > 25ms |
| F10 | Mirror לא תלוי בקצב פריימים | `GameViewModel` | `testMirrorFlipProbabilityIsFrameRateIndependent` | ידני על ProMotion 120Hz | היפוכים כפולים ב-120Hz |
| F11 | `defersSystemGestures(.bottom)` | `GameView` | — | ידני: החלקה ליד TAP לא משהה | pause מקרי |
| F12 | ביטול רענון Home כשנכנסים למשחק | `HomeView.swift` | — | probe: אין stall `home` בתוך gameplay | stall בתחילת סבב |
| F13 | הפעלה מחדש של מנוע הקול אחרי החלפת route (AirPods) מחוץ למסלול ההקשה | `SoundEngine` (`AVAudioEngineConfigurationChange`) | — | ידני: חיבור/ניתוק AirPods באמצע Endless (תרחיש 5 בפרוטוקול) | ההקשה הבאה נתקעת / אין קול |
| F14 | handler ההקשה לא נוגע ב-`player.stop()` | `SoundEngine`, `GameViewModel` | — | probe: `game.tap` avg < 1ms, max < 4ms | tap avg > 1ms |

### נקודות סיכון חדשות ב-1.2.0 (לבדוק בכל merge של ענפי הסוכנים)
- **כלכלה סמכותית (Agent A):** flush של `EconomyOutbox` "after game over, off the render path" — לוודא שאין קריאת רשת/IO סינכרוני על main בין סוף סבב ל-Game Over (`nav.roundEndToGameOver` לא עולה מעל baseline).
- **StoreKit (Agent C):** `Transaction.updates` listener ו-`Transaction.unfinished` scan — לא על main באמצע סבב; לא להציג sheet/alert רכישה מעל משחק רץ (בדומה ל-F7).
- **חנות וסקינים:** רינדור ראשון של gradient/shader של סקין — F5 עם כל סקין פרימיום, לא רק Glitch.
- **רגרסיה פתוחה:** `nav.roundEndToGameOver` עלה מ-31–40ms (1.1.1) ל-55–58ms (1.2.0) — לא מוסבר; לא חוסם (מתחת ל-150ms), לעקוב.

## B. נוהל אימות ביצועים

### B1. סימולטור (אוטומטי, לכל release candidate ולכל merge של ענף שנוגע ב-Game/Audio/Shop/Economy)
```bash
# אותו Mac, אותו סימולטור לכל ההשוואות (UDID קבוע), derived data נפרד
PT_SIM_UDID=<udid> PT_DERIVED_DATA=/tmp/pt-perf-dd scripts/perf-run.sh rc-<sha>-default
PT_SIM_UDID=<udid> PT_DERIVED_DATA=/tmp/pt-perf-dd TEST_RUNNER_PT_PERF_THEME=glitch scripts/perf-run.sh rc-<sha>-glitch

python3 scripts/qa/perf-gate.py docs/perf/rc-<sha>-default.json --baseline docs/perf/after-1.2.0-default-run2.json
python3 scripts/qa/perf-gate.py docs/perf/rc-<sha>-glitch.json  --baseline docs/perf/after-1.2.0-glitch-run2.json
```
- `perf-run.sh` מוחק את האפליקציה, מריץ `GameplayPerformanceTests` עם `-PTPerfProbe -PTUITestNoAds -PTUITestOfflineBackend` (אין רשת, אין כתיבה ל-Supabase), ושומר JSON.
- `perf-gate.py` בודק ספים מוחלטים: 0 פריימים ≥250ms ו-0 stalls ≥250ms בזמן משחק, ≤2 פריימים ≥100ms, worst < 250ms, p99 ≤ 25ms, hitch ratio ≤ 0.6%, `nav.roundEndToGameOver` avg ≤150 / max ≤250ms, `game.tap` avg ≤1 / max ≤4ms, `game.viewBootstrap` ≤50ms, זיכרון ≤150MB, לפחות 5 סבבים. עם `--baseline` הוא גם מסמן החמרה של >50%.
- **כיול:** הסקריפט נבדק על הנתונים הקיימים — `baseline-1.1.0-run1` נכשל (8 הפרות), `after-1.2.0-glitch` (לפני תיקון ה-warm-up, stall 519ms) נכשל, ו-`after-1.1.1-*`, `after-1.2.0-default*`, `after-1.2.0-glitch-run2` עוברים.
- **2 ריצות** לכל תצורה; כישלון בריצה אחת → ריצה שלישית; שני כישלונות = רגרסיה.
- הערות על `perf-run.sh` (לא שונה): ברירת המחדל היא סימולטור בשם "iPhone 17"; אם הוא לא קיים, `set -e` + `pipefail` גורמים ליציאה שקטה לפני הודעת השגיאה — תמיד להעביר `PT_SIM_UDID`. הסקריפט כותב גם `docs/perf/<label>.xcodebuild.log` — לא לעשות לו commit.

### B2. מכשיר פיזי (חובה לפני G10 TestFlight; סימולטור אינו מוכיח hitch rate)
- `docs/perf/DEVICE_PROFILING_PROTOCOL.he.md`, 8 תרחישים × 3 חזרות, Release (Product › Profile), Instruments: Animation Hitches, Hangs, Time Profiler, os_signpost (`com.perfecttap.perf`), Allocations.
- מכשירים: iPhone ישן (11/12/SE) + ProMotion 120Hz; iPad אחד (Portrait + Landscape).
- תרחישים נוספים ל-1.2.0: (9) פתיחת החנות + גלילה + preview לכל סקין; (10) Game Over → חנות → משחק חדש; (11) עם flags ON ב-build Debug: רכישת Sandbox ואז מיד משחק — אין hitch מה-listener.
- **קריטריון קבלה:** אין Hang ≥250ms; `nav.roundEndToGameOver` חציוני <150ms במכשיר הישן; אין hitch מחזורי ~10.7ש׳; תרחישי revive/רקע תמיד ממשיכים.

### B3. רישום
- JSON + שורת סיכום ב-`docs/QA_1.2.0_MATRIX.md` (שורת Performance) וטבלת מכשיר לפי הפרוטוקול.
