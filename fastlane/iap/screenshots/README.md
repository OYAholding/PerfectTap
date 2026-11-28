# IAP review screenshots

Generate these files from `PerfectTapUITests/IAPReviewScreenshotTests` using the checked-in StoreKit configuration:

- `en-US/coin-packs.png`
- `en-US/skin-neonpulse.png`
- `en-US/skin-liquidchrome.png`
- `en-US/skin-glitchmode.png`
- `en-US/skin-cosmicgold.png`

They must show StoreKit's configured **local test prices** without placeholders. These are authentic local StoreKit screenshots, not evidence of live App Store Connect prices. Re-capture whenever product names, local test prices, or layout change.

This folder is preparation material only. No Fastlane lane uploads it. `iap_prepare` does not require screenshots; `iap_submission_validate` requires them and also verifies that all products exist in App Store Connect.
