# PerfectTap — Compliance research: health claims, payments, advertising

**Prepared:** 2026-11-21 · **Status:** research notes, **not legal advice**. Have counsel confirm the items under "Open questions" before any launch decision.
**Access date:** every URL below was accessed on **2026-11-21** unless stated otherwise.
**Verification labels:** **VERIFIED** = read on the primary (official) source. **SECONDARY** = only press or law-firm coverage. **UNVERIFIED** = could not confirm. **[RECENT]** = changed in 2025–2026.

Context: PerfectTap wants to be "designed with ADHD players in mind" without making medical claims. In 1.2.0 it plans to sell cosmetic digital items through StoreKit 2 IAP, and possibly through a web store.

---

## 0. Summary for decision-makers

1. **The ADHD positioning works only as a design statement, never as a health claim.**
   - OK: "designed with ADHD players in mind", "built with feedback from ADHD players" (only if documented and true).
   - Not OK: "improves focus", "trains attention", "reduces ADHD symptoms", "clinically proven".
   - Those claims trigger Apple 1.4.1 / 2.3 / **2.3.14** **[RECENT]**, FTC substantiation duties (the FTC's 2016 Lumosity case explicitly covered ADHD claims) and FDA device territory (ADHD digital therapy is a Class II device type).
2. **Cosmetics sold in the app must use Apple IAP** (3.1.1). Showing odds is mandatory if items are ever randomized (loot boxes).
3. **External web purchases:**
   - **US storefront:** external buy buttons and links are currently allowed with no entitlement. Whether Apple may charge a commission on them is still in court.
   - **EU:** since **2026-10-01**, one set of terms applies: 26% IAP / 20% alternative PSP / 15% link-out / 5% CTC **[RECENT]**.
   - **South Korea:** 26%.
   - **Japan:** MSCA terms since December 2025.
4. **Lemon Squeezy is shutting down: VERIFIED.** Sign-ups closed **2026-11-16**, and transaction processing ends **2027-03-31**. Do not build on it. The migration path is Stripe Managed Payments.
5. **Meta ads may never address the viewer's own condition.** "Do you have ADHD?" is a policy violation. There is no ADHD interest targeting. Health-condition custom conversions have been blocked since 2025-09-02.
6. **In-app research on ADHD needs informed consent and ethics-board approval** (Apple 5.1.3(iii)–(iv)). See [USER_STUDY_PLAN.md](USER_STUDY_PLAN.md).

---

## 1. Apple App Review Guidelines

**Source:** <https://developer.apple.com/app-store/review/guidelines/>. The page shows **"Last Updated: October 16, 2026"**. VERIFIED.

**Recent changes** (Apple Developer News, <https://developer.apple.com/news/>), VERIFIED:

| Date | Change |
|---|---|
| 2025-05-01 | 3.1.1, 3.1.1(a), 3.1.3 and 3.1.3(a) revised for the **US storefront** after the Epic contempt ruling (buttons, links, calls to action allowed). **[RECENT]** |
| 2025-06-09 | Added 3.2.2(x) (incentivizing user actions). |
| 2025-11-13 | Revised 1.2.1(a), 4.1(c), 4.7, 5.1.1(ix), 5.1.2(i) (disclosure before sharing data with third-party AI). |
| 2026-02-06 | Random/anonymous chat apps fall under 1.2. |
| **2026-10-16** | New **2.3.14** (creative assets must not contain unverifiable product claims). New **2.5.19** (no hidden or undocumented features). Revised 1.2, 3.1.1(a) and 5. Announcement: <https://developer.apple.com/news/?id=92th7e5i>. **[RECENT]** |

### 1.1 Medical and health claims

- **1.4 / 1.4.1 (Physical Harm → Medical): VERIFIED**
  - Apps that could be used for diagnosing or treating patients get "greater scrutiny".
  - Health-measurement accuracy claims need disclosed data and methodology. Apple rejects claims whose accuracy cannot be validated.
  - Apps should remind users to check with a doctor.
  - Apps with regulatory clearance should link to the clearance documentation.
- **2.3 Accurate Metadata: VERIFIED**
  - Metadata must accurately reflect the app's core experience.
  - Under **2.3.1(a)**, misleading marketing "within or outside of the App Store" can lead to removal. **This covers off-store ads too (e.g. Meta).**
  - Under **2.3.7**, keywords must accurately describe the app. "ADHD treatment" or "ADHD therapy" keywords would be inaccurate.
- **2.3.14 (new 2026-10-16): VERIFIED.** Creative assets must not include "unverifiable product claims". A product-page header like "improves focus" is out unless substantiated. **[RECENT]**
- **5.1.1 / 5.1.3 (Health and health research): VERIFIED**
  - **5.1.3(i):** data gathered in health or health-research contexts may not be used for advertising or data mining.
  - **5.1.3(iii):** health-related human-subject research requires informed consent, including parental consent for minors. Consent must cover nature, purpose and duration; procedures, risks and benefits; confidentiality; a contact; and withdrawal.
  - **5.1.3(iv):** health-related human-subject research requires approval from an **independent ethics review board**, with proof provided on request.
- **1.3 Kids Category: VERIFIED.** No links out or purchase opportunities except behind a parental gate. No third-party analytics or ads. **Recommendation:** do not list in the Kids Category if a web store or third-party analytics is planned.

**Implication for PerfectTap:**
- A game with no health or measurement claims is not a "medical app".
- Any "focus score" shown to players must not be presented as a health or attention measurement. Call it a game statistic, e.g. "timing consistency".
- Do not ask players inside the app whether they have ADHD, except in an IRB-approved, consented study.

### 1.2 In-app purchases for digital cosmetics

- **3.1.1: VERIFIED.** Unlocking features or content, including in-game currencies and premium content, must use IAP.
  - The word "cosmetic" does not appear. Cosmetic skins are digital content consumed in the app, so the general rule covers them.
  - **Loot boxes:** randomized paid items must "disclose the odds of receiving each type of item" before purchase.
  - Digital gift cards redeemable in-app can only be sold via IAP.
- **3.1.1(a): VERIFIED.** Developers may apply for entitlements to link to a "permitted destination". Entitlements "are not required" for buttons and links in **US storefront** apps. In all other storefronts, no buttons, links or calls to action to non-IAP purchasing are allowed except via entitlements or regional terms. On 2026-10-16 the Music Streaming entitlement was merged into the StoreKit External Purchase Link Entitlement.
- **3.1.3 (Other purchase methods): VERIFIED**
  - The preamble allows in-app encouragement of non-IAP purchasing only on the **US storefront** or as 3.1.1(a) and 3.1.3(a) allow. Developers may always communicate with users *outside* the app.
  - **3.1.3(b) Multiplatform services:** items bought on the web, "including consumable items in multi-platform games", may be used in the app *provided they are also available as IAP*. → Web-store cosmetics can unlock in iOS worldwide **if the same items are also sold via IAP**. Outside the US, the app cannot point to the web store without an entitlement or regional terms.
  - (a) reader apps, (c) enterprise, (d) person-to-person, (e) physical goods, (f) free stand-alone companions and (g) ad management do not apply to PerfectTap.
- **5.3 Gaming / contests:** if real-money prizes or sweepstakes are ever added, official rules are required. See also Stripe's prohibition on paid skill tournaments in §3.

### 1.3 US storefront after *Epic v. Apple* **[RECENT]**

| Date | Event | Verification |
|---|---|---|
| 2025-04-30 | Judge Gonzalez Rogers (N.D. Cal., 4:20-cv-05640-YGR) held Apple in contempt of the 2021 anti-steering injunction. Apple was barred from charging commission on link-out purchases and from restricting buttons and links. | SECONDARY (e.g. [MacRumors](https://www.macrumors.com/2025/04/30/apple-app-store-anti-steering-injunction-violation)). Effect confirmed by Apple's 2025-05-01 guideline change. |
| 2025-12-11 | **Ninth Circuit (No. 25-2935)** affirmed the contempt finding, but held Apple may charge a commission limited to costs "genuinely and reasonably necessary". Remanded to set that fee. | SECONDARY ([Fenwick](https://www.fenwick.com/insights/publications/ninth-circuit-largely-upholds-ruling-in-epic-v-apple)). [Opinion](https://law.justia.com/cases/federal/appellate-courts/ca9/25-2935/25-2935-2025-12-11.html) not retrievable (HTTP 403). |
| 2026-06-30 | **US Supreme Court granted certiorari**, *Apple Inc. v. Epic Games, Inc.*, No. 25-1311, limited to Question 1 (contempt based on an injunction's "spirit"). | VERIFIED ([SCOTUSblog](https://www.scotusblog.com/cases/apple-inc-v-epic-games-inc-2/)) |
| 2026-08-11 / 08-13 | District court refused to pause the fee proceedings. The Supreme Court denied Apple's stay application (26A194). | SECONDARY ([9to5Mac](https://9to5mac.com/2026/08/11/court-rejects-apples-attempt-to-postpone-app-store-fee-proceedings-in-epic-games-case/)) / VERIFIED (SCOTUSblog docket) |
| **2027-01-11** | **Oral argument scheduled.** | VERIFIED (SCOTUSblog) |

**Bottom line (US):**
- US apps may currently include external purchase buttons and links without an entitlement (VERIFIED, 2026-10-16 guideline text).
- **UNVERIFIED:** whether the district court has yet approved a cost-based commission. No rate-setting order was found as of 2026-11-21.
- Plan the business case assuming Apple may eventually charge a cost-based fee on US link-outs. The Supreme Court ruling, likely by mid-2027, could also change the picture.

### 1.4 EU (Digital Markets Act) **[RECENT]**

Sources:
- Apple Developer News, 2026-08-18, <https://developer.apple.com/news/?id=gmws0jgp>
- <https://developer.apple.com/support/apps-in-the-eu/>
- 2025-06-26 update, <https://developer.apple.com/news/?id=awedznci> (now superseded)

All VERIFIED. **From 2026-10-01 (DPLA Attachment 14):**

| Path | Standard | Reduced (Small Business Program, etc.) |
|---|---|---|
| App Store + Apple IAP | 26% | 15% |
| App Store + alternative payment processor in-app | 20% | 10% |
| App Store + link-out (on sales within 7 days of the tap) | 15% store services commission | 10% |
| Distribution outside the App Store | 5% Core Technology Commission (CTC) | — |

- **Abolished:** the Core Technology Fee (€0.50 per install), the Initial Acquisition Fee and the Store Services *Fee*. Do not confuse the last one with the link-out store services *commission*, which still applies.
- Alternative payment options, if offered, must be maintained for 12 months, with monthly reporting.
- **Minors:**
  - Kids Category and under-13 users: no out-of-app offers. Alternative payments only behind a parental gate.
  - Ages 13–17: parental gate for both.

### 1.5 Other regions

| Region | Mechanism | Terms | Verification |
|---|---|---|---|
| **South Korea** | StoreKit External Purchase Entitlement (KR), under the Telecommunications Business Act | **26%** commission. Separate KR-only binary, with one pre-approved PSP. Cannot be combined with IAP in the same app. | VERIFIED: <https://developer.apple.com/support/storekit-external-entitlement-kr>, news 2022-06-30 <https://developer.apple.com/news/?id=q0feipe4> |
| **Japan** | Mobile Software Competition Act (MSCA), announced by Apple 2025-12-17 with iOS 26.2 | App Store commission 10% (Small Business; subscriptions after year 1) or 21%, **+5%** if Apple IAP is used. 15%/10% on web-linked purchases. 5% CTC outside the App Store. Parental gate for under-18 purchases outside IAP. No web links for under-13 users or Kids apps. Updated agreement to accept by 2026-03-17. | VERIFIED: [Apple Newsroom](https://www.apple.com/newsroom/2025/12/apple-announces-changes-to-ios-in-japan/). **UNVERIFIED:** the rate for in-app *alternative payment processing*, and the statutory full-enforcement date (reported as 2025-12-18). |
| **Netherlands** (historical) | Dating apps only, after the ACM order | 27% (2022) | Support page exists (<https://developer.apple.com/support/storekit-external-entitlement/>). Rate is SECONDARY. Irrelevant to games. |
| Brazil / China / Taiwan (FYI) | Brazil alternative payments (announced 2026-06-18). China 25%/12% from 2026-03-15. Taiwan 30%→26% from 2026-10-31. | — | VERIFIED headlines only (Developer News) |

---

## 2. Lemon Squeezy wind-down: VERIFIED **[RECENT]**

- Stripe acquired Lemon Squeezy (announced 2024-07-26): <https://lemonsqueezy.com/blog/stripe-acquires-lemon-squeezy>.
- **Wind-down announced 2026-11-16:** <https://www.lemonsqueezy.com/blog/saying-goodbye-to-lemon-squeezy>. Migration docs: <https://docs.lemonsqueezy.com/migration>.

| Milestone | Date |
|---|---|
| New sign-ups and stores stop | **2026-11-16** |
| Migration tooling to Stripe Managed Payments | 2026-12-02 |
| Recommended latest start of migration (can take up to ~8 weeks) | mid-January 2027 |
| **Transaction processing ends, including renewals** (the blog says the deadline will not be extended) | **2027-03-31** ✅ the reported date is confirmed |

- **Migration target:** Stripe Managed Payments (merchant of record).
  - Promotional rate: 1.5% through 2027-12-01.
  - Standard rate: 3.5% plus Stripe processing, versus Lemon Squeezy's 5% + $0.50 (<https://docs.lemonsqueezy.com/migration/comparison>).
  - Gaps: no PayPal, no license keys or affiliates.
- **Stripe Managed Payments eligibility:** <https://docs.stripe.com/payments/managed-payments/eligibility>. "Video games" is a supported category. App-to-web guide: <https://docs.stripe.com/payments/managed-payments/set-up-mobile>.
- **Stripe Restricted Businesses** (last updated 2026-09-22, <https://stripe.com/legal/restricted-businesses>):
  - The sale of in-game items is *restricted* unless the seller operates the virtual world. PerfectTap does, but expect review.
  - Paid **skill tournaments/competitions** are *prohibited*.
- **Recommendation:** if a web store is ever built, use Stripe Managed Payments (or Stripe Checkout + Stripe Tax), never Lemon Squeezy. Confirm acceptance with Stripe first.

---

## 3. Meta advertising policies

**Source:** Meta Transparency Center, Advertising Standards: <https://transparency.meta.com/policies/ad-standards/>.

- **Personal Attributes: VERIFIED** (<https://transparency.meta.com/policies/ad-standards/objectionable-content/privacy-violations-personal-attributes/>)
  - Ads may not assert or imply personal attributes, including physical or mental health conditions and disability.
  - Ads may not imply the advertiser knows a user's medical information.
  - Meta's own examples: "Do you have diabetes?" is not allowed, while "New diabetes treatment available" is.
- **Health & Wellness: VERIFIED** (<https://transparency.meta.com/policies/ad-standards/restricted-goods-services/health-wellness/>; latest dated version 2026-07-22 **[RECENT]**). No negative self-perception messaging. No claims to "cure, heal, or eliminate" conditions. No exaggerated or time-bound result promises.
- **Sensitive detailed targeting removed 2022-01-19: VERIFIED** ([announcement](https://www.facebook.com/business/news/removing-certain-ad-targeting-options-and-expanding-our-ad-controls), [developer blog](https://developers.facebook.com/blog/post/2021/12/08/updating-metas-detailed-targeting-options/)). Health-cause interests were removed, so expect **no ADHD interest targeting**. Use broad or casual-games targeting.
- **Health-related custom conversions:**
  - **VERIFIED:** from **2025-09-02**, custom conversions naming specific health conditions are flagged and cannot run ([Meta docs](https://developers.facebook.com/docs/meta-pixel/implementation/conversion-tracking/)) **[RECENT]**.
  - **SECONDARY/UNVERIFIED:** January 2025 restrictions on lower-funnel events for datasets Meta classifies as health & wellness.
  - → Never name Pixel/SDK/CAPI events "adhd_*", "focus_score", "diagnosis", etc. Never send any self-reported diagnosis to Meta.

### Ad copy examples

| ❌ Non-compliant | Why | ✅ Compliant alternative |
|---|---|---|
| "Do you have ADHD? This game is for you." | Asserts a personal attribute | "PerfectTap: a timing game designed with ADHD players in mind." |
| "Struggling to focus? PerfectTap trains your attention." | Implies the viewer's condition, and makes an unsubstantiated cognitive claim | "Short, satisfying rounds. Play for 30 seconds or 30 minutes." |
| "Clinically proven to improve focus." | No RCT substantiation (FTC); Apple 2.3.14 | "Built with feedback from ADHD gamers." (only if true and documented) |
| "Reduce ADHD symptoms while you play." | Treatment claim (FDA device territory; Meta health rules) | "Calm mode: fewer effects, no timers, just the bar." |
| "Your ADHD brain will love this." | Implies knowledge of the viewer's condition | "For players who love quick feedback and clear visuals." |
| "Like medication, but fun." | Drug comparison / treatment implication | "Low-pressure, pick-up-and-play fun." |

Describe design features (short sessions, clear feedback, adjustable stimulation, no punishing streaks) and who the game was built *with*, never what it does to the player's brain.
Add "PerfectTap is a game, not a medical product" in the FAQ. Note that **a disclaimer does not cure a contradictory claim** (FTC guidance, Example 14).

---

## 4. US regulators (context for any "focus" wording)

- **FTC Health Products Compliance Guidance (2022-12-20): VERIFIED.** <https://www.ftc.gov/business-guidance/resources/health-products-compliance-guidance>
  - Health claims need "competent and reliable scientific evidence", generally randomized controlled human trials.
  - Brain-training claims need sound research on *that specific program*.
  - Improvement on one lab task does not support a general claim.
  - Testimonials are not substantiation.
- **FTC v. Lumos Labs (2016-01-05): VERIFIED.** <https://www.ftc.gov/news-events/news/press-releases/2016/01/lumosity-pay-2-million-settle-ftc-deceptive-advertising-charges-its-brain-training-program>
  - $2M redress ($50M judgment suspended).
  - The FTC challenged claims that the games reduce cognitive impairment from conditions **including ADHD**. This is the direct precedent.
- **FDA General Wellness guidance (revised 2026-01-06): VERIFIED.** <https://www.fda.gov/regulatory-information/search-fda-guidance-documents/general-wellness-policy-low-risk-devices>; PDF <https://www.fda.gov/media/90652/download> **[RECENT]**
  - Claims about "concentration" or eye-hand coordination *without reference to a disease* can be general wellness.
  - Claims that a game diagnoses or treats a condition are not general wellness.
  - ADHD digital therapy is a regulated device type: EndeavorRx De Novo **DEN200026**, 21 CFR 882.5803, Class II, prescription only (<https://www.accessdata.fda.gov/cdrh_docs/reviews/DEN200026.pdf>).
  - → "Improves attention in people with ADHD" is a **device claim**. Even generic "focus" claims require FTC substantiation. **Safest: no cognitive-benefit claims at all.**
- Outside the US (EU MDR, UK MHRA, Israel AMAR), the same logic applies: software with a medical intended purpose is a medical device. This was not researched in depth here and should be checked before any non-US health positioning.

---

## 5. Wording rules for PerfectTap (derived)

| Use | Avoid |
|---|---|
| "designed with ADHD players in mind" | "for ADHD", "ADHD training", "ADHD therapy" |
| "calm mode", "reduced effects", "short sessions", "you choose the pace" | "improves focus/attention/concentration", "trains your brain" |
| "timing consistency" (game statistic) | "attention score", "focus score", "ADHD score", "cognitive age" |
| "we're studying whether practice carries over; results not yet known" | "scientifically proven", "clinically tested", "doctor-recommended" |

---

## 6. Open questions (need counsel or direct confirmation)

1. Whether a US link-out commission has been set on remand (none found as of 2026-11-21). Also the Supreme Court outcome after the 2027-01-11 argument.
2. Japan: the commission for in-app alternative payment processing, and the statutory full-enforcement date.
3. Meta's exact current wording on health & wellness dataset restrictions (the January 2025 tiering is only secondary).
4. Stripe's acceptance of cosmetic items for Managed Payments (a "restricted" category).
5. Non-US medical-device rules if any health positioning is ever considered.

---

## סיכום בעברית

> מחקר בלבד, לא ייעוץ משפטי. כל הקישורים נבדקו ב־21.11.2026.

- **מיצוב ADHD:** מותר לתאר את המשחק כ"מעוצב מתוך מחשבה על שחקנים עם ADHD", כלומר הצהרה על העיצוב ועל קהל היעד.
  - **אסור** לטעון שהמשחק "משפר ריכוז" או "מאמן קשב", שהוא "מפחית תסמיני ADHD" או שהוא "מוכח קלינית".
  - טענות כאלה מפעילות את הנחיות אפל 1.4.1, 2.3 ו־**2.3.14**. סעיף 2.3.14 נוסף ב־16.10.2026 ואוסר "טענות מוצר שלא ניתן לאמת" בחומרי החנות.
  - טענות כאלה גם מחייבות ביסוס מדעי מול ה־FTC. ב־2016 נקנסה Lumosity, בין השאר על טענות הקשורות ל־ADHD.
  - בנוסף, טענות כאלה מכניסות את המשחק לתחום של מכשור רפואי מוסדר מול ה־FDA. EndeavorRx היא מכשיר Class II במרשם.
- **רכישות בתוך האפליקציה:** פריטים קוסמטיים בתוך האפליקציה חייבים לעבור דרך IAP של אפל (סעיף 3.1.1). אם יש "קופסאות מזל", חובה להציג את הסיכויים לפני הרכישה.
- **תשלום חיצוני:**
  - **ארה"ב:** מותר כרגע לשים כפתור או קישור לרכישה באתר, בלי הרשאה מיוחדת. בית המשפט לערעורים קבע בדצמבר 2025 שאפל רשאית לגבות עמלה מבוססת־עלות. גובה העמלה עדיין לא נקבע, והדיון בבית המשפט העליון נקבע ל־11.1.2027.
  - **האיחוד האירופי (מ־1.10.2026):** 26% ב־IAP, 20% בספק תשלומים חלופי, 15% בקישור החוצה ו־5% CTC מחוץ ל־App Store. אגרת ה־CTF בוטלה.
  - **דרום קוריאה:** 26%.
  - **יפן:** חוק ה־MSCA, החל מדצמבר 2025.
  - פריטים שנקנו באתר יכולים להיפתח באפליקציה בכל העולם (סעיף 3.1.3(b)), בתנאי שהם נמכרים גם ב־IAP.
- **Lemon Squeezy (מאומת):** ההרשמה נסגרה ב־16.11.2026, ועיבוד התשלומים מסתיים ב־**31.3.2027**, בלי הארכה. המעבר המומלץ הוא ל־Stripe Managed Payments. לא לבנות חנות חדשה על Lemon Squeezy.
- **פרסום במטא:**
  - אסור לפנות לצופה לגבי מצבו, למשל "יש לך ADHD?".
  - אין טירגוט לפי עניין ב־ADHD. הוא הוסר ב־2022.
  - מאז 2.9.2025 נחסמות המרות מותאמות שמזכירות מצב בריאותי. אסור לקרוא לאירועי Pixel בשמות כמו "adhd" או "focus_score", ואסור לשלוח למטא מידע על אבחנה.
- **מחקר בתוך האפליקציה:** מחקר בריאותי על משתמשים מחייב הסכמה מדעת ואישור של ועדת אתיקה בלתי תלויה (סעיף 5.1.3). פירוט ב־[USER_STUDY_PLAN.md](USER_STUDY_PLAN.md).
