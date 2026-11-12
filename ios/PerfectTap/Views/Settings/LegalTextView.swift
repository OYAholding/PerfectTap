import SwiftUI

// MARK: - LegalTextView (in-app Privacy Policy & Terms of Use)

struct LegalTextView: View {
    let title: String
    let content: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color(red: 0.039, green: 0.039, blue: 0.059).ignoresSafeArea()

            VStack(spacing: 0) {
                // Nav bar
                HStack {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.white.opacity(0.6))
                            .frame(width: 32, height: 32)
                            .background(Color.white.opacity(0.08))
                            .clipShape(Circle())
                    }

                    Spacer()

                    Text(title)
                        .font(.system(size: 14, weight: .black))
                        .tracking(2)
                        .foregroundColor(.white)

                    Spacer()

                    // Invisible spacer to center title
                    Color.clear.frame(width: 32, height: 32)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)

                Divider().background(Color.white.opacity(0.08))

                ScrollView(showsIndicators: true) {
                    Text(content)
                        .font(.system(size: 13, weight: .regular))
                        .foregroundColor(.white.opacity(0.75))
                        .lineSpacing(5)
                        .padding(20)
                }
            }
        }
    }
}

// MARK: - Public legal pages (GitHub Pages, from website/ in this repo)

enum LegalLinks {
    static let privacy = URL(string: "https://oyaholding.github.io/PerfectTap/")!
    static let terms   = URL(string: "https://oyaholding.github.io/PerfectTap/terms.html")!
    static let support = URL(string: "https://oyaholding.github.io/PerfectTap/support.html")!
    static let contactEmail = "PerfectTap@oyaholding.com"
}

// MARK: - Legal Content (offline fallback; the published pages above are authoritative)

enum LegalContent {

    static let privacyPolicy = """
PRIVACY POLICY — PERFECTTAP
Last updated: March 18, 2026

Welcome to PerfectTap. This Privacy Policy explains how PerfectTap ("we," "us," or "our") collects, uses, stores, and shares information when you use the PerfectTap mobile game, website, and related services (collectively, the "Service").

By downloading, accessing, or using the Service, you acknowledge that you have read this Privacy Policy.

1. Who We Are

PerfectTap is a mobile game application and related service.

If you have any questions about this Privacy Policy, you may contact us at:
Email: PerfectTap@oyaholding.com
Website: https://oyaholding.github.io/PerfectTap/

2. Information We Collect

Depending on how you use the Service, we may collect the following categories of information:

a. Information You Provide
• Messages or inquiries you send to us
• Feedback you voluntarily provide
• Information you provide when contacting us regarding support, purchases, bugs, or account-related issues

b. Gameplay and App Usage Data
We may collect information about how you interact with the game, such as:
• game progress
• scores
• coins, rewards, skins, unlocks, and in-game items
• gameplay settings and preferences
• session activity
• interactions with ads, offers, and in-app purchase screens

c. Device and Technical Data
We may collect technical data necessary to operate, secure, maintain, and improve the Service, such as:
• device type
• operating system and version
• app version
• language
• country or region
• performance data
• diagnostic information
• crash reports
• error logs

d. Purchase Information
If you make an in-app purchase, the transaction is processed by Apple or the applicable platform provider, not directly by us. We may receive limited transaction-related information required to validate purchases and deliver purchased content, such as:
• product identifier
• purchase status
• receipt validation result
• entitlement or content delivery status

e. Advertising and Analytics Data
If the Service uses advertising, analytics, or similar tools, we or our service providers may collect information relating to:
• ad impressions
• rewarded ad completions
• attribution events
• engagement metrics
• identifiers or similar technical data where permitted by applicable law and platform rules

3. How We Use Information

We may use collected information to:
• provide and operate the Service
• save game progress and entitlements
• deliver coins, items, cosmetics, and ad-related rewards
• verify purchases and prevent fraud
• maintain security and integrity of the Service
• diagnose bugs, crashes, abuse, or misuse
• improve gameplay, balance, monetization, and performance
• provide support
• comply with legal obligations
• enforce our Terms of Use

4. Legal Bases

Where required by applicable law, we process personal data on one or more of the following legal bases:
• performance of a contract
• legitimate interests
• compliance with legal obligations
• consent, where required

5. Sharing of Information

We do not sell your personal information for money.

We may share information with trusted third-party service providers where reasonably necessary to operate the Service, including:
• cloud hosting providers
• analytics providers
• crash reporting providers
• advertising partners
• payment and platform providers such as Apple
• security, fraud prevention, and anti-abuse providers

We may also disclose information:
• where required by law, regulation, legal process, or governmental request
• to protect rights, safety, property, or security
• in connection with a merger, acquisition, restructuring, financing, or sale of assets

6. Data Retention

We retain information only for as long as reasonably necessary for purposes such as:
• operating the Service
• maintaining gameplay functionality and purchase records
• preventing fraud and abuse
• resolving disputes
• complying with legal, tax, accounting, and regulatory obligations

Retention periods may vary depending on the type of information and applicable law.

7. Data Security

We use reasonable technical and organizational safeguards intended to protect information against unauthorized access, misuse, loss, alteration, or disclosure. However, no system is completely secure, and we cannot guarantee absolute security.

8. Children

PerfectTap is not directed to children under the minimum age permitted by applicable law, unless explicitly stated otherwise in the product design, age rating, or platform listing. If we learn that we have collected personal information in violation of applicable law, we may delete such information.

9. International Transfers

Your information may be processed or stored in countries outside your country of residence, including countries that may have different data protection laws.

10. Your Rights

Depending on your location, you may have rights to:
• request access to personal data
• request correction
• request deletion
• request restriction of processing
• object to certain processing
• request data portability
• withdraw consent where processing is based on consent

To exercise applicable rights, contact us at: PerfectTap@oyaholding.com

11. Third-Party Services

The Service may rely on third-party services, SDKs, and platforms, including Apple, analytics providers, advertising providers, and backend infrastructure providers. Those third parties may process information under their own privacy policies and legal terms.

12. In-App Purchases

In-app purchases are processed by Apple or the applicable platform provider. We do not directly store your full payment card details. We may process limited purchase-related information needed to confirm purchases, deliver content, restore entitlements where applicable, and prevent fraud.

13. Advertising

If the Service includes advertisements, including rewarded ads, advertising partners may collect or receive data in accordance with their own technologies, legal obligations, and privacy practices.

Tracking only with your permission: before any tracking, the app asks through Apple's App Tracking Transparency prompt. Only if you choose "Allow" can Google use your device's advertising identifier (IDFA) for personalized ads. If you choose "Ask App Not to Track", the advertising identifier is not accessed, ads are not personalized, and no advertising signals are sent from Firebase Analytics. The game works the same either way. You can change this in iOS Settings → Privacy & Security → Tracking, or in the app under Settings → Privacy. Where the law requires it (EEA, UK, Switzerland), Google's consent message is shown before ads are requested, and you can change your choice under Settings → Privacy → Privacy Choices.

14. Changes to This Privacy Policy

We may update this Privacy Policy from time to time. The updated version will be posted at:
https://oyaholding.github.io/PerfectTap/

The "Last updated" date will be revised accordingly. Your continued use of the Service after any update constitutes your acknowledgment of the revised Privacy Policy to the extent permitted by law.

15. Contact Us

If you have questions about this Privacy Policy, you may contact us at:
PerfectTap@oyaholding.com
"""

