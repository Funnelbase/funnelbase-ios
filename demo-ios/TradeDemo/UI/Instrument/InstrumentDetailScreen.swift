import Funnelbase
import SwiftUI

struct InstrumentDetailScreen: View {

    let symbol: String

    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Group {
            if let instrument = appState.market.instrument(symbol) {
                detail(instrument)
            } else {
                // Reachable only in principle — every route into this screen comes from a list
                // built from the same instrument set, except a push's deep link, which can name
                // anything. Handled rather than force-unwrapped, because a crash on a stale
                // campaign is a worse answer than a back button.
                unknown
            }
        }
        .tradeDemoScreenBackground()
        .navigationTitle(symbol)
        .navigationBarTitleDisplayMode(.inline)
        .tradeDemoNavigationBar()
        // A screen was shown either way; whether an instrument was viewed is the event below.
        .trackScreenView(Screens.instrumentDetail)
    }

    private func detail(_ instrument: Instrument) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(instrument.name)
                        .font(.headline)
                        .foregroundStyle(TradeDemoColors.textPrimary)
                        .padding(.bottom, 6)
                    Pill(instrument.sector, color: TradeDemoColors.accent)
                    Text(Money.usd(instrument.price))
                        .font(.numericDisplay(size: 34))
                        .foregroundStyle(TradeDemoColors.textPrimary)
                        .padding(.top, 16)
                        .padding(.bottom, 6)
                    ChangeText(
                        changePercent: instrument.changePercent,
                        absolute: instrument.changeAbsolute
                    )
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                SectionCard {
                    Text("Today")
                        .font(.headline)
                        .foregroundStyle(TradeDemoColors.textPrimary)
                        .padding(.bottom, 12)
                    StatRow("Open", Money.usd(instrument.open))
                    StatRow("Day high", Money.usd(instrument.dayHigh))
                    StatRow("Day low", Money.usd(instrument.dayLow))
                    StatRow("Previous close", Money.usd(instrument.previousClose))
                    StatRow("Volume", Money.compact(Double(instrument.volume)))
                    StatRow("Market cap", Money.compactUsd(instrument.marketCapUsd))
                }

                SectionCard {
                    Text("About the company")
                        .font(.headline)
                        .foregroundStyle(TradeDemoColors.textPrimary)
                        .padding(.bottom, 8)
                    Text(instrument.about)
                        .font(.subheadline)
                        .foregroundStyle(TradeDemoColors.textSecondary)
                }

                // Deliberately inert. Wiring these up would mean order placement, which is a
                // feature this demo does not have — and a button that says it is unavailable is
                // better than a screen that looks like it cannot trade at all.
                HStack(spacing: 12) {
                    Button("Buy") {}
                        .buttonStyle(DisabledButtonStyle())
                        .disabled(true)
                    Button("Sell") {}
                        .buttonStyle(DisabledButtonStyle())
                        .disabled(true)
                }
                .padding(.bottom, 24)
            }
            .padding(.horizontal, 16)
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                let isFavourite = appState.isFavourite(instrument.symbol)
                Button {
                    appState.toggleFavourite(instrument.symbol)
                } label: {
                    Image(systemName: isFavourite ? "star.fill" : "star")
                        .foregroundStyle(isFavourite ? TradeDemoColors.accent : TradeDemoColors.textSecondary)
                }
                .accessibilityLabel(isFavourite ? "Remove from favourites" : "Add to favourites")
            }
        }
        // Which instrument is a product fact, not navigation context, so it is its own event
        // rather than a property on the screen view. Same firing rule as the screen view: once
        // on arriving, again on coming back, never on a re-render. Needs a catalog definition —
        // see `Events`.
        .task(id: instrument.symbol) {
            Analytics.track(
                Events.instrumentViewed,
                properties: [Events.propertySymbol: instrument.symbol]
            )
        }
    }

    private var unknown: some View {
        VStack(spacing: 12) {
            Text("No instrument \(symbol)")
                .font(.headline)
                .foregroundStyle(TradeDemoColors.textPrimary)
            Button("Back") { dismiss() }
                .buttonStyle(OutlineButtonStyle())
                .frame(maxWidth: 200)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }
}
