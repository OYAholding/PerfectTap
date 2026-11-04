import SwiftUI

// MARK: - Particle model
private struct Particle: Identifiable {
    let id = UUID()
    var x: Double
    var y: Double
    var vx: Double
    var vy: Double
    var opacity: Double = 1.0
    var size: Double
    var color: Color
}

// MARK: - Tap FX color palettes (keyed by ShopItem id)
// Each equipped Tap FX changes the particle colors for PERFECT and GREAT hits.
private enum TapFXPalette {
    static func colors(for fxId: String, accuracy: TapAccuracy) -> [Color] {
        switch fxId {
        case "fx_ripple":
            return accuracy == .perfect
                ? [Color(red: 0.10, green: 0.60, blue: 0.98), Color(red: 0.20, green: 0.80, blue: 0.98), Color(red: 0.05, green: 0.50, blue: 0.90)]
                : [Color(red: 0.15, green: 0.70, blue: 0.95), Color(red: 0.25, green: 0.85, blue: 0.98)]
        case "fx_spark":
            return accuracy == .perfect
                ? [Color(red: 0.98, green: 0.90, blue: 0.20), Color(red: 0.98, green: 0.70, blue: 0.10), Color(red: 1.0, green: 1.0, blue: 0.60)]
                : [Color(red: 0.98, green: 0.85, blue: 0.30), Color(red: 0.98, green: 0.75, blue: 0.15)]
        case "fx_hearts":
            return accuracy == .perfect
                ? [Color(red: 0.98, green: 0.30, blue: 0.50), Color(red: 0.95, green: 0.45, blue: 0.65), Color(red: 0.98, green: 0.20, blue: 0.40)]
                : [Color(red: 0.95, green: 0.50, blue: 0.65), Color(red: 0.90, green: 0.40, blue: 0.55)]
        case "fx_stars":
            return accuracy == .perfect
                ? [Color(red: 0.98, green: 0.85, blue: 0.10), Color(red: 1.0, green: 0.95, blue: 0.50), Color(red: 0.98, green: 0.75, blue: 0.05)]
                : [Color(red: 0.98, green: 0.90, blue: 0.40), Color(red: 1.0, green: 0.95, blue: 0.60)]
        case "fx_confetti":
            return accuracy == .perfect
                ? [Color.red, Color.green, Color.blue, Color.yellow, Color.orange, Color.purple]
                : [Color.cyan, Color.green, Color.yellow, Color.orange]
        case "fx_shatter":
            return accuracy == .perfect
                ? [Color(red: 0.90, green: 0.10, blue: 0.10), Color(red: 0.98, green: 0.40, blue: 0.10), Color(red: 0.98, green: 0.20, blue: 0.05)]
                : [Color(red: 0.95, green: 0.30, blue: 0.10), Color(red: 0.98, green: 0.50, blue: 0.15)]
        default: // fx_default or unknown
            return accuracy == .perfect ? ParticleEffectView.defaultPerfectColors : ParticleEffectView.defaultGreatColors
        }
    }
}

// MARK: - ParticleEffectView (triggered by accuracy)
// Only runs the TimelineView animation while particles are active,
// preventing continuous GPU work when nothing is on screen.
// Reads equipped Tap FX from PlayerProfile to customize particle colors.
struct ParticleEffectView: View {
    let accuracy: TapAccuracy?
    let trigger: UUID   // changes when a new hit occurs
    let equippedFX: String

    @State private var particles: [Particle] = []
    @State private var startTime: Date = .now
    @State private var isAnimating: Bool = false

    fileprivate static let defaultPerfectColors: [Color] = [
        Color(red: 0.76, green: 0.55, blue: 0.99),
        Color(red: 0.22, green: 0.87, blue: 0.98),
        Color(red: 0.59, green: 0.28, blue: 0.98)
    ]
    fileprivate static let defaultGreatColors: [Color] = [
        Color(red: 0.22, green: 0.87, blue: 0.98),
        Color(red: 0.36, green: 0.87, blue: 0.98)
    ]

    private var shouldAnimate: Bool {
        accuracy == .perfect || accuracy == .great
    }

    var body: some View {
        Group {
            if isAnimating {
                TimelineView(.animation) { timeline in
                    let elapsed = timeline.date.timeIntervalSince(startTime)
                    Canvas { context, size in
                        if elapsed > 1.2 { return }

                        for p in particles {
                            let t = elapsed
                            let x = p.x + p.vx * t
                            let y = p.y + p.vy * t + 150 * t * t  // gravity
                            let alpha = max(0, p.opacity - t * 1.2)
                            guard alpha > 0 else { continue }

                            let rect = CGRect(
                                x: size.width * x - p.size / 2,
                                y: size.height * y - p.size / 2,
                                width: p.size,
                                height: p.size
                            )
                            context.opacity = alpha
                            context.fill(Path(ellipseIn: rect), with: .color(p.color))
                        }
                    }
                    .allowsHitTesting(false)
                    .onChange(of: elapsed > 1.2) { done in
                        if done {
                            isAnimating = false
                            particles = []
                        }
                    }
                }
            }
        }
        .onChange(of: trigger) { _ in
            spawnParticles()
        }
    }

    private func spawnParticles() {
        guard shouldAnimate, let acc = accuracy else {
            particles = []
            isAnimating = false
            return
        }

        let count = acc == .perfect ? 20 : 10
        let colors = TapFXPalette.colors(for: equippedFX, accuracy: acc)

        startTime = .now
        particles = (0..<count).map { _ in
            let angle = Double.random(in: 0...(2 * .pi))
            let speed = Double.random(in: 0.15...0.45)
            return Particle(
                x: 0.5,
                y: 0.45,
                vx: cos(angle) * speed,
                vy: sin(angle) * speed - 0.3,
                size: Double.random(in: 4...8),
                color: colors.randomElement() ?? .white
            )
        }
        isAnimating = true
    }
}
