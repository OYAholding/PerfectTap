import SwiftUI
import Charts

// MARK: - TimingProgressView
//
// Personal trend of Practice Session timing statistics. Only sessions of the
// same length (same protocol) are compared, so the curve reflects practice at
// one fixed task. Copy deliberately avoids attention/ADHD/medical language
// (docs/research/COMPLIANCE.md): these are game statistics.

struct TimingProgressView: View {
    @EnvironmentObject var router: AppRouter
    @State private var duration = PracticeSession.selectedDuration
    @State private var sessions: [SessionMetrics] = []

    private let accent = Color(red: 0.13, green: 0.60, blue: 0.68)

    var body: some View {
        ZStack {
            Color(red: 0.039, green: 0.039, blue: 0.059).ignoresSafeArea()
            VStack(spacing: 0) {
                header
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 16) {
                        lengthPicker
                        if sessions.isEmpty {
                            emptyState
                        } else {
                            summaryCards
                            if sessions.count >= 2 { trendChart }
                            recentList
                        }
                        disclaimer
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 40)
                }
            }
        }
        .navigationBarHidden(true)
        .onAppear(perform: reload)
        .onChange(of: duration) { _ in reload() }
    }

    private func reload() {
        let key = PracticeSession.protocolKey(duration: duration)
        sessions = SessionMetricsStore.shared.sessions(protocolKey: key)
    }

    /// Oldest → newest, completed sessions only (a quit session is shorter
    /// and not comparable).
    private var chronological: [SessionMetrics] {
        sessions.filter(\.completed).reversed()
    }

    // MARK: Sections

    private var header: some View {
        HStack {
            Button { router.pop() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white.opacity(0.6))
                    .padding(12)
                    .background(Color.white.opacity(0.05))
                    .clipShape(Circle())
            }
            .accessibilityLabel("Back")
            Spacer()
            Text("PROGRESS")
                .font(.system(size: 14, weight: .black))
                .tracking(4)
                .foregroundColor(.white)
            Spacer()
            Color.clear.frame(width: 44, height: 44)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    private var lengthPicker: some View {
        Picker("Practice length", selection: $duration) {
            ForEach(PracticeSession.durations, id: \.self) { d in
                Text("\(d / 60) min").tag(d)
            }
        }
        .pickerStyle(.segmented)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Text("📈").font(.system(size: 40))
            Text("No \(duration / 60)-minute Practice Sessions yet")
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(.white)
            Text("Practice Session uses the same pace and length every time, so your sessions can be compared.")
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.5))
                .multilineTextAlignment(.center)
            Button {
                PracticeSession.selectedDuration = duration
                router.push(.game(.practice))
            } label: {
                Text("START PRACTICE")
                    .font(.system(size: 13, weight: .black))
                    .tracking(2)
                    .padding(.horizontal, 20).padding(.vertical, 12)
                    .background(accent.opacity(0.35))
                    .foregroundColor(.white)
                    .clipShape(Capsule())
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .background(Color.white.opacity(0.04))
        .cornerRadius(20)
    }

    private var summaryCards: some View {
        let completed = chronological
        let best = completed.min(by: { $0.sdErrorMs < $1.sdErrorMs })
        let last = sessions.first
        return HStack(spacing: 10) {
            card(label: "LAST CONSISTENCY", value: last.map { "±\(Int($0.sdErrorMs.rounded())) ms" } ?? "–")
            card(label: "BEST CONSISTENCY", value: best.map { "±\(Int($0.sdErrorMs.rounded())) ms" } ?? "–")
            card(label: "SESSIONS", value: "\(sessions.count)")
        }
    }

    private func card(label: String, value: String) -> some View {
        VStack(spacing: 6) {
            Text(label)
                .font(.system(size: 8, weight: .bold))
                .tracking(1.5)
                .foregroundColor(.white.opacity(0.4))
                .multilineTextAlignment(.center)
            Text(value)
                .font(.system(size: 16, weight: .bold, design: .monospaced))
                .foregroundColor(.white)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Color.white.opacity(0.04))
        .cornerRadius(14)
    }

    private var trendChart: some View {
        let points = Array(chronological.suffix(30).enumerated())
        return VStack(alignment: .leading, spacing: 8) {
            Text("TIMING SPREAD PER SESSION (LOWER = MORE CONSISTENT)")
                .font(.system(size: 9, weight: .bold))
                .tracking(1.5)
                .foregroundColor(.white.opacity(0.4))
            Chart {
                ForEach(points, id: \.element.id) { index, s in
                    LineMark(x: .value("Session", index + 1), y: .value("Spread (ms)", s.sdErrorMs))
                        .foregroundStyle(accent)
                    PointMark(x: .value("Session", index + 1), y: .value("Spread (ms)", s.sdErrorMs))
                        .foregroundStyle(accent)
                }
            }
            .chartXAxisLabel("Session")
            .chartYAxisLabel("ms")
            .frame(height: 180)
            .accessibilityLabel("Timing spread per session")
        }
        .padding(16)
        .background(Color.white.opacity(0.04))
        .cornerRadius(20)
    }

    private var recentList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("RECENT SESSIONS")
                .font(.system(size: 9, weight: .bold))
                .tracking(1.5)
                .foregroundColor(.white.opacity(0.4))
            ForEach(sessions.prefix(10)) { s in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(s.date, style: .date)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.white.opacity(0.8))
                        Text(s.completed ? "\(s.taps) taps" : "\(s.taps) taps • ended early")
                            .font(.system(size: 10))
                            .foregroundColor(.white.opacity(0.4))
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("±\(Int(s.sdErrorMs.rounded())) ms")
                            .font(.system(size: 13, weight: .bold, design: .monospaced))
                            .foregroundColor(.white)
                        Text(PracticeSummary.biasText(s.meanSignedErrorMs))
                            .font(.system(size: 10))
                            .foregroundColor(.white.opacity(0.45))
                    }
                }
                .padding(12)
                .background(Color.white.opacity(0.03))
                .cornerRadius(12)
            }
        }
    }

    private var disclaimer: some View {
        Text(PracticeSummary.disclaimer)
            .font(.system(size: 11))
            .foregroundColor(.white.opacity(0.4))
            .multilineTextAlignment(.center)
            .padding(.top, 8)
    }
}

// MARK: - Shared copy / formatting

enum PracticeSummary {
    static let disclaimer = "These numbers describe your timing in PerfectTap only. They are not a medical, attention or diagnostic measure."

    /// "Average 6 ms late" / "Average 4 ms early" / "On time on average".
    static func biasText(_ meanMs: Double) -> String {
        let v = Int(abs(meanMs).rounded())
        if v == 0 { return "On time on average" }
        return "Average \(v) ms \(meanMs < 0 ? "early" : "late")"
    }
}
