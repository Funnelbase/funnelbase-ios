import SwiftUI

extension Font {
    /// The numeric style: use for anything that sits in a column with other numbers.
    ///
    /// Prices, quantities and totals are set in a monospaced face wherever they line up in a
    /// column, so digits share a width and the decimal points form a straight edge down a list.
    /// Proportional digits make a price column look ragged even when every value is correctly
    /// formatted.
    static let numeric = Font.system(size: 15, weight: .medium, design: .monospaced)

    /// The same face, for a headline figure.
    static func numericDisplay(size: CGFloat) -> Font {
        .system(size: size, weight: .bold, design: .monospaced)
    }
}

extension View {

    /// The app's chrome, applied once at the root.
    ///
    /// Dark only, and deliberately so: the system's setting is not consulted. A trading app is a
    /// dark-UI genre, the palette was chosen against a near-black ground, and shipping a
    /// half-considered light theme so the toggle "works" would look worse in light mode than
    /// having no light mode at all. The Info.plist says `UIUserInterfaceStyle = Dark` for the
    /// same reason, so the keyboard and the system alerts agree with the app.
    func tradeDemoTheme() -> some View {
        preferredColorScheme(.dark)
            .tint(TradeDemoColors.accent)
            .background(TradeDemoColors.background)
    }
}

/// A filled accent button, the counterpart of Material's `Button`.
struct AccentButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(TradeDemoColors.onAccent)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(TradeDemoColors.accent.opacity(configuration.isPressed ? 0.7 : 1))
            )
    }
}

/// An outlined button, the counterpart of Material's `OutlinedButton`.
struct OutlineButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(TradeDemoColors.accent)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(TradeDemoColors.outline, lineWidth: 1)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(configuration.isPressed ? TradeDemoColors.surface : .clear)
                    )
            )
    }
}

/// A button that says it cannot be pressed rather than looking pressable and doing nothing.
struct DisabledButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(TradeDemoColors.cancelled)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(RoundedRectangle(cornerRadius: 12).fill(TradeDemoColors.surface))
    }
}