    static let termsOfUse = """
TERMS OF USE — PERFECTTAP
Last updated: March 18, 2026

These Terms of Use ("Terms") govern your use of the PerfectTap mobile game, website, and related services (the "Service"). By downloading, accessing, or using the Service, you agree to these Terms.

1. Eligibility

You may use the Service only if you are legally permitted to do so under applicable law and under the rules of the platform through which you download or access the app.

2. License

We grant you a limited, non-exclusive, non-transferable, revocable license to use the Service for personal, non-commercial entertainment purposes, subject to these Terms.

You may not:
• copy, modify, distribute, sell, lease, sublicense, or commercially exploit any part of the Service except as permitted by law
• reverse engineer, decompile, or attempt to extract source code except where such restriction is prohibited by law
• exploit bugs, cheats, automation, or unauthorized tools
• interfere with the integrity, availability, or security of the Service

3. Game Experience

PerfectTap is provided as a skill-based entertainment game. Your enjoyment, results, progress, and outcomes may vary.

We do not guarantee:
• uninterrupted access
• error-free operation
• permanent availability of any feature, mode, reward, cosmetic item, or offer
• compatibility with all devices, regions, or operating system versions at all times

We reserve the right to update, rebalance, modify, suspend, limit, or discontinue any aspect of the Service at any time.

4. In-App Purchases

The Service may offer digital items, virtual currency, cosmetic content, reward-based features, or ad-removal features through in-app purchases.

By making a purchase, you acknowledge that:
• purchases are processed by Apple or the applicable platform provider
• digital items are licensed, not sold
• virtual currency and virtual items have no cash value
• purchases are non-transferable
• availability of purchased content may depend on your account, platform, app version, and technical integrity of the Service

Where technically appropriate and supported, we may allow restoration of eligible non-consumable purchases in accordance with platform rules.

5. Refunds

Except where required by applicable law or granted by Apple or the applicable platform provider under its policies, purchases are generally final.

Refund requests for App Store purchases are handled by Apple under Apple's own procedures and policies. Nothing in these Terms limits any non-waivable consumer rights you may have under applicable law.

6. User Conduct

You agree not to:
• use the Service for unlawful purposes
• exploit bugs or vulnerabilities
• attempt to manipulate ads, purchases, rewards, progression systems, or gameplay outcomes
• use bots, scripts, automation, emulators, unauthorized modifications, or third-party tools to gain unfair advantage
• harass, threaten, abuse, defraud, or impersonate others through any support or community channel
• upload malware or otherwise interfere with the Service

7. Suspension and Termination

We may suspend, restrict, or terminate access to the Service, with or without notice, if we reasonably believe:
• you violated these Terms
• fraud, abuse, cheating, manipulation, or unauthorized use occurred
• technical, legal, security, operational, or business reasons require action
• the Service must be secured, changed, or discontinued

8. Intellectual Property

The Service, including its code, design, name, branding, visuals, sounds, music, mechanics, text, graphics, features, and other content, is owned by or licensed to us and is protected by applicable intellectual property laws.

You may not use our intellectual property without prior written permission.

9. No Professional or Safety Reliance

The Service is provided solely for entertainment purposes. You are responsible for using the Service in a safe, reasonable, and lawful manner and for maintaining awareness of your environment while using your device.

Do not use the Service in any situation where distraction may cause injury, damage, theft, loss, danger, or violation of law.

10. Disclaimer of Warranties

To the maximum extent permitted by applicable law, the Service is provided on an "AS IS" and "AS AVAILABLE" basis, without warranties of any kind, whether express, implied, or statutory, including implied warranties of merchantability, fitness for a particular purpose, title, non-infringement, availability, or uninterrupted use.

We do not warrant that:
• the Service will always be available
• the Service will be error-free, uninterrupted, or secure
• defects will always be corrected
• the Service will meet every user's expectations
• the Service will be compatible with every device or environment

11. Limitation of Liability

To the maximum extent permitted by applicable law, we, our affiliates, licensors, contractors, and service providers shall not be liable for any indirect, incidental, special, consequential, exemplary, or punitive damages, or for any loss of profits, revenues, data, goodwill, business opportunity, or device use arising out of or related to the Service.

To the maximum extent permitted by applicable law, we shall also not be liable for:
• frustration, disappointment, anger, stress, or emotional reaction arising from gameplay
• interruptions, lag, bugs, crashes, balancing changes, progression resets, or reward issues
• device distraction, dropping, loss, theft, misuse, or unavailability occurring while the user is playing
• alleged damage resulting from use of the Service in unsafe, inattentive, distracted, risky, or unauthorized circumstances
• third-party platform outages, billing failures, ad network interruptions, analytics issues, connectivity problems, or hosting failures
• unauthorized access to your device or account caused by your own negligence or circumstances beyond our reasonable control

For the avoidance of doubt, PerfectTap is software intended for entertainment only and is not designed to physically damage a user's device. However, you remain solely responsible for how, where, and under what circumstances you use your device while engaging with the Service.

Nothing in these Terms excludes or limits liability that cannot be excluded or limited under applicable law.

12. Device and Environmental Responsibility

You are solely responsible for:
• keeping your device secure
• using appropriate physical protection for your device
• supervising your surroundings while playing
• avoiding play during dangerous, distracting, or inappropriate situations
• complying with all laws, regulations, and safety obligations while using your device

13. Third-Party Services

The Service may include, depend on, or interact with third-party services and platforms, including Apple, analytics providers, ad networks, payment systems, cloud infrastructure, and related vendors. We are not responsible for third-party services, billing systems, outages, policies, or content.

14. Updates and Changes

We may modify these Terms at any time. Updated Terms will be posted at:
https://oyaholding.github.io/PerfectTap/terms.html

Continued use of the Service after updated Terms become effective constitutes acceptance of the revised Terms, except where further consent is required by law.

15. Right to Modify, Suspend, or Discontinue the Service

You understand and agree that PerfectTap is an independently developed entertainment product and may be changed, paused, restricted, removed, or discontinued at any time.

We reserve the right, at any time, in our sole discretion, with or without prior notice, to modify, limit, suspend, remove, discontinue, or terminate the Service, in whole or in part, for any reason or for no stated reason, including technical, operational, legal, security, creative, business, financial, product-development, maintenance, or strategic reasons.

This includes, without limitation, the right to:
• shut down the game entirely
• remove features, modes, rewards, ads, items, purchases, currencies, or cosmetic content
• reset, rebalance, alter, or discontinue progression systems, game economy, and availability
• stop supporting certain devices, territories, versions, or operating systems
• suspend future development, maintenance, or support
• permanently discontinue access to the Service

You acknowledge and agree that the Service may be changed, interrupted, limited, or discontinued at any time, and that we shall not be liable to you for any modification, suspension, discontinuation, unavailability, or termination of the Service, except to the extent liability cannot be excluded under applicable law.

Nothing in these Terms limits any non-waivable rights you may have under applicable consumer protection laws.

16. Governing Law

These Terms shall be governed by the laws of the State of Israel, excluding conflict-of-law principles, unless otherwise required by applicable consumer protection law.

17. Severability

If any provision of these Terms is found to be invalid, unlawful, or unenforceable, the remaining provisions shall remain in full force and effect to the maximum extent permitted by law.

18. Contact

For support, legal inquiries, or questions regarding the Service, contact:
PerfectTap@oyaholding.com
"""
}
