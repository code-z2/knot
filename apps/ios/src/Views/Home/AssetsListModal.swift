import Balance
import SwiftUI

struct AssetsListModal: View {
    @Binding var query: String
    let state: AssetListState
    let displayCurrencyCode: String
    let displayLocale: Locale
    let usdToSelectedRate: Decimal

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SearchInput(text: $query, placeholderKey: "search_placeholder", width: nil)
                .padding(.horizontal, AppSpacing.lg)
                .padding(.top, 13)
                .padding(.bottom, 21)

            Rectangle()
                .fill(AppThemeColor.separatorOpaque)
                .frame(height: 4)

            ScrollView(showsIndicators: false) {
                AssetList(
                    query: query,
                    state: state,
                    displayCurrencyCode: displayCurrencyCode,
                    displayLocale: displayLocale,
                    usdToSelectedRate: usdToSelectedRate,
                )
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 28)
            }
            .padding(.horizontal, AppSpacing.lg)
            .padding(.top, AppSpacing.xl)
            .padding(.bottom, AppSpacing.xl)
        }
    }
}
