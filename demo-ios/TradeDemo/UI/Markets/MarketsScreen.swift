import SwiftUI

struct MarketsScreen: View {

    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var navigator: Navigator

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(appState.market.instruments) { instrument in
                    InstrumentRow(
                        instrument: instrument,
                        isFavourite: appState.isFavourite(instrument.symbol),
                        onToggleFavourite: { appState.toggleFavourite(instrument.symbol) },
                        onSelect: { navigator.push(.instrument(instrument.symbol)) }
                    )
                    Divider().overlay(TradeDemoColors.outline)
                }
            }
            .padding(.bottom, 16)
        }
        .tradeDemoScreenBackground()
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                TitleWithSubtitle(
                    title: "Markets",
                    subtitle: "\(appState.market.instruments.count) instruments · S&P 500"
                )
            }
        }
        .tradeDemoNavigationBar()
        .trackScreenView(Screens.markets)
    }
}

private struct InstrumentRow: View {

    let instrument: Instrument
    let isFavourite: Bool
    let onToggleFavourite: () -> Void
    let onSelect: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onToggleFavourite) {
                Image(systemName: isFavourite ? "star.fill" : "star")
                    .foregroundStyle(isFavourite ? TradeDemoColors.accent : TradeDemoColors.textSecondary)
                    .frame(width: 40, height: 40)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            // The label says what the tap does, not what the icon looks like — a screen reader
            // user needs the action, not the glyph.
            .accessibilityLabel(
                isFavourite
                    ? "Remove \(instrument.symbol) from favourites"
                    : "Add \(instrument.symbol) to favourites"
            )

            Button(action: onSelect) {
                HStack {
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
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, 4)
        .padding(.trailing, 16)
        .padding(.vertical, 10)
    }
}
