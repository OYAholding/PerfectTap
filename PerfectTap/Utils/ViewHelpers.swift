import SwiftUI

// MARK: - Shared nav bar used across all views
func navBar(title: String, onBack: @escaping () -> Void) -> some View {
    HStack {
        Button(action: onBack) {
            Image(systemName: "chevron.left")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.white.opacity(0.6))
                .padding(12)
                .background(Color.white.opacity(0.05))
                .clipShape(Circle())
        }
        Spacer()
        Text(title)
            .font(.system(size: 14, weight: .black))
            .tracking(4)
            .foregroundColor(.white)
        Spacer()
        Color.clear.frame(width: 44, height: 44)
    }
    .padding(.horizontal, 20)
    .padding(.vertical, 14)
}
