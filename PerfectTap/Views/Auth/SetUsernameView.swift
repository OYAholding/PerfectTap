import SwiftUI

// MARK: - SetUsernameView (shown once on first launch — permanent username)
struct SetUsernameView: View {
    @EnvironmentObject var authVM: AuthViewModel

    @State private var username = ""
    @State private var isLoading = false

    private var isValid: Bool {
        let trimmed = username.trimmingCharacters(in: .whitespaces)
        return trimmed.count >= 2 && trimmed.count <= 20 &&
               trimmed.range(of: "^[a-zA-Z0-9_]+$", options: .regularExpression) != nil
    }

    var body: some View {
        ZStack {
            Color(red: 0.039, green: 0.039, blue: 0.059).ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                VStack(spacing: 32) {
                    // Logo
                    VStack(spacing: 16) {
                        Image("Logo")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 80, height: 80)
                            .clipShape(RoundedRectangle(cornerRadius: 20))
                            .shadow(color: Color(red: 0.59, green: 0.28, blue: 0.98).opacity(0.3), radius: 20)

                        Text("PERFECTTAP")
                            .font(.system(size: 28, weight: .black))
                            .tracking(4)
                            .foregroundColor(.white)
                    }

                    // Title
                    VStack(spacing: 8) {
                        Text("Choose Your Name")
                            .font(.system(size: 22, weight: .black))
                            .foregroundColor(.white)
                        Text("This will be your permanent player name.\nChoose wisely — it can't be changed later!")
                            .font(.system(size: 13))
                            .multilineTextAlignment(.center)
                            .foregroundColor(.white.opacity(0.45))
                    }

                    // Input
                    VStack(spacing: 8) {
                        TextField("Username (2–20 chars, a-z 0-9 _)", text: $username)
                            .autocapitalization(.none)
                            .autocorrectionDisabled()
                            .padding(16)
                            .background(Color.white.opacity(0.06))
                            .overlay(RoundedRectangle(cornerRadius: 14).stroke(
                                isValid ? Color(red: 0.59, green: 0.28, blue: 0.98).opacity(0.5) : Color.white.opacity(0.10)
                            ))
                            .cornerRadius(14)
                            .foregroundColor(.white)
                            .font(.system(size: 17))

                        if let err = authVM.errorMessage {
                            Text(err)
                                .font(.system(size: 12))
                                .foregroundColor(.red.opacity(0.8))
                                .multilineTextAlignment(.center)
                        }

                        if isValid {
                            Text("✓ Looks good!")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(Color(red: 0.22, green: 0.82, blue: 0.49).opacity(0.7))
                        }
                    }

                    Button {
                        guard isValid else { return }
                        isLoading = true
                        Task {
                            await authVM.setUsername(username.trimmingCharacters(in: .whitespaces))
                            isLoading = false
                        }
                    } label: {
                        if isLoading {
                            ProgressView().tint(.white).frame(maxWidth: .infinity).padding(.vertical, 18)
                        } else {
                            Text("LET'S GO!")
                                .font(.system(size: 18, weight: .black))
                                .tracking(3)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 18)
                        }
                    }
                    .background(
                        LinearGradient(
                            colors: [Color(red: 0.47, green: 0.18, blue: 0.85), Color(red: 0.18, green: 0.55, blue: 0.96)],
                            startPoint: .leading, endPoint: .trailing
                        )
                    )
                    .cornerRadius(16)
                    .disabled(!isValid || isLoading)
                    .opacity(isValid ? 1 : 0.5)
                }
                .padding(.horizontal, 28)

                Spacer()
            }
        }
    }
}
