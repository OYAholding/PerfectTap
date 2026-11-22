import SwiftUI
import GoogleMobileAds
import FirebaseCore

// MARK: - AppDelegate (Firebase + AdMob initialization)
// Firebase recommends configuring in UIApplicationDelegate.didFinishLaunchingWithOptions
// to ensure all system services are ready before Firebase starts.
class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        FirebaseApp.configure()
        FirebaseService.connectToLocalEmulatorsIfRequested()
        // Ads are NOT started here: ConsentManager (Google UMP + Apple ATT) starts them
        // once the app is active and consent has been handled. See ConsentManager.swift.
        return true
    }
}

// MARK: - App Entry Point
@main
struct PerfectTapApp: App {

    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate

    @StateObject private var router = AppRouter()
    @StateObject private var themeManager = ThemeManager()
    @StateObject private var authVM = AuthViewModel.shared
    @StateObject private var duelAutoLaunchCoordinator = DuelAutoLaunchCoordinator()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(router)
                .environmentObject(themeManager)
                .environmentObject(authVM)
                .environmentObject(duelAutoLaunchCoordinator)
                .providesEffectsLevel()
                .preferredColorScheme(.dark)
                .task {
                    FrameMonitor.shared.startIfEnabled()
                    // Load saved timing statistics off the main thread so the
                    // first round end does not read the file.
                    Task.detached(priority: .utility) { _ = SessionMetricsStore.shared.all() }
                    // Warm audio + haptics at launch (audio graph setup now runs
                    // off the main thread) instead of inside the first game's
                    // onAppear, where it cost ~330 ms of main-thread time.
                    SoundEngine.shared.warmUp()
                    HapticsEngine.shared.warmUp()
                }
                .task {
                    // First launch: scenePhase may already be .active, so onChange won't fire.
                    ConsentManager.shared.isPresentationBlocked = { [weak router] in
                        router?.isGameOnStack ?? false
                    }
                    try? await Task.sleep(nanoseconds: 800_000_000)
                    await ConsentManager.shared.gatherConsentIfNeeded()
                }
                .task {
                    // Load IAP products from App Store Connect on launch.
                    // Without this, coinProducts and specialProducts are empty
                    // and no IAP purchases can be made.
                    await PurchaseManager.shared.start()
                }
                .onChange(of: router.isGameOnStack) { gameOnStack in
                    guard !gameOnStack, scenePhase == .active else { return }
                    Task {
                        await ConsentManager.shared.gatherConsentIfNeeded()
                        ConsentManager.shared.refreshTrackingStatus()
                    }
                }
                .onChange(of: scenePhase) { phase in
                    FrameMonitor.shared.setPaused(phase != .active)
                    guard phase == .active else { return }
                    // Never put the consent form / ATT prompt over a running
                    // round: a full-screen cover stopped the game clock (freeze)
                    // and an alert pauses play. Retried when the round is gone.
                    guard !router.isGameOnStack else { return }
                    Task {
                        // ATT can only be shown while active; iPadOS may report "active"
                        // slightly before the window can present, so give it a moment.
                        try? await Task.sleep(nanoseconds: 600_000_000)
                        await ConsentManager.shared.gatherConsentIfNeeded()
                        ConsentManager.shared.refreshTrackingStatus()
                    }
                }
        }
    }
}

// MARK: - Root: handles auth state routing
// No login wall — device-based identity created automatically.
// Player goes straight to username selection on first launch,
// then directly to home on subsequent launches.
struct RootView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @EnvironmentObject var router: AppRouter
    @EnvironmentObject var duelAutoLaunchCoordinator: DuelAutoLaunchCoordinator

    var body: some View {
        switch authVM.authState {
        case .loading:
            splashView

        case .needsUsername:
            SetUsernameView()

        case .authenticated:
            NavigationStack(path: $router.path) {
                HomeView()
                    .navigationDestination(for: AppRoute.self) { route in
                        route.destinationView()
                    }
            }
            .background(DuelAutoLaunchBootstrapView())
            .background(GameRenderWarmupView())
        }
    }

    private var splashView: some View {
        ZStack {
            Color(red: 0.039, green: 0.039, blue: 0.059).ignoresSafeArea()
            VStack(spacing: 12) {
                Image("Logo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 80, height: 80)
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                Text("PERFECTTAP")
                    .font(.system(size: 24, weight: .black)).tracking(6)
                    .foregroundColor(.white)
                ProgressView().tint(.white.opacity(0.5))
            }
        }
    }
}

