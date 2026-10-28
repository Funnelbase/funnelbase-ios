import Funnelbase
import SwiftUI
import UIKit

/// Push, from the device's side: whether notifications are allowed, which token this install
/// registered, and a way to see a campaign without waiting for one.
///
/// It is a demo screen, so it shows the machinery rather than hiding it. The simulate buttons are
/// the part worth having: they post the same `data` map the backend sends, so the text, the
/// buttons, the tap and the routing can all be seen on a simulator with no APNs certificate at
/// all (docs/push.md, "Trying push without a provider").
struct PushScreen: View {

    @State private var allowed = false
    @State private var token: String?
    @State private var manualToken = ""
    @State private var simulated = 0
    @EnvironmentObject private var navigator: Navigator

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                permissionCard
                topicsCard
                tokenCard
                campaignCard
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .tradeDemoScreenBackground()
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.inline)
        .tradeDemoNavigationBar()
        .trackScreenView(Screens.push)
        .onAppear(perform: refresh)
    }

    private var permissionCard: some View {
        SectionCard {
            SectionHeader("Permission") {
                Pill(allowed ? "Allowed" : "Blocked", color: allowed ? TradeDemoColors.up : TradeDemoColors.down)
            }
            Text("A push needs the person's permission. The SDK never asks on its own — it has no "
                + "screen to ask from — so the app asks and the SDK reads the answer into the "
                + "token's status.")
                .font(.caption)
                .foregroundStyle(TradeDemoColors.textSecondary)
                .padding(.top, 4)

            if !allowed {
                Button("Allow notifications") {
                    // Whatever the person chooses, the registry needs to hear it: the token's
                    // status *is* the permission, so the SDK re-registers rather than assuming.
                    Analytics.push.requestAuthorization { granted in
                        DispatchQueue.main.async {
                            refresh()
                            if !granted { openSystemSettings() }
                        }
                    }
                }
                .buttonStyle(AccentButtonStyle())
                .padding(.top, 12)
            }
        }
    }

    private var topicsCard: some View {
        SectionCard {
            SectionHeader("What you get")
            Text("Choose which kinds of message this app may send you. The list is the app's own, "
                + "set in the dashboard, and a campaign under a topic you switched off skips you.")
                .font(.caption)
                .foregroundStyle(TradeDemoColors.textSecondary)
                .padding(.top, 4)

            Button("Notification topics") {
                navigator.push(.notificationSettings)
            }
            .buttonStyle(OutlineButtonStyle())
            .padding(.top, 12)
        }
    }

    private var tokenCard: some View {
        SectionCard {
            SectionHeader("This install's token")
            Text(token ?? "None registered yet. With push allowed, APNs issues one and the SDK "
                + "registers it at launch; without it, paste any string below and the dashboard "
                + "can target this install through a custom gateway.")
                .font(token == nil ? .caption : .numeric)
                .foregroundStyle(token == nil ? TradeDemoColors.textSecondary : TradeDemoColors.textPrimary)
                .lineLimit(3)
                .truncationMode(.middle)
                .padding(.top, 4)

            LabelledField(label: "A token of your own", text: $manualToken)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(.top, 12)

            Button("Register it") {
                let trimmed = manualToken.trimmingCharacters(in: .whitespacesAndNewlines)
                let value = trimmed.isEmpty ? "opaque-\(UUID().uuidString)" : trimmed
                Analytics.push.setToken(value, kind: TokenKinds.opaque)
                manualToken = ""
                // The SDK writes the registration asynchronously, once it has asked the system
                // for the permission the status describes, so the read has to come after.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { refresh() }
            }
            .buttonStyle(OutlineButtonStyle())
            .padding(.top, 8)
        }
    }

    private var campaignCard: some View {
        SectionCard {
            SectionHeader("See a campaign") {
                if simulated > 0 {
                    Pill("\(simulated) sent", color: TradeDemoColors.accent)
                }
            }
            Text("The same payload the platform sends, posted as a local notification here — "
                + "nothing local can make Apple run the service extension, so the text, the "
                + "buttons and the tap are real while the image and the receipt are not.")
                .font(.caption)
                .foregroundStyle(TradeDemoColors.textSecondary)
                .padding(.top, 4)
                .padding(.bottom, 12)

            SimulateButton(label: "Basic notification") {
                PushSimulation.basic(deliveryId: PushSimulation.deliveryId())
            } onSent: {
                simulated += 1
            }
            SimulateButton(label: "With an image and two buttons") {
                PushSimulation.rich(deliveryId: PushSimulation.deliveryId())
            } onSent: {
                simulated += 1
            }
            SimulateButton(label: "Collapsing: replaces the last one") {
                PushSimulation.collapsing(deliveryId: PushSimulation.deliveryId())
            } onSent: {
                simulated += 1
            }

            StatRow("Posted after", "3s")
            Text("Background the app to see the banner. A real campaign's image is fetched by "
                + "the notification service extension; this demo's sample image is served by a "
                + "local provider on localhost:9099.")
                .font(.caption)
                .foregroundStyle(TradeDemoColors.textSecondary)
                .padding(.top, 8)
        }
    }

    private func refresh() {
        token = Analytics.push.registeredToken()
        Analytics.push.notificationsEnabled { enabled in
            DispatchQueue.main.async { allowed = enabled }
        }
    }

    /// Once the prompt has been answered, only Settings can change the answer.
    private func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}

/// A simulate button, so the three read the same.
private struct SimulateButton: View {
    let label: String
    let payload: () -> [String: String]
    let onSent: () -> Void

    var body: some View {
        Button(label) {
            PushSimulation.post(payload())
            onSent()
        }
        .buttonStyle(OutlineButtonStyle())
        .padding(.bottom, 8)
    }
}
