import SwiftUI

// MARK: - DailyRewardsView (ported from DailyRewards.jsx)
struct DailyRewardsView: View {
    @EnvironmentObject var router: AppRouter
    @State private var profile: PlayerProfile = PlayerProfile.load() ?? PlayerProfile()
    @State private var showClaimed = false
    @State private var claimedAmount: Int = 0
    @State private var authoritativeDay: String? = nil
    @State private var eligibilityMessage: String? = nil
    @State private var isClaiming = false

    private let dayRewards = [25, 35, 50, 75, 100, 125, 250]   // coins per day in 7-day cycle
    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
    private static let dayCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        return calendar
    }()

    private var canClaim: Bool {
        guard let day = authoritativeDay else { return false }
        return profile.dailyRewardLastClaim != day
    }

    private var currentDay: Int {
        (profile.dailyRewardStreak % 7)   // 0–6
    }

    var body: some View {
        ZStack {
            Color(red: 0.039, green: 0.039, blue: 0.059).ignoresSafeArea()

            VStack(spacing: 0) {
                navBar(title: "DAILY REWARDS") { router.pop() }

                // Streak
                HStack(spacing: 8) {
                    Text("🔥")
                    Text("\(profile.dailyRewardStreak) day streak")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white.opacity(0.8))
                }
                .padding(.bottom, 24)

                // 7 day grid
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 12) {
                    ForEach(0..<7, id: \.self) { day in
                        dayCard(day: day)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 32)

                // Claim button
                Button {
                    Task { await claimReward() }
                } label: {
                    Text(canClaim ? "CLAIM TODAY'S REWARD" : (authoritativeDay == nil ? "UNAVAILABLE" : "COME BACK TOMORROW"))
                        .font(.system(size: 16, weight: .black))
                        .tracking(2)
                        .foregroundColor(canClaim ? .white : .white.opacity(0.4))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .background(
                            canClaim
                            ? AnyView(LinearGradient(colors: [Color(red: 0.98, green: 0.45, blue: 0.0), Color(red: 0.98, green: 0.73, blue: 0.26)], startPoint: .leading, endPoint: .trailing))
                            : AnyView(Color.white.opacity(0.06))
                        )
                        .cornerRadius(16)
                }
                .disabled(!canClaim || isClaiming)
                .padding(.horizontal, 20)

                if showClaimed {
                    Text("🎉 +\(claimedAmount) coins claimed!")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(Color(red: 0.98, green: 0.73, blue: 0.26))
                        .padding(.top, 16)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                if let eligibilityMessage {
                    Text(eligibilityMessage)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white.opacity(0.5))
                        .padding(.top, 10)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                }

                Spacer()
            }
        }
        .navigationBarHidden(true)
        .onAppear { Task { await refreshEligibility(forceRefresh: true) } }
    }

    private func dayCard(day: Int) -> some View {
        let isPast = day < currentDay
        let isCurrent = day == currentDay
        let isFuture = day > currentDay

        return VStack(spacing: 6) {
            Text("Day \(day + 1)")
                .font(.system(size: 10, weight: .bold))
                .tracking(1)
                .foregroundColor(isCurrent ? Color(red: 0.98, green: 0.73, blue: 0.26) : .white.opacity(0.3))
            Text("🪙")
                .font(.system(size: 20))
                .opacity(isFuture ? 0.3 : 1)
            Text("+\(dayRewards[day])")
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(isPast ? Color(red: 0.22, green: 0.82, blue: 0.49) : isCurrent ? Color(red: 0.98, green: 0.73, blue: 0.26) : .white.opacity(0.25))
        }
        .padding(10)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(isCurrent ? Color(red: 0.98, green: 0.73, blue: 0.26).opacity(0.1) : Color.white.opacity(0.04))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(
                    isCurrent ? Color(red: 0.98, green: 0.73, blue: 0.26).opacity(0.4) :
                    isPast ? Color(red: 0.22, green: 0.82, blue: 0.49).opacity(0.2) : Color.white.opacity(0.07)
                ))
        )
        .overlay(alignment: .topTrailing) {
            if isPast {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundColor(Color(red: 0.22, green: 0.82, blue: 0.49))
                    .offset(x: 4, y: -4)
            }
        }
    }

    private func refreshEligibility(forceRefresh: Bool) async {
        profile = PlayerProfile.load() ?? PlayerProfile()
        let verification = await Backend.shared.authoritativeDayVerification(forceRefresh: forceRefresh)
        if let day = verification.dayKey {
            authoritativeDay = day
            eligibilityMessage = verification.usedFallback
                ? "Using last verified server day. Reconnect to refresh availability."
                : nil
        } else {
            authoritativeDay = nil
            eligibilityMessage = messageForEligibilityFailure(verification.failureReason)
        }
    }

    private func dayDelta(from earlierDay: String, to laterDay: String) -> Int? {
        guard let earlier = Self.dayFormatter.date(from: earlierDay),
              let later = Self.dayFormatter.date(from: laterDay) else { return nil }
        return Self.dayCalendar.dateComponents([.day], from: earlier, to: later).day
    }

    private func claimReward() async {
        guard !isClaiming else { return }
        isClaiming = true
        defer { isClaiming = false }

        let verification = await Backend.shared.authoritativeDayVerification(forceRefresh: true)
        guard let currentDay = verification.dayKey else {
            authoritativeDay = nil
            eligibilityMessage = messageForEligibilityFailure(verification.failureReason)
            return
        }
        authoritativeDay = currentDay
        eligibilityMessage = verification.usedFallback
            ? "Using last verified server day. Reconnect to refresh availability."
            : nil
        guard canClaim else { return }

        profile = EconomyManager.shared.updateProfile { profile in
            // Reset streak if the player missed a day (last claim was not yesterday)
            if !profile.dailyRewardLastClaim.isEmpty {
                if let delta = dayDelta(from: profile.dailyRewardLastClaim, to: currentDay) {
                    if delta != 1 {
                        // Any gap (or rollback) breaks the streak.
                        profile.dailyRewardStreak = 0
                    }
                } else {
                    // Corrupt/legacy date string: fail-safe reset.
                    profile.dailyRewardStreak = 0
                }
            }

            let reward = dayRewards[profile.dailyRewardStreak % dayRewards.count]
            claimedAmount = reward  // store BEFORE incrementing streak
            profile.coins += reward
            profile.stats.totalCoinsEarned += reward
            profile.dailyRewardStreak += 1
            profile.dailyRewardLastClaim = currentDay
        }
        withAnimation { showClaimed = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation { showClaimed = false }
        }
    }

    private func messageForEligibilityFailure(
        _ reason: AuthoritativeDayFailureReason?
    ) -> String {
        switch reason {
        case .noInternet:
            return "No internet connection. Daily rewards need server verification."
        case .firebaseNotConfigured:
            return "Server verification unavailable (Firebase not configured)."
        case .authUnavailable:
            return "Sign-in verification failed. Please reopen the app."
        case .permissionDenied:
            return "Server verification denied by backend permissions."
        case .serverTimestampMissing:
            return "Server time check failed. Please try again."
        case .unknown, .none:
            return "Daily reward requires server time verification."
        }
    }
}
