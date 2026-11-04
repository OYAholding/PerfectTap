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
        AdManager.shared.initializeSDK()
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

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(router)
                .environmentObject(themeManager)
                .environmentObject(authVM)
                .environmentObject(duelAutoLaunchCoordinator)
                .preferredColorScheme(.dark)
                .task {
                    // Load IAP products from App Store Connect on launch.
                    // Without this, coinProducts and specialProducts are empty
                    // and no IAP purchases can be made.
                    await PurchaseManager.shared.loadProducts()
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

private struct DuelAutoLaunchBootstrapView: View {
    @EnvironmentObject var router: AppRouter
    @EnvironmentObject var duelAutoLaunchCoordinator: DuelAutoLaunchCoordinator

    var body: some View {
        Color.clear
            .onAppear {
                duelAutoLaunchCoordinator.start(router: router)
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
        isListening = true

        outgoingInviteListener = FirebaseService.shared.listenOutgoingDuelInvitations { [weak self] invites in
            Task { @MainActor in
                self?.handleOutgoingInvites(invites)
            }
        }
    }

    func stop() {
        FirebaseService.shared.removeListener(outgoingInviteListener)
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
                let duel = await FirebaseService.shared.loadDuel(duelId: candidate.duelId)
                let state = candidate.presentationState(
                    currentUID: FirebaseService.shared.currentUID,
                    duel: duel,
                    isHandled: DuelInviteLaunchReceiptStore.isHandled(inviteId: candidate.id, duelId: candidate.duelId)
                )
                guard state == .readyToPlay else { continue }
                guard self.isAutoLaunchEligibleRoute(router.path.last) else { return }
                guard DuelContext.load() == nil else { return }

                DuelInviteLaunchReceiptStore.markHandled(inviteId: candidate.id, duelId: candidate.duelId)
                DuelContext.save(duelId: candidate.duelId, role: .host, mode: candidate.mode)
                router.push(.game(candidate.mode))
                _ = await FirebaseService.shared.markDuelInvitationInProgress(candidate.id)
                return
            }
        }
    }
}
