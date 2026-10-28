import SwiftUI

struct DashboardScreen: View {

    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var navigator: Navigator

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                PortfolioValueCard(portfolio: appState.market.portfolio)
                FavouriteInstrumentsCard(
                    favourites: favourites,
                    onInstrumentSelected: { navigator.push(.instrument($0)) }
                )
                RecentNewsCard(
                    articles: Array(appState.market.news.prefix(3)),
                    onSeeAll: { navigator.select(.news) }
                )
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .tradeDemoScreenBackground()
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                TitleWithSubtitle(
                    title: "Dashboard",
                    subtitle: appState.username.map { "Signed in as \($0)" }
                )
            }
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                Button {
                    navigator.push(.pushSettings)
                } label: {
                    Image(systemName: "bell")
                }
                .accessibilityLabel("Notifications")

                Button {
                    appState.signOut()
                    navigator.reset()
                } label: {
                    Image(systemName: "rectangle.portrait.and.arrow.right")
                }
                .accessibilityLabel("Sign out")
            }
        }
        .tradeDemoNavigationBar()
        .trackScreenView(Screens.dashboard)
    }

    private var favourites: [Instrument] {
        appState.market.instruments.filter { appState.isFavourite($0.symbol) }
    }
}

private struct PortfolioValueCard: View {
    let portfolio: Portfolio

    var body: some View {
        SectionCard {
            Text("Portfolio value")
                .font(.footnote.weight(.medium))
                .foregroundStyle(TradeDemoColors.textSecondary)
                .padding(.bottom, 6)

            Text(Money.usd(portfolio.totalValue))
                .font(.numericDisplay(size: 32))
                .foregroundStyle(TradeDemoColors.textPrimary)
                .padding(.bottom, 8)

            ChangeText(changePercent: portfolio.dayChangePercent, absolute: portfolio.dayChange)
            Text("Today")
                .font(.caption)
                .foregroundStyle(TradeDemoColors.textSecondary)

            Divider()
                .overlay(TradeDemoColors.outline)
                .padding(.vertical, 14)

            HStack {
                LabelledAmount(label: "Invested", value: Money.usd(portfolio.investedValue))
                Spacer()
                LabelledAmount(label: "Cash", value: Money.usd(portfolio.cashUsd))
                Spacer()
                LabelledAmount(label: "Positions", value: "\(portfolio.holdings.count)")
            }
        }
    }
}

private struct LabelledAmount: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundStyle(TradeDemoColors.textSecondary)
            Text(value)
                .font(.numeric)
                .foregroundStyle(TradeDemoColors.textPrimary)
        }
    }
}

private struct FavouriteInstrumentsCard: View {
    let favourites: [Instrument]
    let onInstrumentSelected: (String) -> Void

    var body: some View {
        SectionCard {
            SectionHeader("Favourite instruments")

            if favourites.isEmpty {
                Text("Nothing favourited yet. Tap the star on any instrument in Markets.")
                    .font(.subheadline)
                    .foregroundStyle(TradeDemoColors.textSecondary)
                    .padding(.vertical, 12)
            } else {
                ForEach(favourites) { instrument in
                    Button {
                        onInstrumentSelected(instrument.symbol)
                    } label: {
                        HStack(alignment: .center) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(instrument.symbol)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(TradeDemoColors.textPrimary)
                                Text(instrument.name)
                                    .font(.caption)
                                    .foregroundStyle(TradeDemoColors.textSecondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(Money.usd(instrument.price))
                                    .font(.numeric)
                                    .foregroundStyle(TradeDemoColors.textPrimary)
                                ChangeText(changePercent: instrument.changePercent)
                            }
                        }
                        .padding(.vertical, 12)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

private struct RecentNewsCard: View {
    let articles: [NewsArticle]
    let onSeeAll: () -> Void

    var body: some View {
        SectionCard {
            SectionHeader("Recent news") {
                Button("See all", action: onSeeAll)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(TradeDemoColors.accent)
            }

            ForEach(articles) { article in
                VStack(alignment: .leading, spacing: 2) {
                    Text(article.headline)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(TradeDemoColors.textPrimary)
                        .lineLimit(2)
                    Text("\(article.source) · \(Money.relativeTime(article.minutesAgo))")
                        .font(.caption)
                        .foregroundStyle(TradeDemoColors.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 8)
            }
        }
    }
}
