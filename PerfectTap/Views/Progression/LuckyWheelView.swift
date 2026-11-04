import SwiftUI

// MARK: - LuckyWheelView (ported from LuckyWheel.jsx)
struct LuckyWheelView: View {
    @EnvironmentObject var router: AppRouter
    @State private var rotation: Double = 0
    @State private var isSpinning = false
    @State private var result: String? = nil
    @State private var canSpin = true
    @State private var profile: PlayerProfile = PlayerProfile.load() ?? PlayerProfile()
    @State private var availabilityMessage: String? = nil
    @State private var authoritativeDay: String? = nil
    @State private var spinRequestReserved = false

    private let segments: [(label: String, color: Color, coins: Int)] = [
        ("25 🪙",  Color(red: 0.59, green: 0.28, blue: 0.98), 25),
        ("50 🪙",  Color(red: 0.22, green: 0.82, blue: 0.98), 50),
        ("10 🪙",  Color(red: 0.85, green: 0.28, blue: 0.94), 10),
        ("100 🪙", Color(red: 0.98, green: 0.73, blue: 0.26), 100),
        ("35 🪙",  Color(red: 0.22, green: 0.82, blue: 0.49), 35),
        ("5 🪙",   Color(red: 0.95, green: 0.24, blue: 0.37), 5),
        ("250 🪙", Color(red: 0.98, green: 0.45, blue: 0.10), 250),
        ("75 🪙",  Color(red: 0.47, green: 0.18, blue: 0.85), 75),
    ]
    private let wheelLastSpinDayKey = "perfecttap_wheel_last_spin_server_day"
    private let wheelLegacyLastSpinKey = "perfecttap_last_spin"
    private let wheelPendingSpinIDKey = "perfecttap_wheel_pending_spin_id"
    private let wheelPendingSpinDayKey = "perfecttap_wheel_pending_spin_day"
    private let wheelPendingSpinIndexKey = "perfecttap_wheel_pending_spin_index"
    private let wheelRewardedSpinIDsKey = "perfecttap_wheel_rewarded_spin_ids"

