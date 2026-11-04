import SwiftUI

// MARK: - TapBar (ported from TapBar.jsx)
// Shows the moving indicator bouncing between left and right.
// Position is driven by GameViewModel's IndicatorRelay (0.0–1.0).
// Only TapBarView observes the relay, so only this view re-renders at 60fps —
// the parent GameView is NOT re-evaluated every frame.

struct TapBarView: View {
    /// The relay that publishes indicator position at 60fps
    @ObservedObject var indicatorRelay: IndicatorRelay
    let theme: AppTheme
    var hideZones: Bool = false
    var perfectZoneScale: Double = 1.0
    var strictPerfectOnly: Bool = false

    // Zone boundaries (matching GameConfig accuracy zones)
    private let perfectHalf: CGFloat = 0.04   // ±4% from center (before scaling)
    private let greatHalf: CGFloat   = 0.10   // ±10%
    private let goodHalf: CGFloat    = 0.20   // ±20%

    var body: some View {
        VStack(spacing: 6) {
            // Labels row
            HStack {
                Text("◀")
                Spacer()
                Text("AIM FOR CENTER")
                    .tracking(3)
                Spacer()
                Text("▶")
            }
            .font(.system(size: 11))
            .foregroundColor(.white.opacity(0.25))

            // Bar
            GeometryReader { geo in
                let w = geo.size.width
                let h = geo.size.height

                ZStack(alignment: .leading) {
                    // Static zone graphics — does NOT depend on indicatorRelay
                    let dynamicPerfectHalf = max(0.01, min(perfectHalf, perfectHalf * CGFloat(perfectZoneScale)))
                    TapBarZonesView(
                        theme: theme,
                        hideZones: hideZones,
                        strictPerfectOnly: strictPerfectOnly,
                        perfectHalf: dynamicPerfectHalf,
                        greatHalf: greatHalf,
                        goodHalf: goodHalf,
                        barWidth: w,
                        barHeight: h
                    )

                    // Moving indicator — reads position from relay (60fps updates)
                    Capsule()
                        .fill(Color.white)
                        .frame(width: 20, height: 48)
                        .shadow(color: Color.white.opacity(0.9), radius: 6)
                        .shadow(color: theme.glowColor.opacity(0.7), radius: 14)
                        .shadow(color: theme.glowColor.opacity(0.3), radius: 24)
                        .drawingGroup()  // rasterize shadows — GPU compositing instead of per-frame calculation
                        .offset(x: w * indicatorRelay.position - 10)
                }
                .clipShape(RoundedRectangle(cornerRadius: 18))
            }
            .frame(height: 56)

            // Zone labels — symmetrical, color-coded (hidden in invisible zone mode)
            HStack(spacing: 0) {
                zoneLabel("MISS", color: Color(red: 0.92, green: 0.27, blue: 0.27).opacity(0.5))
                zoneLabel(strictPerfectOnly ? "MISS" : "GOOD", color: strictPerfectOnly ? Color(red: 0.92, green: 0.27, blue: 0.27).opacity(0.45) : Color(red: 0.98, green: 0.73, blue: 0.26).opacity(0.7))
                zoneLabel(strictPerfectOnly ? "MISS" : "GREAT", color: strictPerfectOnly ? Color(red: 0.92, green: 0.27, blue: 0.27).opacity(0.45) : Color(red: 0.29, green: 0.86, blue: 0.50).opacity(0.8))
                zoneLabel("PERFECT", color: theme.targetColor)
                    .fontWeight(.bold)
                zoneLabel(strictPerfectOnly ? "MISS" : "GREAT", color: strictPerfectOnly ? Color(red: 0.92, green: 0.27, blue: 0.27).opacity(0.45) : Color(red: 0.29, green: 0.86, blue: 0.50).opacity(0.8))
                zoneLabel(strictPerfectOnly ? "MISS" : "GOOD", color: strictPerfectOnly ? Color(red: 0.92, green: 0.27, blue: 0.27).opacity(0.45) : Color(red: 0.98, green: 0.73, blue: 0.26).opacity(0.7))
                zoneLabel("MISS", color: Color(red: 0.92, green: 0.27, blue: 0.27).opacity(0.5))
            }
            .font(.system(size: 8, weight: .bold))
            .opacity(hideZones ? 0 : 1)
        }
    }

    private func zoneLabel(_ text: String, color: Color) -> some View {
        Text(text)
            .foregroundColor(color)
            .frame(maxWidth: .infinity)
    }
}

// MARK: - Static zone graphics (no dependency on IndicatorRelay — never re-renders at 60fps)
private struct TapBarZonesView: View {
    let theme: AppTheme
    let hideZones: Bool
    let strictPerfectOnly: Bool
    let perfectHalf: CGFloat
    let greatHalf: CGFloat
    let goodHalf: CGFloat
    let barWidth: CGFloat
    let barHeight: CGFloat

    var body: some View {
        ZStack(alignment: .leading) {
            // Base — dark miss zone
            RoundedRectangle(cornerRadius: 18)
                .fill(Color(red: 0.92, green: 0.15, blue: 0.15).opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )

            if !hideZones {
                // GOOD zone (center ±20%)
                if !strictPerfectOnly {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(red: 0.98, green: 0.73, blue: 0.26).opacity(0.12))
                        .frame(width: barWidth * goodHalf * 2)
                        .offset(x: barWidth * (0.5 - goodHalf))
                }

                // GREAT zone (center ±10%)
                if !strictPerfectOnly {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(red: 0.29, green: 0.86, blue: 0.50).opacity(0.18))
                        .frame(width: barWidth * greatHalf * 2)
                        .offset(x: barWidth * (0.5 - greatHalf))
                }

                // PERFECT zone (center ±4%) — brightest
                RoundedRectangle(cornerRadius: 4)
                    .fill(
                        LinearGradient(
                            colors: [theme.targetColor.opacity(0.35), theme.glowColor.opacity(0.35)],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                    .frame(width: barWidth * perfectHalf * 2)
                    .offset(x: barWidth * (0.5 - perfectHalf))

                // Zone edge lines for clarity
                if !strictPerfectOnly {
                    ForEach([-goodHalf, goodHalf, -greatHalf, greatHalf], id: \.self) { offset in
                        Rectangle()
                            .fill(Color.white.opacity(0.06))
                            .frame(width: 1, height: barHeight)
                            .offset(x: barWidth * (0.5 + offset))
                    }
                }

                // PERFECT zone edge lines (brighter)
                ForEach([-perfectHalf, perfectHalf], id: \.self) { offset in
                    Rectangle()
                        .fill(theme.targetColor.opacity(0.25))
                        .frame(width: 1, height: barHeight)
                        .offset(x: barWidth * (0.5 + offset))
                }
            }

            // Center target line (always visible — even in invisible zone)
            Rectangle()
                .fill(Color.white.opacity(hideZones ? 0.15 : 0.50))
                .frame(width: 2, height: barHeight)
                .offset(x: barWidth / 2 - 1)

            // Center diamond marker
            Rectangle()
                .fill(theme.targetColor.opacity(hideZones ? 0.2 : 0.7))
                .frame(width: 10, height: 10)
                .rotationEffect(.degrees(45))
                .offset(x: barWidth / 2 - 5, y: -barHeight / 2 + 2)
        }
    }
}

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        TapBarView(indicatorRelay: IndicatorRelay(), theme: .default, hideZones: false)
            .padding()
    }
}
