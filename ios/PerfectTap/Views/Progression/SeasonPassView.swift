import SwiftUI

// MARK: - SeasonPassView (Season Pass with ad-based premium unlock)
struct SeasonPassView: View {
    @EnvironmentObject var router: AppRouter
    @State private var profile: PlayerProfile = PlayerProfile.load() ?? PlayerProfile()
    @State private var isWatchingAd = false
    @State private var showRewardUnavailableAlert = false
    @State private var rewardUnavailableMessage = ""

    private static let adsRequired = 50

    private var currentTier: Int { profile.seasonTier }
    private var tierProgress: Double {
        let xpInTier = profile.seasonXP % GameConfig.seasonXPPerTier
        return Double(xpInTier) / Double(GameConfig.seasonXPPerTier)
    }

    var body: some View {
        ZStack {
            Color(red: 0.039, green: 0.039, blue: 0.059).ignoresSafeArea()

            VStack(spacing: 0) {
                navBar(title: "SEASON PASS") { router.pop() }

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 16) {
                        // Season header
                        seasonHeader

                        // Tier XP progress
                        tierProgressBar

                        // Premium unlock banner (or unlocked badge)
                        if profile.seasonPremium {
                            premiumUnlockedBadge
                                .padding(.horizontal, 20)
                        } else {
                            premiumUnlockBanner
                                .padding(.horizontal, 20)
                        }

                        // Tiers scroll
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(SeasonTier.season1Tiers) { tier in
                                    let claimed = profile.seasonClaimedTiers.contains(tier.id)
                                    let premMarker = "sp_prem_\(tier.id)"
                                    let pendingPrem = claimed && profile.seasonPremium && tier.premiumReward != nil && !profile.ownedItems.contains(premMarker)
                                    TierCard(
                                        tier: tier,
                                        currentTier: currentTier,
                                        isPremium: profile.seasonPremium,
                                        isClaimed: claimed,
                                        hasPendingPremium: pendingPrem,
                                        onClaim: { claimTierRewards(tier) }
                                    )
                                }
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 12)
                        }
                    }
                    .padding(.bottom, 40)
                }
            }
        }
        .navigationBarHidden(true)
        .onAppear {
            // Reload profile to get latest state
            profile = PlayerProfile.load() ?? profile
        }
        .alert("Reward Temporarily Unavailable", isPresented: $showRewardUnavailableAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(rewardUnavailableMessage)
        }
    }

    // MARK: - Season Header

    private var seasonHeader: some View {
        VStack(spacing: 8) {
            HStack {
                Text("⚡")
                Text("Season 1: Neon Nights")
                    .font(.system(size: 16, weight: .black))
                    .foregroundColor(.white)
            }
            Text("Mar 1 – May 31, 2026")
                .font(.system(size: 11)).tracking(2)
                .foregroundColor(.white.opacity(0.4))
            Text("Tier \(max(1, currentTier)) / 30")
                .font(.system(size: 22, weight: .black))
                .foregroundStyle(LinearGradient(colors: [Color(red: 0.98, green: 0.73, blue: 0.26), Color(red: 0.98, green: 0.45, blue: 0.10)], startPoint: .leading, endPoint: .trailing))
        }
        .padding(.vertical, 16)
    }

    // MARK: - Tier XP Progress Bar

    private var tierProgressBar: some View {
        VStack(spacing: 6) {
            HStack {
                Text("Season XP: \(profile.seasonXP)")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.5))
                Spacer()
                Text("\(profile.seasonXP % GameConfig.seasonXPPerTier) / \(GameConfig.seasonXPPerTier) XP")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Color(red: 0.98, green: 0.73, blue: 0.26))
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.06)).frame(height: 8)
                    Capsule()
                        .fill(LinearGradient(colors: [Color(red: 0.98, green: 0.73, blue: 0.26), Color(red: 0.98, green: 0.45, blue: 0.10)], startPoint: .leading, endPoint: .trailing))
                        .frame(width: geo.size.width * tierProgress, height: 8)
                }
            }
            .frame(height: 8)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 4)
    }

    // MARK: - Premium Unlocked Badge

    private var premiumUnlockedBadge: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 22))
                .foregroundColor(Color(red: 0.98, green: 0.73, blue: 0.26))
            VStack(alignment: .leading, spacing: 2) {
                Text("PREMIUM UNLOCKED")
                    .font(.system(size: 13, weight: .black)).tracking(2)
                    .foregroundColor(Color(red: 0.98, green: 0.73, blue: 0.26))
                Text("All premium rewards are available")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.5))
            }
            Spacer()
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(red: 0.98, green: 0.73, blue: 0.26).opacity(0.08)).overlay(RoundedRectangle(cornerRadius: 16).stroke(Color(red: 0.98, green: 0.73, blue: 0.26).opacity(0.25))))
    }

    // MARK: - Premium Unlock Banner (ad-based)

    private var premiumUnlockBanner: some View {
        let progress = min(profile.seasonAdProgress, Self.adsRequired)
        let fraction = Double(progress) / Double(Self.adsRequired)

        return VStack(spacing: 12) {
            Text("👑 Unlock Premium Track")
                .font(.system(size: 15, weight: .black))
                .foregroundColor(.white)
            Text("Watch rewarded ads to unlock exclusive avatars, themes, and badges")
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.5))
                .multilineTextAlignment(.center)

            // Progress bar
            VStack(spacing: 6) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.08)).frame(height: 12)
                        Capsule()
                            .fill(LinearGradient(colors: [Color(red: 0.59, green: 0.28, blue: 0.98), Color(red: 0.98, green: 0.73, blue: 0.26)], startPoint: .leading, endPoint: .trailing))
                            .frame(width: max(0, geo.size.width * fraction), height: 12)
                    }
                }
                .frame(height: 12)

                Text("\(progress) / \(Self.adsRequired) ads completed")
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundColor(Color(red: 0.98, green: 0.73, blue: 0.26))
            }

            // Watch Ad button
            Button {
                guard !isWatchingAd else { return }
                isWatchingAd = true
                Task {
                    let success = await AdManager.shared.showRewardedAd(placement: .seasonPassUnlock)
                    if success {
                        profile = EconomyManager.shared.updateProfile { profile in
                            profile.seasonAdProgress += 1
                            if profile.seasonAdProgress >= Self.adsRequired {
                                profile.seasonPremium = true
                            }
                        }
                    }
                    isWatchingAd = false
                }
            } label: {
                HStack(spacing: 8) {
                    if isWatchingAd {
                        ProgressView().tint(.white).scaleEffect(0.8)
                    } else {
                        Image(systemName: "play.circle.fill").font(.system(size: 18))
                    }
                    Text(isWatchingAd ? "WATCHING AD…" : "WATCH AD (+1)")
                        .font(.system(size: 14, weight: .black))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(LinearGradient(colors: [Color(red: 0.59, green: 0.28, blue: 0.98), Color(red: 0.22, green: 0.82, blue: 0.98)], startPoint: .leading, endPoint: .trailing))
                .cornerRadius(14)
            }
            .disabled(isWatchingAd)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 20).fill(Color(red: 0.98, green: 0.73, blue: 0.26).opacity(0.06)).overlay(RoundedRectangle(cornerRadius: 20).stroke(Color(red: 0.98, green: 0.73, blue: 0.26).opacity(0.2))))
    }

    // MARK: - Claim Tier Rewards

    private func claimTierRewards(_ tier: SeasonTier) {
        profile = EconomyManager.shared.updateProfile { profile in
            guard tier.id <= profile.seasonTier else { return }

            let alreadyClaimed = profile.seasonClaimedTiers.contains(tier.id)

            if !alreadyClaimed {
                // First-time claim: grant free reward
                if let reward = tier.freeReward {
                    _ = grantReward(reward, tierID: tier.id, profile: &profile)
                }
                // Grant premium reward too if premium is already unlocked
                if profile.seasonPremium, let reward = tier.premiumReward {
                    let granted = grantReward(reward, tierID: tier.id, profile: &profile)
                    if granted {
                        // Mark premium reward as granted so it won't double-grant later
                        let marker = "sp_prem_\(tier.id)"
                        if !profile.ownedItems.contains(marker) { profile.ownedItems.append(marker) }
                    }
                }
                profile.seasonClaimedTiers.append(tier.id)
            } else if profile.seasonPremium, let reward = tier.premiumReward {
                // Already claimed free, but user unlocked premium later —
                // grant the premium reward if not already granted
                let marker = "sp_prem_\(tier.id)"
                if !profile.ownedItems.contains(marker) {
                    let granted = grantReward(reward, tierID: tier.id, profile: &profile)
                    if granted {
                        profile.ownedItems.append(marker)
                    }
                }
            }
        }
    }

    private func grantReward(_ reward: SeasonReward, tierID: Int, profile: inout PlayerProfile) -> Bool {
        switch reward.type {
        case .coins(let amount):
            profile.coins += amount
            profile.stats.totalCoinsEarned += amount
            return true
        case .avatar(let id):
            guard knownAvatarRewardIDs.contains(id) else {
                flagUnavailableReward(category: "avatar", rewardID: id, tierID: tierID)
                return false
            }
            if !profile.ownedItems.contains(id) {
                profile.ownedItems.append(id)
            }
            return true
        case .theme(let name):
            guard knownThemeRewardNames.contains(name) else {
                flagUnavailableReward(category: "theme", rewardID: name, tierID: tierID)
                return false
            }
            let themeID = "theme_\(name)"
            if !profile.ownedItems.contains(themeID) {
                profile.ownedItems.append(themeID)
            }
            return true
        case .badge(let id):
            guard knownBadgeRewardIDs.contains(id) else {
                flagUnavailableReward(category: "badge", rewardID: id, tierID: tierID)
                return false
            }
            if !profile.ownedItems.contains(id) {
                profile.ownedItems.append(id)
            }
            return true
        }
    }

    private var knownAvatarRewardIDs: Set<String> {
        Set(ShopItem.avatars.map { $0.id })
    }

    private var knownThemeRewardNames: Set<String> {
        Set(AppTheme.all.map { $0.name })
    }

    private var knownBadgeRewardIDs: Set<String> {
        Set(ShopItem.badges.map { $0.id })
    }

    private func flagUnavailableReward(category: String, rewardID: String, tierID: Int) {
        AnalyticsService.logSeasonRewardUnavailable(category: category, rewardId: rewardID, tier: tierID)
        #if DEBUG
        print("[SeasonPass] Unavailable reward ID '\(rewardID)' for category '\(category)' in tier \(tierID)")
        #endif
        rewardUnavailableMessage = "Tier \(tierID) reward (\(rewardID)) is temporarily unavailable and was not granted. Please try again in a future update."
        showRewardUnavailableAlert = true
    }
}

