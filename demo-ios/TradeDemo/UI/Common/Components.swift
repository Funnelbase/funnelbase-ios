import SwiftUI

/// A price move.
///
/// The glyph is not decoration. Green-up/red-down is the convention, but it is a hue distinction
/// that roughly one man in twelve cannot make, so direction is always carried by the ▲/▼ as well
/// — colour reinforces the shape rather than being the only thing saying it.
struct ChangeText: View {
    let changePercent: Double
    var absolute: Double?

    init(changePercent: Double, absolute: Double? = nil) {
        self.changePercent = changePercent
        self.absolute = absolute
    }

    var body: some View {
        Text(text)
            .font(.numeric)
            .foregroundStyle(changePercent >= 0 ? TradeDemoColors.up : TradeDemoColors.down)
    }

    private var text: String {
        var result = changePercent >= 0 ? "▲ " : "▼ "
        if let absolute {
            result += Money.signedUsd(absolute) + "  "
        }
        result += Money.signedPercent(changePercent)
        return result
    }
}

/// A card. One corner radius and one border colour for the whole app, defined here.
struct SectionCard<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 16).fill(TradeDemoColors.surface))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(TradeDemoColors.outline, lineWidth: 1))
    }
}

/// A section heading with an optional trailing action, e.g. "See all".
struct SectionHeader<Action: View>: View {
    private let title: String
    private let action: Action

    init(_ title: String, @ViewBuilder action: () -> Action) {
        self.title = title
        self.action = action()
    }

    var body: some View {
        HStack {
            Text(title)
                .font(.headline)
                .foregroundStyle(TradeDemoColors.textPrimary)
            Spacer()
            action
        }
        .frame(maxWidth: .infinity)
    }
}

extension SectionHeader where Action == EmptyView {
    init(_ title: String) {
        self.init(title) { EmptyView() }
    }
}

/// A small filled pill — order status, sector, side.
struct Pill: View {
    let text: String
    let color: Color

    init(_ text: String, color: Color) {
        self.text = text
        self.color = color
    }

    var body: some View {
        Text(text)
            .font(.caption2)
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(RoundedRectangle(cornerRadius: 6).fill(color.opacity(0.14)))
    }
}

/// A `Label  Value` row, used for the stats grid and anywhere else two columns of text need to
/// line up. The value is monospaced so a stack of these has a straight right edge.
struct StatRow: View {
    let label: String
    let value: String

    init(_ label: String, _ value: String) {
        self.label = label
        self.value = value
    }

    var body: some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(TradeDemoColors.textSecondary)
            Spacer()
            Text(value)
                .font(.numeric)
                .foregroundStyle(TradeDemoColors.textPrimary)
        }
        .frame(maxWidth: .infinity)
    }
}

/// A two-line navigation title, which is what the Android demo's top app bars have and what
/// SwiftUI's `navigationTitle` cannot express on its own.
struct TitleWithSubtitle: View {
    let title: String
    let subtitle: String?

    var body: some View {
        VStack(spacing: 1) {
            Text(title)
                .font(.headline)
                .foregroundStyle(TradeDemoColors.textPrimary)
            if let subtitle {
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(TradeDemoColors.textSecondary)
            }
        }
    }
}
