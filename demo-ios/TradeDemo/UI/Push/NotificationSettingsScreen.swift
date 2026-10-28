import Funnelbase
import SwiftUI
import UIKit

/// Which kinds of message this person gets: the app's notification topics, each with a switch.
///
/// Nothing here is hard-coded. The list is whatever the dashboard offers for this app, read with
/// `Analytics.topics.fetch`, and a switch calls `Analytics.topics.set` — so a topic added in the
/// dashboard shows up on the next visit with no app release. The Android demo's screen of the same
/// name does the same, and reports the same `notification_settings` screen view.
///
/// A switch changes the moment it is flipped. The SDK queues the choice like any event and shows it
/// on the next fetch even before the server has it, so there is nothing to wait for or roll back.
struct NotificationSettingsScreen: View {

    private enum Load {
        case loading
        case loaded([TopicChoice])
        case failed(String)
    }

    @State private var load: Load = .loading
    @State private var allowed = true

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if !allowed { blockedCard }
                content
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .tradeDemoScreenBackground()
        .navigationTitle("Notification topics")
        .navigationBarTitleDisplayMode(.inline)
        .tradeDemoNavigationBar()
        .trackScreenView(Screens.notificationSettings)
        .onAppear {
            fetch()
            readPermission()
        }
        // Coming back from Settings is the moment the permission may have changed.
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            readPermission()
        }
    }

    @ViewBuilder
    private var content: some View {
        switch load {
        case .loading:
            SectionCard {
                HStack(spacing: 12) {
                    ProgressView()
                    Text("Loading topics…")
                        .font(.subheadline)
                        .foregroundStyle(TradeDemoColors.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 8)
            }
        case .failed(let message):
            SectionCard {
                SectionHeader("Couldn't load topics")
                Text(message)
                    .font(.caption)
                    .foregroundStyle(TradeDemoColors.textSecondary)
                    .padding(.top, 4)
                Button("Try again", action: fetch)
                    .buttonStyle(AccentButtonStyle())
                    .padding(.top, 12)
            }
        case .loaded(let topics) where topics.isEmpty:
            SectionCard {
                SectionHeader("No topics yet")
                Text("This app has no notification topics. Add one in the dashboard and it appears here.")
                    .font(.caption)
                    .foregroundStyle(TradeDemoColors.textSecondary)
                    .padding(.top, 4)
            }
        case .loaded(let topics):
            SectionCard {
                ForEach(Array(topics.enumerated()), id: \.element.key) { index, topic in
                    if index > 0 {
                        Divider().overlay(TradeDemoColors.outline).padding(.vertical, 12)
                    }
                    Toggle(isOn: binding(for: topic.key)) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(topic.name)
                                .font(.subheadline)
                                .foregroundStyle(TradeDemoColors.textPrimary)
                            if let description = topic.description, !description.isEmpty {
                                Text(description)
                                    .font(.caption)
                                    .foregroundStyle(TradeDemoColors.textSecondary)
                            }
                        }
                    }
                    .tint(TradeDemoColors.accent)
                }
            }
        }
    }

    /// Topics are the app's choice; whether anything arrives at all is the phone's. With
    /// notifications off, every switch here is moot, so the screen says so and offers the way out.
    private var blockedCard: some View {
        SectionCard {
            Text("Notifications are turned off for Trade Demo, so none of these will arrive.")
                .font(.subheadline)
                .foregroundStyle(TradeDemoColors.textPrimary)
            Button("Open notification settings", action: openNotificationSettings)
                .buttonStyle(OutlineButtonStyle())
                .padding(.top, 12)
        }
    }

    private func binding(for key: String) -> Binding<Bool> {
        Binding(
            get: {
                guard case .loaded(let topics) = load else { return false }
                return topics.first { $0.key == key }?.subscribed ?? false
            },
            set: { subscribed in
                guard case .loaded(var topics) = load, let index = topics.firstIndex(where: { $0.key == key }) else { return }
                topics[index].subscribed = subscribed
                topics[index].chosen = true
                load = .loaded(topics)
                Analytics.topics.set(key, subscribed: subscribed)
            }
        )
    }

    private func fetch() {
        load = .loading
        Analytics.topics.fetch { result in
            switch result {
            case .success(let topics):
                load = .loaded(topics)
            case .failure(let error):
                load = .failed(Self.describe(error))
            }
        }
    }

    private func readPermission() {
        Analytics.push.notificationsEnabled { enabled in
            DispatchQueue.main.async { allowed = enabled }
        }
    }

    private func openNotificationSettings() {
        let target: String
        if #available(iOS 16.0, *) {
            target = UIApplication.openNotificationSettingsURLString
        } else {
            target = UIApplication.openSettingsURLString
        }
        guard let url = URL(string: target) else { return }
        UIApplication.shared.open(url)
    }

    private static func describe(_ error: Error) -> String {
        switch error as? TopicsError {
        case .notInitialized:
            return "Analytics isn't configured in this build — set an ingest key in Config.xcconfig."
        case .http(let status) where status == 503:
            return "The server is busy right now. Try again in a moment."
        case .http(let status):
            return "The server answered HTTP \(status)."
        case .network:
            return "No connection to the server."
        case .malformed:
            return "The server's answer couldn't be read."
        case nil:
            return error.localizedDescription
        }
    }
}
