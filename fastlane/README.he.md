# Fastlane — PerfectTap

אימות מול App Store Connect נעשה **רק** עם מפתח API של הצוות (role: App Manager). אין Apple ID וסיסמה.
כל ה-lanes נעולים על האפליקציה PerfectTap (App ID `6760975737`, Bundle ID `com.perfecttap.app`)
ונכשלים אם ה-API מחזיר אפליקציה אחרת.

## הגדרה מקומית (פעם אחת)
המפתח וההגדרות נשמרים **מחוץ לריפו** (הרשאות `600`):

```
~/.config/perfecttap/apple/AuthKey_<KEY_ID>.p8
~/.config/perfecttap/apple/asc.env
```

`asc.env`:
```
ASC_KEY_ID=<KEY_ID>
ASC_ISSUER_ID=<ISSUER_ID>
ASC_KEY_PATH=$HOME/.config/perfecttap/apple/AuthKey_<KEY_ID>.p8
```
ה-Fastfile מסרב להשתמש בקובץ `.p8` שנמצא בתוך הריפו. `*.p8` ו-`AuthKey_*.p8` חסומים ב-`.gitignore`.

```bash
brew install ruby xcodegen                       # Ruby של המערכת (2.6) ישן מדי
export PATH="/opt/homebrew/opt/ruby/bin:$PATH" LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8
bundle config set --local path vendor/bundle
bundle install
```

## Lanes
| Lane | כותב ל-App Store Connect? | מה עושה |
|---|---|---|
| `asc_check` | לא | בודק חיבור, גרסאות, builds, TestFlight, סטטוס review, ו-HTTP של Privacy/Support URL |
| `metadata_pull` | לא | מוריד metadata ל-`fastlane/metadata` (פרטי איש קשר ל-review לא נכנסים לגיט) |
| `build` | לא | `xcodegen generate` + ‏`.ipa` חתום ל-`build/fastlane/`; מספר build = הגבוה ביותר שהועלה + 1 |
| `beta` | **כן** — `PT_CONFIRM=yes` | `build` + העלאה ל-TestFlight. בלי Beta App Review ובלי בודקים חיצוניים |
| `metadata_push` | **כן** — `PT_CONFIRM=yes` | מעלה טקסט metadata בלבד. בלי binary, בלי צילומי מסך, בלי שליחה ל-review |

```bash
bundle exec fastlane asc_check
bundle exec fastlane metadata_pull
PT_CONFIRM=yes bundle exec fastlane beta          # רק אחרי אישור מפורש
```

אף lane לא שולח ל-App Review, לא מפיץ לבודקים חיצוניים ולא משחרר גרסה. אלה פעולות ידניות ב-App Store Connect.
