import SwiftUI

// MARK: - GameSettingsView (ported from GameSettings.jsx)
struct GameSettingsView: View {
    @EnvironmentObject var router: AppRouter
    @EnvironmentObject var themeManager: ThemeManager
    @ObservedObject private var authVM = AuthViewModel.shared
    @Environment(\.openURL) private var openURL

    @State private var soundEnabled: Bool = UserDefaults.standard.object(forKey: "perfecttap_sound") as? Bool ?? true
    @State private var musicEnabled: Bool = UserDefaults.standard.object(forKey: "perfecttap_music") as? Bool ?? true
    @State private var hapticsEnabled: Bool = UserDefaults.standard.object(forKey: "perfecttap_haptics") as? Bool ?? true
    @State private var showLinkAccount = false
    @State private var showDeleteConfirm = false
    @State private var isDeleting = false
    @State private var reauthPassword = ""
    @State private var profile: PlayerProfile = PlayerProfile.load() ?? PlayerProfile()
    @State private var showPrivacyPolicy = false
    @State private var showTermsOfUse = false

    /// Real build version (was hard-coded "1.0.0" while the app ships 1.0.2).
    static var appVersion: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }

    var body: some View {
        ZStack {
            Color(red: 0.039, green: 0.039, blue: 0.059).ignoresSafeArea()
            VStack(spacing: 0) {
                navBar(title: "SETTINGS") { router.pop() }

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 20) {

                        // Player info
                        settingsSection("PLAYER") {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(profile.username)
                                        .font(.system(size: 16, weight: .bold))
                                        .foregroundColor(.white)
                                    Text("Level \(profile.level) • \(profile.friendCode)")
                                        .font(.system(size: 12))
                                        .foregroundColor(.white.opacity(0.4))
                                }
                                Spacer()
                                Image(systemName: "person.circle.fill")
                                    .font(.system(size: 28))
                                    .foregroundColor(Color(red: 0.59, green: 0.28, blue: 0.98))
                            }
                            .padding(14)
                        }

                        // Audio
                        settingsSection("AUDIO") {
                            settingToggle(label: "Sound Effects", icon: "speaker.wave.2.fill", isOn: $soundEnabled)
                                .onChange(of: soundEnabled) { newValue in
                                    UserDefaults.standard.set(newValue, forKey: "perfecttap_sound")
                                    SoundEngine.shared.refreshSettings()
                                }
                            Divider().background(Color.white.opacity(0.06))
                            settingToggle(label: "Music", icon: "music.note", isOn: $musicEnabled)
                                .onChange(of: musicEnabled) { newValue in
                                    UserDefaults.standard.set(newValue, forKey: "perfecttap_music")
                                    SoundEngine.shared.refreshSettings()
                                    if newValue { SoundEngine.shared.startBgMusic() } else { SoundEngine.shared.stopBgMusic() }
                                }
                            Divider().background(Color.white.opacity(0.06))
                            settingToggle(label: "Haptics", icon: "waveform.path", isOn: $hapticsEnabled)
                                .onChange(of: hapticsEnabled) { newValue in
                                    UserDefaults.standard.set(newValue, forKey: "perfecttap_haptics")
                                    HapticsEngine.shared.refreshSettings()
                                }
                        }

                        // Theme picker — only shows owned themes
                        settingsSection("THEME") {
                            let ownedThemes = AppTheme.all.filter { theme in
                                let themeID = "theme_\(theme.name)"
                                // "default" theme is always owned; check ownership for others
                                return theme.name == "default" || profile.ownedItems.contains(themeID)
                            }

                            if ownedThemes.isEmpty {
                                Text("No themes unlocked yet. Visit the Shop!")
                                    .font(.system(size: 13))
                                    .foregroundColor(.white.opacity(0.4))
                                    .padding(14)
                            } else {
                                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                                    ForEach(ownedThemes, id: \.name) { theme in
                                        themeButton(theme)
                                    }
                                }
                                .padding(10)
                            }

                            // Link to shop for more themes
                            Button {
                                router.push(.shop)
                            } label: {
                                HStack {
                                    Image(systemName: "bag.fill").font(.system(size: 12))
                                    Text("Get more themes in the Shop")
                                        .font(.system(size: 12, weight: .medium))
                                }
                                .foregroundColor(Color(red: 0.59, green: 0.28, blue: 0.98))
                                .padding(.horizontal, 14).padding(.vertical, 10)
                            }
                        }

                        // Account
                        settingsSection("ACCOUNT") {
                            // Cloud backup / account linking
                            Button {
                                showLinkAccount = true
                            } label: {
                                HStack {
                                    Image(systemName: "icloud.and.arrow.up").foregroundColor(Color(red: 0.22, green: 0.58, blue: 0.98))
                                    Text("Cloud Backup").font(.system(size: 14, weight: .semibold)).foregroundColor(.white.opacity(0.8))
                                    Spacer()
                                    Image(systemName: "chevron.right").font(.system(size: 12)).foregroundColor(.white.opacity(0.3))
                                }
                                .padding(14)
                            }

                            Divider().background(Color.white.opacity(0.06))

                            // Restore purchases
                            Button {
                                Task { await PurchaseManager.shared.restorePurchases() }
                            } label: {
                                HStack {
                                    Image(systemName: "arrow.clockwise").foregroundColor(Color(red: 0.59, green: 0.28, blue: 0.98))
                                    Text("Restore Purchases").font(.system(size: 14, weight: .semibold)).foregroundColor(.white.opacity(0.8))
                                    Spacer()
                                }
                                .padding(14)
                            }

                            Divider().background(Color.white.opacity(0.06))

                            // Delete account (Apple-compliant)
                            Button {
                                showDeleteConfirm = true
                            } label: {
                                HStack {
                                    Image(systemName: "person.crop.circle.badge.minus").foregroundColor(.red.opacity(0.8))
                                    Text("Delete Account").font(.system(size: 14, weight: .semibold)).foregroundColor(.red.opacity(0.8))
                                    Spacer()
                                    if isDeleting {
                                        ProgressView().tint(.red.opacity(0.6)).scaleEffect(0.8)
                                    }
                                }
                                .padding(14)
                            }
                            .disabled(isDeleting)
                        }
                        // Legal
                        settingsSection("LEGAL") {
                            Button {
                                openURL(LegalLinks.privacy) { opened in if !opened { showPrivacyPolicy = true } }
                            } label: {
                                HStack {
                                    Image(systemName: "hand.raised.fill").foregroundColor(.white.opacity(0.5))
                                    Text("Privacy Policy").font(.system(size: 14, weight: .semibold)).foregroundColor(.white.opacity(0.8))
                                    Spacer()
                                    Image(systemName: "chevron.right").font(.system(size: 11)).foregroundColor(.white.opacity(0.3))
                                }
                                .padding(14)
                            }

                            Divider().background(Color.white.opacity(0.06))

                            Button {
                                openURL(LegalLinks.terms) { opened in if !opened { showTermsOfUse = true } }
                            } label: {
                                HStack {
                                    Image(systemName: "doc.text.fill").foregroundColor(.white.opacity(0.5))
                                    Text("Terms of Use").font(.system(size: 14, weight: .semibold)).foregroundColor(.white.opacity(0.8))
                                    Spacer()
                                    Image(systemName: "chevron.right").font(.system(size: 11)).foregroundColor(.white.opacity(0.3))
                                }
                                .padding(14)
                            }

                            Divider().background(Color.white.opacity(0.06))

                            Button {
                                openURL(LegalLinks.support)
                            } label: {
                                HStack {
                                    Image(systemName: "questionmark.circle.fill").foregroundColor(.white.opacity(0.5))
                                    Text("Support").font(.system(size: 14, weight: .semibold)).foregroundColor(.white.opacity(0.8))
                                    Spacer()
                                    Image(systemName: "chevron.right").font(.system(size: 11)).foregroundColor(.white.opacity(0.3))
                                }
                                .padding(14)
                            }
                        }

                        // App version
                        Text("PerfectTap v\(Self.appVersion)")
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.2))
                            .padding(.top, 8)
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 40)
                }
            }
        }
        .onAppear {
            // Re-read: purchases/restores may have changed the profile meanwhile.
            profile = PlayerProfile.load() ?? profile
        }
        .navigationBarHidden(true)
        .sheet(isPresented: $showLinkAccount) {
            LinkAccountView()
        }
        .sheet(isPresented: $showPrivacyPolicy) {
            LegalTextView(title: "PRIVACY POLICY", content: LegalContent.privacyPolicy)
        }
        .sheet(isPresented: $showTermsOfUse) {
            LegalTextView(title: "TERMS OF USE", content: LegalContent.termsOfUse)
        }
        .alert("Delete Account?", isPresented: $showDeleteConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Delete My Account", role: .destructive) {
                isDeleting = true
                Task {
                    // Do NOT popToRoot here — this view must stay on screen
                    // so the re-auth password alert can show if needed.
                    // After deletion, authState changes to .loading which
                    // causes RootView to switch to splash → username screen.
                    await authVM.deleteAccount()
                }
            }
        } message: {
            Text("This will permanently delete your account, all progress, scores, coins, cosmetics, and your username. This cannot be undone.")
        }
        .alert("Enter Password to Delete", isPresented: $authVM.needsReauthForDelete) {
            SecureField("Password", text: $reauthPassword)
            Button("Cancel", role: .cancel) {
                reauthPassword = ""
                // User cancelled — cloud data already deleted, sign out and clean up
                authVM.needsReauthForDelete = false
                Task {
                    await Backend.shared.signOut()
                    authVM.finishDeleteCleanup()
                }
            }
            Button("Delete", role: .destructive) {
                let pw = reauthPassword
                reauthPassword = ""
                Task {
                    await authVM.deleteAccountAfterReauth(password: pw)
                }
            }
        } message: {
            Text("Enter your password to complete account deletion.")
        }
    }

    private func settingsSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.system(size: 10, weight: .black)).tracking(3)
                .foregroundColor(.white.opacity(0.4))
                .padding(.bottom, 8)
            VStack(spacing: 0) { content() }
                .background(RoundedRectangle(cornerRadius: 16).fill(Color.white.opacity(0.04)))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.08)))
        }
    }

    private func settingToggle(label: String, icon: String, isOn: Binding<Bool>) -> some View {
        HStack {
            Image(systemName: icon).font(.system(size: 16)).foregroundColor(Color(red: 0.59, green: 0.28, blue: 0.98)).frame(width: 28)
            Text(label).font(.system(size: 14, weight: .medium)).foregroundColor(.white)
            Spacer()
            Toggle("", isOn: isOn).labelsHidden().tint(Color(red: 0.59, green: 0.28, blue: 0.98))
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
    }

    private func themeButton(_ theme: AppTheme) -> some View {
        let isSelected = themeManager.current.name == theme.name
        return Button {
            themeManager.apply(theme)
            // Mutate the CURRENT stored profile: the @State copy may predate a
            // purchase or restore made while Settings was open (would revert it).
            profile = EconomyManager.shared.updateProfile { $0.equippedTheme = theme.name }
        } label: {
            VStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 10)
                    .fill(LinearGradient(colors: [theme.barGradient.0, theme.barGradient.1], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(height: 36)
                    .overlay(isSelected ? RoundedRectangle(cornerRadius: 10).stroke(Color.white, lineWidth: 2) : nil)
                Text(theme.name.capitalized)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(isSelected ? .white : .white.opacity(0.4))
            }
        }
    }
}
