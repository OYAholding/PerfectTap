# PerfectTap — תהליך שחרור (קבוע לכל גרסה)

עקרונות:
- כל שלב שכותב ל-Apple דורש אישור מפורש שלך (`PT_CONFIRM=yes`).
- שליחה ל-App Review ושחרור לחנות נעשים **רק ידנית** ב-App Store Connect.
- בלי שירותים בתשלום: GitHub Actions חינמי לריפו ציבורי, Fastlane ו-Xcode מקומיים.

| # | שלב | איך | מי |
|---|---|---|---|
| 1 | פיתוח | ענף `feature/…` או `fix/…` מ-`main` | מפתח |
| 2 | בדיקות | `xcodebuild test … -scheme PerfectTap` (offline); לפי הצורך `-scheme PerfectTapUITests` על iPhone + **iPad Air 11-inch (M3)**; ‏Supabase: ‏`supabase test db --local` + `./supabase/tests/integration/run.sh` | מפתח |
| 3 | PR | `gh pr create` → CI: ‏gitleaks + backend tests | אוטומטי |
| 4 | אבטחה | CI ירוק, אין סודות (`.p8`/`.p12`/`sb_secret_`) | אוטומטי |
| 5 | Merge | אחרי review | **בעלים** |
| 6 | בדיקת מצב | `bundle exec fastlane asc_check` | קריאה בלבד |
| 7 | גרסה וחתימה | העלאת `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION` ב-`ios/PerfectTap/project.yml` → `bundle exec fastlane validate_release` | קריאה בלבד |
| 8 | Build | `bundle exec fastlane build`: ‏`.ipa` חתום ב-`build/fastlane/`, בדיקת גרסה בתוך ה-IPA | מקומי |
| 9 | TestFlight | `PT_CONFIRM=yes bundle exec fastlane beta`: קבוצה פנימית בלבד, הערות מ-`fastlane/testflight_notes.txt` | **אישור בעלים** |
| 10 | אימות | התקנה מ-TestFlight על מכשיר אמיתי: ‏ATT, מודעות, מעבר חשבון, דו-קרב | בודקים |
| 11 | Metadata | `bundle exec fastlane metadata_pull` → עריכה → `PT_CONFIRM=yes bundle exec fastlane metadata_push` (טקסט בלבד); ‏Review Notes | **אישור בעלים** |
| 12 | דוח | `bundle exec fastlane release_report` → `build/fastlane/release_report.md` | קריאה בלבד |
| 13 | הגשה | App Store Connect → Add for Review → Submit | **בעלים בלבד** |

## לפני כל build
- גרסה חדשה > הגרסה החיה. מספר build גדול מכל build שהועלה (ה-lane בודק מול Apple).
- הגרסה ב-App Store Connect שווה ל-`MARKETING_VERSION` (`PT_CONFIRM=yes fastlane rename_version`).
- SDK חדש או מידע חדש שנאסף: לעדכן את `PrivacyInfo.xcprivacy`, את `docs/APP_PRIVACY_DECLARATION.he.md` ואת שאלון App Privacy.

## חתימה
חתימה אוטומטית עם מפתח ה-API ‏(`-allowProvisioningUpdates`, ‏team `K88C7DPG4C`).
ל-export ל-App Store צריך **iOS Distribution identity** ב-Keychain, או הרשאת Cloud-Managed Distribution Certificate למפתח.
ראו "חסמים" ב-`docs/RELEASE_1.1.0_READINESS.he.md`.
