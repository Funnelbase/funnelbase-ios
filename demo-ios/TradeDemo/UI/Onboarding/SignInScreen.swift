import SwiftUI

/// Sign-in. Any username and any password are accepted — there is no auth backend, by design.
///
/// The username is not decoration: it is hashed into the `user_id` every event afterwards
/// carries (see `UserId`), so signing in as the same name twice produces the same person. The
/// "Pro plan" switch stands in for billing: a pro account's `$identify` carries the day its plan
/// renews (`AppState.signIn`).
struct SignInScreen: View {

    let onSignedIn: (_ username: String, _ pro: Bool) -> Void

    @State private var username = ""
    @State private var password = ""
    @State private var pro = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Welcome back. Any credentials work — this demo has no authentication server.")
                .font(.subheadline)
                .foregroundStyle(TradeDemoColors.textSecondary)
                .padding(.bottom, 24)

            LabelledField(label: "Username", text: $username)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(.bottom, 12)

            LabelledField(label: "Password", text: $password, isSecure: true)
                .padding(.bottom, 16)

            Toggle("Pro plan", isOn: $pro)
                .foregroundStyle(TradeDemoColors.textPrimary)
                .tint(TradeDemoColors.accent)

            Button("Sign in") { onSignedIn(username, pro) }
                .buttonStyle(AccentButtonStyle())
                // The password is genuinely unchecked, but an empty username would hash to a
                // shared id for everyone who left the field blank.
                .disabled(username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .opacity(username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.5 : 1)
                .padding(.top, 20)

            Spacer()
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .tradeDemoScreenBackground()
        .navigationTitle("Sign in")
        .navigationBarTitleDisplayMode(.inline)
        .tradeDemoNavigationBar()
        .trackScreenView(Screens.signIn)
    }
}

/// A bordered text field with its label above it, which is the shape Material's
/// `OutlinedTextField` has and SwiftUI's plain `TextField` does not.
struct LabelledField: View {

    let label: String
    @Binding var text: String
    var isSecure: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.caption)
                .foregroundStyle(TradeDemoColors.textSecondary)
            Group {
                if isSecure {
                    SecureField("", text: $text)
                } else {
                    TextField("", text: $text)
                }
            }
            .font(.body)
            .foregroundStyle(TradeDemoColors.textPrimary)
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: 12).fill(TradeDemoColors.surface))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(TradeDemoColors.outline, lineWidth: 1))
        }
    }
}
