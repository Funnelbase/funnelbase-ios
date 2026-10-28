import SwiftUI

struct NewsScreen: View {

    @EnvironmentObject private var appState: AppState

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(appState.market.news) { article in
                    ArticleRow(article: article)
                    Divider().overlay(TradeDemoColors.outline)
                }
            }
            .padding(.bottom, 16)
        }
        .tradeDemoScreenBackground()
        .navigationTitle("News")
        .navigationBarTitleDisplayMode(.inline)
        .tradeDemoNavigationBar()
        .trackScreenView(Screens.news)
    }
}

private struct ArticleRow: View {
    let article: NewsArticle

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(article.headline)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(TradeDemoColors.textPrimary)
            Text(article.summary)
                .font(.subheadline)
                .foregroundStyle(TradeDemoColors.textSecondary)
            Text("\(article.source) · \(Money.relativeTime(article.minutesAgo))")
                .font(.caption2)
                .foregroundStyle(TradeDemoColors.textSecondary)
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }
}