    var body: some View {
        ZStack {
            Color(red: 0.039, green: 0.039, blue: 0.059).ignoresSafeArea()

            VStack(spacing: 0) {
                navBar(title: "LUCKY WHEEL") { router.pop() }

                Text("1 free spin per day")
                    .font(.system(size: 11)).tracking(2)
                    .foregroundColor(.white.opacity(0.3))
                    .padding(.bottom, 32)

                // Wheel
                ZStack {
                    ForEach(0..<segments.count, id: \.self) { i in
                        WheelSegment(
                            index: i,
                            total: segments.count,
                            color: segments[i].color,
                            label: segments[i].label
                        )
                    }
                    // Center
                    Circle()
                        .fill(Color(red: 0.08, green: 0.08, blue: 0.12))
                        .frame(width: 50, height: 50)
                        .overlay(Circle().stroke(Color.white.opacity(0.2), lineWidth: 2))
                }
                .frame(width: 280, height: 280)
                .rotationEffect(.degrees(rotation))
                .animation(isSpinning ? .easeInOut(duration: 3.5) : .default, value: rotation)

                // Pointer
                Triangle()
                    .fill(Color.white)
                    .frame(width: 20, height: 28)
                    .offset(y: -155)
                    .padding(.top, -28)

                Spacer(minLength: 32)

                if let res = result {
                    Text("🎉 You won: \(res)")
                        .font(.system(size: 18, weight: .black))
                        .foregroundColor(.white)
                        .transition(.scale.combined(with: .opacity))
                        .padding(.bottom, 16)
                }
                if let availabilityMessage {
                    Text(availabilityMessage)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white.opacity(0.5))
                        .padding(.bottom, 10)
                }

                Button {
                    Task { await spin() }
                } label: {
                    Text(canSpin ? "SPIN!" : (authoritativeDay == nil ? "UNAVAILABLE" : "COME BACK TOMORROW"))
                        .font(.system(size: 18, weight: .black))
                        .tracking(3)
                        .foregroundColor(canSpin ? .white : .white.opacity(0.4))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 20)
                        .background(
                            canSpin
                            ? AnyView(LinearGradient(colors: [Color(red: 0.59, green: 0.28, blue: 0.98), Color(red: 0.22, green: 0.82, blue: 0.98)], startPoint: .leading, endPoint: .trailing))
                            : AnyView(Color.white.opacity(0.06))
                        )
                        .cornerRadius(20)
                }
                .disabled(!canSpin || isSpinning || spinRequestReserved)
                .padding(.horizontal, 28)
                .padding(.bottom, 40)
            }
        }
        .navigationBarHidden(true)
        .onAppear { Task { await recoverPendingSpinAndRefresh() } }
    }

    private struct PendingWheelSpin {
        let id: String
        let day: String
        let index: Int
    }

    private func recoverPendingSpinAndRefresh() async {
        profile = PlayerProfile.load() ?? PlayerProfile()
        spinRequestReserved = false
        if let pending = loadPendingSpin() {
            finalizePendingSpin(pending, playRewardSound: false)
        }
        await refreshSpinAvailability(forceRefresh: true)
    }

    private func refreshSpinAvailability(forceRefresh: Bool) async {
        let verification = await FirebaseService.shared.authoritativeDayVerification(forceRefresh: forceRefresh)
        if let day = verification.dayKey {
            authoritativeDay = day
            availabilityMessage = verification.usedFallback
                ? "Using last verified server day. Reconnect to refresh availability."
                : nil
            canSpin = loadPendingSpin() == nil && lastConsumedSpinDay() != day
        } else {
            authoritativeDay = nil
            canSpin = false
            availabilityMessage = messageForAvailabilityFailure(verification.failureReason)
        }
    }

    private func spin() async {
        guard canSpin, !isSpinning, !spinRequestReserved else { return }
        spinRequestReserved = true
        defer {
            if !isSpinning {
                spinRequestReserved = false
            }
        }

        let verification = await FirebaseService.shared.authoritativeDayVerification(forceRefresh: true)
        guard let day = verification.dayKey else {
            authoritativeDay = nil
            canSpin = false
            availabilityMessage = messageForAvailabilityFailure(verification.failureReason)
            return
        }
        authoritativeDay = day
        availabilityMessage = verification.usedFallback
            ? "Using last verified server day. Reconnect to refresh availability."
            : nil
        guard loadPendingSpin() == nil else {
            canSpin = false
            return
        }
        guard lastConsumedSpinDay() != day else {
            canSpin = false
            return
        }

        isSpinning = true
        canSpin = false
        result = nil

        let winIndex = Int.random(in: 0..<segments.count)
        let spinID = UUID().uuidString
        persistPendingSpin(id: spinID, day: day, index: winIndex)
        setLastConsumedSpinDay(day)

        let segmentAngle = 360.0 / Double(segments.count)
        // Pointer is at top. To land on the CENTER of winIndex segment:
        // We need rotation such that (-rotation mod 360) = winIndex * segmentAngle + segmentAngle/2
        let targetAngle = 360.0 * 5 + (360.0 - segmentAngle * Double(winIndex) - segmentAngle / 2.0)

        rotation += targetAngle

        DispatchQueue.main.asyncAfter(deadline: .now() + 3.6) {
            guard let pending = loadPendingSpin(), pending.id == spinID else { return }
            finalizePendingSpin(pending, playRewardSound: true)
        }
    }

    private func finalizePendingSpin(_ pending: PendingWheelSpin, playRewardSound: Bool) {
        guard segments.indices.contains(pending.index) else {
            clearPendingSpin()
            isSpinning = false
            spinRequestReserved = false
            return
        }
        setLastConsumedSpinDay(pending.day)
        let won = segments[pending.index]
        var rewarded = loadRewardedSpinIDs()
        if !rewarded.contains(pending.id) {
            EconomyManager.shared.addCoins(won.coins, source: .wheelSpin)
            rewarded.insert(pending.id)
            saveRewardedSpinIDs(rewarded)
            profile = PlayerProfile.load() ?? PlayerProfile()
        }
        result = won.label
        clearPendingSpin()
        isSpinning = false
        spinRequestReserved = false
        if playRewardSound {
            SoundEngine.shared.play(.dailyReward)
        }
        Task { await refreshSpinAvailability(forceRefresh: true) }
    }

    private func loadPendingSpin() -> PendingWheelSpin? {
        let defaults = UserDefaults.standard
        guard let id = defaults.string(forKey: wheelPendingSpinIDKey), !id.isEmpty,
              let day = defaults.string(forKey: wheelPendingSpinDayKey), !day.isEmpty else {
            return nil
        }
        let index = defaults.integer(forKey: wheelPendingSpinIndexKey)
        return PendingWheelSpin(id: id, day: day, index: index)
    }

    private func persistPendingSpin(id: String, day: String, index: Int) {
        let defaults = UserDefaults.standard
        defaults.set(id, forKey: wheelPendingSpinIDKey)
        defaults.set(day, forKey: wheelPendingSpinDayKey)
        defaults.set(index, forKey: wheelPendingSpinIndexKey)
    }

    private func clearPendingSpin() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: wheelPendingSpinIDKey)
        defaults.removeObject(forKey: wheelPendingSpinDayKey)
        defaults.removeObject(forKey: wheelPendingSpinIndexKey)
    }

    private func lastConsumedSpinDay() -> String {
        let defaults = UserDefaults.standard
        if let day = defaults.string(forKey: wheelLastSpinDayKey), !day.isEmpty {
            return day
        }
        // Legacy migration fallback.
        return defaults.string(forKey: wheelLegacyLastSpinKey) ?? ""
    }

    private func setLastConsumedSpinDay(_ day: String) {
        let defaults = UserDefaults.standard
        defaults.set(day, forKey: wheelLastSpinDayKey)
        defaults.set(day, forKey: wheelLegacyLastSpinKey)
    }

    private func loadRewardedSpinIDs() -> Set<String> {
        let ids = UserDefaults.standard.stringArray(forKey: wheelRewardedSpinIDsKey) ?? []
        return Set(ids)
    }

    private func saveRewardedSpinIDs(_ ids: Set<String>) {
        // Keep recent bounded history only.
        let trimmed = Array(ids.prefix(200))
        UserDefaults.standard.set(trimmed, forKey: wheelRewardedSpinIDsKey)
    }

    private func messageForAvailabilityFailure(
        _ reason: FirebaseService.AuthoritativeDayFailureReason?
    ) -> String {
        switch reason {
        case .noInternet:
            return "No internet connection. Wheel spin needs server verification."
        case .firebaseNotConfigured:
            return "Server verification unavailable (Firebase not configured)."
        case .authUnavailable:
            return "Sign-in verification failed. Please reopen the app."
        case .permissionDenied:
            return "Server verification denied by backend permissions."
        case .serverTimestampMissing:
            return "Server time check failed. Please try again."
        case .unknown, .none:
            return "Wheel spin requires server time verification."
        }
    }
}

// MARK: - Wheel segment
private struct WheelSegment: View {
    let index: Int
    let total: Int
    let color: Color
    let label: String

    var body: some View {
        let angle = 360.0 / Double(total)
        let startAngle = Double(index) * angle - 90
        return ZStack {
            Path { path in
                let center = CGPoint(x: 140, y: 140)
                path.move(to: center)
                path.addArc(center: center, radius: 140,
                            startAngle: .degrees(startAngle),
                            endAngle: .degrees(startAngle + angle), clockwise: false)
                path.closeSubpath()
            }
            .fill(color.opacity(0.75))

            // Label
            Text(label)
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.white)
                .rotationEffect(.degrees(startAngle + angle / 2 + 90))
                .offset(
                    x: cos((startAngle + angle / 2) * .pi / 180) * 95,
                    y: sin((startAngle + angle / 2) * .pi / 180) * 95
                )
        }
    }
}

private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.closeSubpath()
        return path
    }
}