// MARK: - Tier Card

private struct TierCard: View {
    let tier: SeasonTier
    let currentTier: Int
    let isPremium: Bool
    let isClaimed: Bool
    let hasPendingPremium: Bool   // true if claimed free but premium reward not yet collected
    let onClaim: () -> Void

    private var isUnlocked: Bool { tier.id <= currentTier }
    private var canClaim: Bool { isUnlocked && (!isClaimed || hasPendingPremium) }

    var body: some View {
        VStack(spacing: 8) {
            Text("Tier \(tier.id)")
                .font(.system(size: 10, weight: .black))
                .tracking(1)
                .foregroundColor(isUnlocked ? Color(red: 0.98, green: 0.73, blue: 0.26) : .white.opacity(0.3))

            // Free reward
            rewardBox(reward: tier.freeReward, unlocked: isUnlocked, isPremiumRequired: false)

            // Premium reward
            if let premReward = tier.premiumReward {
                rewardBox(reward: premReward, unlocked: isUnlocked && isPremium, isPremiumRequired: true)
            } else {
                Color.clear.frame(width: 70, height: 70)
            }

            // Claim button
            if isClaimed && !hasPendingPremium {
                Text("CLAIMED")
                    .font(.system(size: 8, weight: .black)).tracking(1)
                    .foregroundColor(Color(red: 0.22, green: 0.82, blue: 0.49))
            } else if canClaim {
                Button(action: onClaim) {
                    Text(hasPendingPremium ? "CLAIM ★" : "CLAIM")
                        .font(.system(size: 9, weight: .black)).tracking(1)
                        .foregroundColor(.white)
                        .padding(.horizontal, 12).padding(.vertical, 5)
                        .background(LinearGradient(colors: [Color(red: 0.98, green: 0.73, blue: 0.26), Color(red: 0.98, green: 0.45, blue: 0.10)], startPoint: .leading, endPoint: .trailing))
                        .cornerRadius(8)
                }
            } else {
                Text("LOCKED")
                    .font(.system(size: 8, weight: .black)).tracking(1)
                    .foregroundColor(.white.opacity(0.2))
            }
        }
        .frame(width: 90)
    }

    private func rewardBox(reward: SeasonReward?, unlocked: Bool, isPremiumRequired: Bool) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(unlocked ? (isPremiumRequired ? Color(red: 0.98, green: 0.73, blue: 0.26).opacity(0.15) : Color.white.opacity(0.08)) : Color.white.opacity(0.03))
                .frame(width: 70, height: 70)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(
                    unlocked ? (isPremiumRequired ? Color(red: 0.98, green: 0.73, blue: 0.26).opacity(0.4) : Color.white.opacity(0.2)) : Color.white.opacity(0.06)
                ))

            if let reward = reward {
                VStack(spacing: 3) {
                    Text(reward.icon).font(.system(size: unlocked ? 24 : 18)).opacity(unlocked ? 1 : 0.3)
                    Text(reward.label.prefix(8)).font(.system(size: 7, weight: .bold)).foregroundColor(.white.opacity(unlocked ? 0.6 : 0.2)).lineLimit(1)
                }
            }

            if isPremiumRequired && !isPremium {
                Image(systemName: "lock.fill").font(.system(size: 14)).foregroundColor(.white.opacity(0.3))
            }
        }
    }
}
