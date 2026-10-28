import Funnelbase
import SwiftUI

private struct IntroPage: Identifiable {
    let id: Int
    let icon: String
    let title: String
    let body: String
}

private let introPages: [IntroPage] = [
    IntroPage(
        id: 0,
        icon: "chart.bar",
        title: "Follow the market",
        body: "Fifty S&P 500 constituents with live-looking prices. Tap any of them for the "
            + "company detail, and favourite the ones you want on your dashboard."
    ),
    IntroPage(
        id: 1,
        icon: "chart.pie",
        title: "Watch your portfolio",
        body: "Positions, cash and the day's move in one figure at the top of the dashboard, "
            + "recalculated from the same prices the market list shows."
    ),
    IntroPage(
        id: 2,
        icon: "list.bullet.rectangle",
        title: "Track your orders",
        body: "Pending, filled and cancelled orders with quantity, price and total cost — and a "
            + "news feed for the tickers you follow."
    ),
]

/// The sign-up flow: three intro pages, then the username step.
///
/// The intro is a pager rather than three navigation destinations because swiping is what makes
/// an onboarding carousel feel like one, and three destinations that only ever go forwards is a
/// back stack pretending to be a carousel.
///
/// That has one consequence for analytics, handled below: a page change is not a navigation
/// change, so this screen reports its pages itself. A page-styled `TabView` moves its selection
/// once a swipe has settled, which is the behaviour wanted — a screen reported mid-drag is a
/// screen nobody looked at.
struct SignUpFlow: View {

    let onSignedUp: (String) -> Void
    let onBack: () -> Void

    @State private var page = 0
    @State private var onUsernameStep = false

    var body: some View {
        Group {
            if onUsernameStep {
                UsernameStep(onSignedUp: onSignedUp)
            } else {
                intro
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .tradeDemoScreenBackground()
        .navigationTitle(onUsernameStep ? "Create account" : "Getting started")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                // Back off the username step returns to the intro rather than out of sign-up,
                // which is where the person came from.
                Button {
                    if onUsernameStep { onUsernameStep = false } else { onBack() }
                } label: {
                    Image(systemName: "chevron.left")
                }
                .accessibilityLabel("Back")
            }
        }
        .tradeDemoNavigationBar()
    }

    private var intro: some View {
        VStack(spacing: 0) {
            TabView(selection: $page) {
                ForEach(introPages) { item in
                    IntroPageContent(page: item).tag(item.id)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .onAppear { reportPage(page) }
            .onChange(of: page) { reportPage($0) }

            PageIndicator(pageCount: introPages.count, currentPage: page)
                .padding(.bottom, 24)

            HStack {
                Button("Skip") { onUsernameStep = true }
                    .font(.headline)
                    .foregroundStyle(TradeDemoColors.accent)

                Spacer()

                Button(isLastPage ? "Continue" : "Next") {
                    if isLastPage {
                        onUsernameStep = true
                    } else {
                        withAnimation { page += 1 }
                    }
                }
                .font(.headline)
                .foregroundStyle(TradeDemoColors.onAccent)
                .padding(.horizontal, 22)
                .padding(.vertical, 12)
                .background(Capsule().fill(TradeDemoColors.accent))
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
        }
    }

    private var isLastPage: Bool { page == introPages.count - 1 }

    /// The intro's pages are screens in their own right, which is the whole reason the Sign-Up
    /// funnel has six steps rather than two.
    private func reportPage(_ page: Int) {
        guard !onUsernameStep else { return }
        Analytics.screen(Screens.signUpIntro(page))
    }
}

private struct IntroPageContent: View {
    let page: IntroPage

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            Image(systemName: page.icon)
                .font(.system(size: 56, weight: .semibold))
                .foregroundStyle(TradeDemoColors.accent)
                .padding(.bottom, 28)
            Text(page.title)
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(TradeDemoColors.textPrimary)
                .multilineTextAlignment(.center)
                .padding(.bottom, 12)
            Text(page.body)
                .font(.subheadline)
                .foregroundStyle(TradeDemoColors.textSecondary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .padding(.horizontal, 32)
    }
}

private struct PageIndicator: View {
    let pageCount: Int
    let currentPage: Int

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<pageCount, id: \.self) { index in
                Capsule()
                    .fill(index == currentPage ? TradeDemoColors.accent : TradeDemoColors.outline)
                    .frame(width: index == currentPage ? 24 : 8, height: 8)
                    .animation(.easeInOut(duration: 0.2), value: currentPage)
            }
        }
    }
}

/// The final step: the username the whole identity hangs off.
///
/// The derived id is shown live as you type. That is the point of the screen — it makes the
/// determinism visible rather than asserted in a comment, and it is the value to paste into a
/// search when checking in the dashboard that events arrived.
private struct UsernameStep: View {

    let onSignedUp: (String) -> Void

    @State private var username = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Pick a username. No password, no email — the username is all this demo needs.")
                .font(.subheadline)
                .foregroundStyle(TradeDemoColors.textSecondary)
                .padding(.bottom, 24)

            LabelledField(label: "Username", text: $username)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            Text("Analytics user id")
                .font(.caption)
                .foregroundStyle(TradeDemoColors.textSecondary)
                .padding(.top, 16)
            Text(isBlank ? "—" : UserId.forUsername(username))
                .font(.numeric)
                .foregroundStyle(TradeDemoColors.accent)
            Text("Derived from the username, so signing in with it again is the same person.")
                .font(.caption)
                .foregroundStyle(TradeDemoColors.textSecondary)

            Button("Create account") { onSignedUp(username) }
                .buttonStyle(AccentButtonStyle())
                .disabled(isBlank)
                .opacity(isBlank ? 0.5 : 1)
                .padding(.top, 28)

            Spacer()
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .trackScreenView(Screens.signUpUsername)
    }

    private var isBlank: Bool {
        username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
