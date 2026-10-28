import SwiftUI

struct WelcomeScreen: View {

    let onSignUp: () -> Void
    let onSignIn: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 64, weight: .semibold))
                .foregroundStyle(TradeDemoColors.accent)
                .padding(.bottom, 24)

            Text("Trade Demo")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(TradeDemoColors.textPrimary)
                .padding(.bottom, 12)

            Text("Markets, portfolio and orders — a sample app instrumented with the in-house analytics SDK.")
                .font(.subheadline)
                .foregroundStyle(TradeDemoColors.textSecondary)
                .multilineTextAlignment(.center)

            Spacer()

            Button("Create account", action: onSignUp)
                .buttonStyle(AccentButtonStyle())
                .padding(.bottom, 12)

            Button("Sign in", action: onSignIn)
                .buttonStyle(OutlineButtonStyle())
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .tradeDemoScreenBackground()
        .toolbar(.hidden, for: .navigationBar)
        .trackScreenView(Screens.welcome)
    }
}
