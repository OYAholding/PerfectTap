import SwiftUI

// MARK: - DuelLobbyView (ported from DuelLobby.jsx)
struct DuelLobbyView: View {
    @EnvironmentObject var router: AppRouter
    @State private var tab: Tab = .create
    @State private var joinCode = ""
    @State private var isLoading = false
    @State private var errorMsg: String? = nil
    @State private var createdCode: String? = nil
    @State private var duelId: String? = nil
    @State private var duel: Duel? = nil
    @State private var duelListener: Any? = nil

    private let profile = PlayerProfile.load() ?? PlayerProfile()

    enum Tab { case create, join }

    var body: some View {
        ZStack {
            Color(red: 0.039, green: 0.039, blue: 0.059).ignoresSafeArea()
            VStack(spacing: 0) {
                navBar(title: "DUEL LOBBY") { router.pop() }

                // Tabs
                HStack(spacing: 0) {
                    tabButton("CREATE", tab: .create)
                    tabButton("JOIN",   tab: .join)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)

                if tab == .create {
                    createTab
                } else {
                    joinTab
                }

                Spacer()
            }
        }
        .navigationBarHidden(true)
        .onDisappear {
            if let listener = duelListener {
                Backend.shared.removeDuelListener(listener)
            }
        }
    }

    // MARK: - Create tab
    private var createTab: some View {
        VStack(spacing: 20) {
            if let code = createdCode {
                VStack(spacing: 16) {
                    Text("Your duel code:")
                        .font(.system(size: 13)).foregroundColor(.white.opacity(0.5))

                    Text(code)
                        .font(.system(size: 48, weight: .black, design: .monospaced))
                        .tracking(8)
                        .foregroundStyle(LinearGradient(colors: [Color(red: 0.95, green: 0.24, blue: 0.37), Color(red: 0.98, green: 0.45, blue: 0.10)], startPoint: .leading, endPoint: .trailing))

                    Text("Share this code with your opponent")
                        .font(.system(size: 12)).foregroundColor(.white.opacity(0.4))

                    if let d = duel, d.status == .inProgress {
                        // Show opponent avatar + name
                        if let guestName = d.guestName {
                            let guestEmoji = ShopItem.avatars.first(where: { $0.id == (d.guestAvatar ?? "") })?.icon ?? "😊"
                            HStack(spacing: 8) {
                                Text(guestEmoji).font(.system(size: 28))
                                Text(guestName)
                                    .font(.system(size: 15, weight: .bold))
                                    .foregroundColor(.white)
                                Text("joined!")
                                    .font(.system(size: 13))
                                    .foregroundColor(.white.opacity(0.5))
                            }
                        }
                        Button {
                            // Save DuelContext so GameViewModel can submit score
                            DuelContext.save(duelId: d.id, role: .host, mode: d.mode)
                            router.push(.game(d.mode))
                        } label: {
                            Text("TAP TO PLAY →")
                                .font(.system(size: 14, weight: .black))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(LinearGradient(colors: [Color(red: 0.95, green: 0.24, blue: 0.37), Color(red: 0.98, green: 0.45, blue: 0.10)], startPoint: .leading, endPoint: .trailing))
                                .cornerRadius(14)
                        }
                    } else {
                        HStack(spacing: 8) {
                            ProgressView().tint(.white.opacity(0.5)).scaleEffect(0.8)
                            Text("Waiting for opponent…")
                                .font(.system(size: 13)).foregroundColor(.white.opacity(0.4))
                        }
                    }
                }
                .padding(.horizontal, 28)
            } else {
                Button {
                    Task { await createDuel() }
                } label: {
                    if isLoading {
                        ProgressView().tint(.white)
                            .frame(maxWidth: .infinity).padding(.vertical, 20)
                    } else {
                        Text("CREATE DUEL")
                            .font(.system(size: 18, weight: .black)).tracking(3)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity).padding(.vertical, 20)
                    }
                }
                .background(LinearGradient(colors: [Color(red: 0.95, green: 0.24, blue: 0.37), Color(red: 0.98, green: 0.45, blue: 0.10)], startPoint: .leading, endPoint: .trailing))
                .cornerRadius(16)
                .padding(.horizontal, 28)
            }

            if let err = errorMsg {
                Text(err).font(.system(size: 13)).foregroundColor(.red.opacity(0.8))
            }
        }
    }

    // MARK: - Join tab
    private var joinTab: some View {
        VStack(spacing: 16) {
            TextField("Enter 6-character code", text: $joinCode)
                .autocapitalization(.allCharacters)
                .autocorrectionDisabled()
                .multilineTextAlignment(.center)
                .font(.system(size: 28, weight: .black, design: .monospaced))
                .tracking(6)
                .foregroundColor(.white)
                .padding(20)
                .background(Color.white.opacity(0.06))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.12)))
                .cornerRadius(16)
                .onChange(of: joinCode) { newValue in joinCode = String(newValue.prefix(6)).uppercased() }

            Button {
                Task { await joinDuel() }
            } label: {
                if isLoading {
                    ProgressView().tint(.white).frame(maxWidth: .infinity).padding(.vertical, 20)
                } else {
                    Text("JOIN DUEL")
                        .font(.system(size: 18, weight: .black)).tracking(3)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity).padding(.vertical, 20)
                }
            }
            .background(LinearGradient(colors: [Color(red: 0.95, green: 0.24, blue: 0.37), Color(red: 0.98, green: 0.45, blue: 0.10)], startPoint: .leading, endPoint: .trailing))
            .cornerRadius(16)
            .disabled(joinCode.count < 6 || isLoading)
            .opacity(joinCode.count < 6 ? 0.5 : 1)

            if let err = errorMsg {
                Text(err).font(.system(size: 13)).foregroundColor(.red.opacity(0.8))
            }
        }
        .padding(.horizontal, 28)
    }

    private func tabButton(_ label: String, tab t: Tab) -> some View {
        Button { tab = t } label: {
            Text(label)
                .font(.system(size: 13, weight: .black)).tracking(2)
                .foregroundColor(tab == t ? .white : .white.opacity(0.4))
                .frame(maxWidth: .infinity).padding(.vertical, 12)
                .background(tab == t ? Color.white.opacity(0.10) : Color.clear)
                .cornerRadius(10)
        }
    }

    private func createDuel() async {
        isLoading = true; errorMsg = nil
        do {
            let result = try await Backend.shared.createDuel(hostName: profile.username, hostAvatar: profile.equippedAvatar)
            duelId = result.duelId
            createdCode = result.code
            // Start listening for opponent to join
            duelListener = Backend.shared.listenDuel(duelId: result.duelId) { d in
                duel = d
            }
        } catch { errorMsg = error.localizedDescription }
        isLoading = false
    }

    private func joinDuel() async {
        isLoading = true; errorMsg = nil
        do {
            let result = try await Backend.shared.joinDuel(code: joinCode, guestName: profile.username, guestAvatar: profile.equippedAvatar)
            // Save DuelContext for GameViewModel — lobby duels default to .duel mode
            DuelContext.save(duelId: result.duelId, role: .guest, mode: .duel)
            router.push(.game(.duel))
        } catch { errorMsg = "Duel not found. Check the code and try again." }
        isLoading = false
    }
}
