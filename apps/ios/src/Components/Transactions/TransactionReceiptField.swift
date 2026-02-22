import SwiftUI

struct TransactionReceiptField<Content: View>: View {
    let label: LocalizedStringKey
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            Text(label)
                .font(.custom("RobotoMono-Regular", size: 12))
                .foregroundStyle(AppThemeColor.labelSecondary)

            content()
        }
    }
}
