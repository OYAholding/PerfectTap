# PerfectTap 1.2.0 — דוח סשן Claude Code (25.11.2026)

**ענף:** `release/1.2.0` · **PR:** OYAholding/PerfectTap#14 · **ייצור:** לא שונה דבר.

## שחזור
- עבודת Codex שלא נשמרה ב-commit (44 קבצים) גובתה ל-`backup/codex-wip-2026-11-25` (`9882a83`) ונשמרה ב-commit `24b45a2`.
- PR #12 (`777011b`) ו-PR #13 (`a3ee906`) כבר כלולים ב-`release/1.2.0`, ואין התנגשויות.
- חוזה משותף: `docs/ECONOMY_SERVICE_CONTRACT.md`.

## מה נבנה
| תחום | עיקר |
|---|---|
| Supabase | `submit_economy_event` (8 מקורות, השרת מחשב את הסכום, אידמפוטנטי, עם תקרות). IAP נזקף דרך ה-ledger. refund מנכה עד אפס, בלי `coin_debt`. `save_profile` מקבע את יתרת המטבעות כשתצורת כלכלה פעילה. Edge Function `admob-ssv`. `reconcile_legacy_economy` כ-dry-run. מתג מכירות `iap_sales_control`. סקריפטי containment. |
| iOS כלכלה | `EconomyService` יחיד, `EconomyOutbox` לכל משתמש (שורד סגירת אפליקציה, offline). Wheel שבו השרת בוחר. SSV custom_data. Starter. Season מחושב לפי תאריך. כשהדגל כבוי אין שינוי התנהגות. |
| StoreKit / ASC | תקרה לפי תצורת build: `Release` כבוי, `Release-IAP` מוגבלת בשרת, `Debug-StoreKit` מקומית. listener מופעל ב-launch. מטבעות רק לחשבון ששילם, ו-finish רק אחרי אישור השרת. restore לאורחים. refund ו-reversal. `iap_reconcile` אידמפוטנטי, dry-run כברירת מחדל. |
| QA / CI | שומרי דגלים וסודות, Deno, pgTAP, Release build עם בדיקת הדגלים שנבנו. `docs/QA_1.2.0_MATRIX.md`, `docs/RELEASE_1.2.0_RUNBOOK.he.md`. |

## בדיקות
| סוויטה | מצב |
|---|---|
| iOS unit | PASSED 123/123 (עץ ממוזג `4ac263c`) |
| StoreKit מקומי + Release build + built-flags=NO | PASSED 26/26. ריצה אחת מתוך שלוש אצל Agent A נכשלה בשתי בדיקות (flaky) |
| pgTAP | PASSED 252/252 עד מיזוג `agent-b/economy-backend`. מבחני מתג המכירות (30) NOT RUN, כי Docker קרס |
| Deno | PASSED 23/23, fmt/lint/check נקיים |
| ASC reconciler (Ruby) | PASSED 7/7 |
| UI mode matrix | FAILED לפני התיקון (בדיקה לא מעודכנת). אחרי התיקון NOT RUN |
| Sandbox / מכשיר / TestFlight | NOT RUN |
| Perf סוף סבב → Game Over | לא חד-משמעי (229ms לעומת 56ms, המחשב היה עמוס). צריך להריץ שוב |

## App Store Connect (קריאה בלבד)
ההתחברות ל-API עובדת. **אף אחד מ-9 המוצרים לא קיים.** כל מחירי הטיוטה קיימים במחירון של ארה״ב, ו-175 טריטוריות זמינות.

## החלטות בעלים פתוחות
1. ערכי Model B, תקרת משחק יומית (1,500) ולוח עונות (השרת: 1.12.2026–1.3.2027, האפליקציה: מחזור רבעוני).
2. מחירי IAP סופיים (`coins.3000` עודכן ל-$3.99 לפי הטבלה).
3. Paid Apps Agreement, מס ובנק. אחר כך `PT_CONFIRM=yes bundle exec fastlane iap_reconcile confirm_create:true`.
4. פריסת המיגרציות ל-staging ואחר כך ל-production (G-gates ב-runbook).
5. מדיניות refund ו-`coin_debt` (כרגע כבוי).

## המשך — 26.11.2026 (`e424776`)
- **לוח עונות:** האפליקציה והשרת מחשבים עונה זהה (רבעונית מ-1.3.2026, UTC), עם חלון חסד של 72 שעות. ה-pacing מגביל דרגות שנתבעו בעונה הנוכחית, ולא את מספר הדרגה, כך שהתקדמות שנצברה לא נדחית. הערכים עדיין מחכים לאישור.
- **StoreKit flake:** נפתר. `clearTransactions()` חוזר לפני שה-cache מתנקה. 5 ריצות רצופות עברו 26/26.
- **UI mode matrix:** 15/15 מצבים עוברים, אחרי תיקון הבדיקה.
- **Perf במחשב פנוי:** עבר פעמיים. סוף סבב → Game Over: 35–39ms (baseline 55ms). ה-229ms הקודמים נבעו מעומס.
- **pgTAP:** 319/319. iOS unit: 128/128.
- **Production (קריאה בלבד):** ה-head הוא `20261114120000`. חמש מיגרציות 1.2.0 לא פרוסות. Edge Functions פרוסות: `claim-legacy-account` v2 ו-`delete-account` v1 בלבד.
