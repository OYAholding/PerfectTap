import SwiftUI

// MARK: - LinkAccountView (optional — link Firebase account for cloud sync)
// This is NOT shown on first launch. It's accessible from Settings for users
// who want to back up their progress to the cloud.
struct LinkAccountView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @Environment(\.dismiss) var dismiss

    @State private var email = ""
    @State private var password = ""
    @State private var isSignUp = true
    @State private var isLoading = false
    @State private var successMessage: String? = nil

    var body: some View {
        ZStack {
            Color(red: 0.039, green: 0.039, blue: 0.059).ignoresSafeArea()

            VStack(spacing: 0) {
                // Header
                HStack {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.white.opacity(0.5))
                            .frame(width: 40, height: 40)
                    }
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)

                Spacer()

                VStack(spacing: 32) {
                    // Icon + title
                    VStack(spacing: 12) {
                        Image(systemName: "icloud.and.arrow.up")
                            .font(.system(size: 48))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [Color(red: 0.59, green: 0.28, blue: 0.98), Color(red: 0.22, green: 0.82, blue: 0.98)],
                                    startPoint: .topLeading, endPoint: .bottomTrailing
                                )
                            )

                        Text("CLOUD BACKUP")
                            .font(.system(size: 24, weight: .black))
                            .tracking(3)
                            .foregroundColor(.white)

                        Text("Link an account to back up your progress.\nThis is optional — your data is saved locally.")
                            .font(.system(size: 13))
                            .multilineTextAlignment(.center)
                            .foregroundColor(.white.opacity(0.45))
                    }

                    if let success = successMessage {
                        // Success state — auto-dismiss after 1.5s
                        VStack(spacing: 12) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 40))
                                .foregroundColor(Color(red: 0.22, green: 0.82, blue: 0.49))
                            Text(success)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(Color(red: 0.22, green: 0.82, blue: 0.49))
                        }
                        .transition(.opacity.combined(with: .scale(scale: 0.8)))
                        .onAppear {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                dismiss()
                            }
                        }
                    } else {
                        // Mode selector tabs
                        HStack(spacing: 0) {
                            modeTab(title: "CREATE ACCOUNT", active: isSignUp) {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    isSignUp = true
                                    authVM.errorMessage = nil
                                }
                            }
                            modeTab(title: "SIGN IN", active: !isSignUp) {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    isSignUp = false
                                    authVM.errorMessage = nil
                                }
                            }
                        }
                        .background(Color.white.opacity(0.04))
                        .cornerRadius(12)

                        // Form
                        VStack(spacing: 14) {
                            formField(placeholder: "Email", text: $email, isSecure: false, keyboard: .emailAddress)
                            formField(placeholder: "Password (min 6 characters)", text: $password, isSecure: true, keyboard: .default)

                            if let err = authVM.errorMessage {
                                Text(err)
                                    .font(.system(size: 13))
                                    .foregroundColor(.red.opacity(0.8))
                                    .multilineTextAlignment(.center)
                                    .transition(.opacity)
                            }

                            Button {
                                isLoading = true
                                authVM.errorMessage = nil
                                Task {
                                    if isSignUp {
                                        await authVM.linkAccount(email: email, password: password)
                                    } else {
                                        await authVM.signInAndLink(email: email, password: password)
                                    }
                                    isLoading = false
                                    if authVM.errorMessage == nil {
                                        withAnimation(.spring(response: 0.4)) {
                                            successMessage = isSignUp
                                                ? "Account created & linked!"
                                                : "Signed in & synced!"
                                        }
                                    }
                                }
                            } label: {
                                if isLoading {
                                    ProgressView().tint(.white)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 18)
                                } else {
                                    Text(isSignUp ? "CREATE & LINK" : "SIGN IN & LINK")
                                        .font(.system(size: 16, weight: .black))
                                        .tracking(2)
                                        .foregroundColor(.white)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 18)
                                }
                            }
                            .background(
                                LinearGradient(
                                    colors: isSignUp
                                        ? [Color(red: 0.47, green: 0.18, blue: 0.85), Color(red: 0.18, green: 0.55, blue: 0.96)]
                                        : [Color(red: 0.18, green: 0.55, blue: 0.96), Color(red: 0.22, green: 0.82, blue: 0.49)],
                                    startPoint: .leading, endPoint: .trailing
                                )
                            )
                            .cornerRadius(16)
                            .disabled(isLoading || email.isEmpty || password.count < 6)
                            .opacity((email.isEmpty || password.count < 6) ? 0.5 : 1)
                        }

                        // Subtitle hint
                        Text(isSignUp
                            ? "Creates a new account and backs up your progress."
                            : "Signs in to an existing account and syncs your data.")
                            .font(.system(size: 12))
                            .foregroundColor(.white.opacity(0.3))
                            .multilineTextAlignment(.center)
                            .padding(.top, 4)
                    }
                }
                .padding(.horizontal, 28)

                Spacer()
            }
        }
    }

    // MARK: - Mode Tab
    private func modeTab(title: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .bold))
                .tracking(1)
                .foregroundColor(active ? .white : .white.opacity(0.35))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(active ? Color.white.opacity(0.10) : Color.clear)
                .cornerRadius(12)
        }
    }

    // MARK: - Form Field
    private func formField(placeholder: String, text: Binding<String>, isSecure: Bool, keyboard: UIKeyboardType) -> some View {
        Group {
            if isSecure {
                SecureField(placeholder, text: text)
            } else {
                TextField(placeholder, text: text)
                    .keyboardType(keyboard)
                    .autocapitalization(.none)
                    .autocorrectionDisabled()
            }
        }
        .padding(16)
        .background(Color.white.opacity(0.06))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.10)))
        .cornerRadius(14)
        .foregroundColor(.white)
        .font(.system(size: 15))
    }
}

// MARK: - Keep LoginView as alias for backward compatibility
// (Any remaining references will compile)
typealias LoginView = LinkAccountView
