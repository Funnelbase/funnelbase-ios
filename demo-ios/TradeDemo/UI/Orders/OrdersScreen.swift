import SwiftUI

struct OrdersScreen: View {

    @EnvironmentObject private var appState: AppState

    // The chips filter within this screen; they are not a navigation change, so nothing is
    // tracked here. Only screen and tab changes report a screen view.
    @State private var selected: OrderStatus = .pending

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                ForEach(OrderStatus.allCases, id: \.self) { status in
                    FilterChip(
                        label: "\(status.label) (\(count(of: status)))",
                        isSelected: selected == status
                    ) {
                        selected = status
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            if visible.isEmpty {
                Text("No \(selected.label.lowercased()) orders.")
                    .font(.subheadline)
                    .foregroundStyle(TradeDemoColors.textSecondary)
                    .padding(24)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(visible) { order in
                            OrderRow(order: order)
                            Divider().overlay(TradeDemoColors.outline)
                        }
                    }
                    .padding(.bottom, 16)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .tradeDemoScreenBackground()
        .navigationTitle("Orders")
        .navigationBarTitleDisplayMode(.inline)
        .tradeDemoNavigationBar()
        .trackScreenView(Screens.orders)
    }

    private var visible: [Order] {
        appState.market.orders.filter { $0.status == selected }
    }

    private func count(of status: OrderStatus) -> Int {
        appState.market.orders.filter { $0.status == status }.count
    }
}

private struct FilterChip: View {
    let label: String
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            Text(label)
                .font(.footnote.weight(.medium))
                .foregroundStyle(isSelected ? TradeDemoColors.onAccent : TradeDemoColors.textSecondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(
                    Capsule()
                        .fill(isSelected ? TradeDemoColors.accentMuted : Color.clear)
                        .overlay(Capsule().strokeBorder(TradeDemoColors.outline, lineWidth: isSelected ? 0 : 1))
                )
        }
        .buttonStyle(.plain)
    }
}

private struct OrderRow: View {
    let order: Order

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text(order.symbol)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(TradeDemoColors.textPrimary)
                Pill(order.side.label.uppercased(), color: order.side == .buy ? TradeDemoColors.up : TradeDemoColors.down)
                Spacer()
                Pill(order.status.label, color: order.status.color)
            }

            Text("\(order.companyName) · \(order.id) · \(Money.relativeTime(order.placedMinutesAgo))")
                .font(.caption)
                .foregroundStyle(TradeDemoColors.textSecondary)
                .lineLimit(1)

            StatRow("Quantity", Money.quantity(order.quantity))
                .padding(.top, 10)
            StatRow("Price", Money.usd(order.price))

            HStack {
                Text("Cost")
                    .font(.subheadline)
                    .foregroundStyle(TradeDemoColors.textSecondary)
                Spacer()
                // The one figure someone actually checks against quantity x price, so it gets
                // the emphasis the other two rows do not.
                Text(Money.usd(order.cost))
                    .font(.numeric)
                    .foregroundStyle(TradeDemoColors.accent)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }
}

private extension OrderStatus {
    var color: Color {
        switch self {
        case .pending: return TradeDemoColors.pending
        case .filled: return TradeDemoColors.filled
        case .cancelled: return TradeDemoColors.cancelled
        }
    }
}