/// Renders one invisible tap bar shortly after Home appears, once per launch.
/// The first tap bar render (rasterised glow via drawingGroup + zone graphics)
/// measured ~600–700 ms of main-thread time in the simulator; without this it
/// landed on the first opening of a game screen. Removed after it has drawn.
private struct GameRenderWarmupView: View {
    @EnvironmentObject var themeManager: ThemeManager
    @State private var done = GameRenderWarmupView.hasWarmed
    private static var hasWarmed = false

    var body: some View {
        if !done {
            // The equipped theme: premium skins draw a gradient indicator and a
            // track tint, whose first render otherwise landed in the first
            // countdown (measured 519 ms with Glitch Mode, docs/perf).
            TapBarView(indicatorRelay: IndicatorRelay(), theme: themeManager.current)
                .frame(width: 300)
                .opacity(0.01)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
                .onAppear {
                    GameRenderWarmupView.hasWarmed = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { done = true }
                }
        }
    }
}

private struct DuelAutoLaunchBootstrapView: View {
    @EnvironmentObject var router: AppRouter
    @EnvironmentObject var duelAutoLaunchCoordinator: DuelAutoLaunchCoordinator

    var body: some View {
        Color.clear
            .onAppear {
                duelAutoLaunchCoordinator.start(router: router)
            }
            // Signed in later (e.g. launched offline): start listening then.
            .onReceive(AuthViewModel.shared.$currentUID) { uid in
                if uid != nil { duelAutoLaunchCoordinator.start(router: router) }
            }
            .onDisappear {
                duelAutoLaunchCoordinator.stop()
            }
    }
}

@MainActor
final class DuelAutoLaunchCoordinator: ObservableObject {
    private weak var router: AppRouter?
    private var outgoingInviteListener: Any? = nil
    private var isListening = false

    func start(router: AppRouter) {
        self.router = router
        guard !isListening else { return }
        outgoingInviteListener = Backend.shared.listenOutgoingDuelInvitations { [weak self] invites in
            Task { @MainActor in
                self?.handleOutgoingInvites(invites)
            }
        }
        // nil = no signed-in user yet (e.g. launched offline): stay retryable.
        isListening = outgoingInviteListener != nil
    }

    func stop() {
        Backend.shared.removeListener(outgoingInviteListener)
        outgoingInviteListener = nil
        router = nil
        isListening = false
    }

    private func isAutoLaunchEligibleRoute(_ route: AppRoute?) -> Bool {
        switch route {
        case nil:
            return true  // Home/root
        case .friends, .friendDetail(_), .duelLobby:
            return true  // Duel-intent surfaces
        default:
            return false
        }
    }

    private func handleOutgoingInvites(_ invites: [DuelInvitation]) {
        guard let router else { return }
        guard isAutoLaunchEligibleRoute(router.path.last) else { return }
        // If a duel context already exists, let that flow finish.
        guard DuelContext.load() == nil else { return }

        let candidates = invites.filter { invite in
            invite.status == .accepted
                && !invite.isExpired
                && !DuelInviteLaunchReceiptStore.isHandled(inviteId: invite.id, duelId: invite.duelId)
        }
        guard !candidates.isEmpty else { return }

        Task {
            for candidate in candidates {
                let duel = await Backend.shared.loadDuel(duelId: candidate.duelId)
                let state = candidate.presentationState(
                    currentUID: Backend.shared.currentUID,
                    duel: duel,
                    isHandled: DuelInviteLaunchReceiptStore.isHandled(inviteId: candidate.id, duelId: candidate.duelId)
                )
                guard state == .readyToPlay else { continue }
                guard self.isAutoLaunchEligibleRoute(router.path.last) else { return }
                guard DuelContext.load() == nil else { return }

                DuelInviteLaunchReceiptStore.markHandled(inviteId: candidate.id, duelId: candidate.duelId)
                DuelContext.save(duelId: candidate.duelId, role: .host, mode: candidate.mode)
                router.push(.game(candidate.mode))
                _ = await Backend.shared.markDuelInvitationInProgress(candidate.id)
                return
            }
        }
    }
}
