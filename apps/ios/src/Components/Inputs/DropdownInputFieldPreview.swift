import SwiftUI

#Preview {
    @Previewable @State var addressQuery = ""
    @Previewable @State var chainQuery = ""
    @Previewable @State var expandedAddress = false
    @Previewable @State var expandedChain = false

    ZStack {
        AppThemeColor.fixedDarkSurface.ignoresSafeArea()
        VStack(spacing: 0) {
            DropdownInputField(
                variant: .address,
                properties: .init(
                    placeholder: "address_book_placeholder_address_or_ens",
                    trailingIconAssetName: nil,
                    textColor: AppThemeColor.labelSecondary,
                    placeholderColor: AppThemeColor.labelSecondary,
                ),
                query: $addressQuery,
                badge: nil,
                isExpanded: $expandedAddress,
                isFocused: .constant(false),
                showsTrailingIcon: false,
                onExpandRequest: {
                    expandedAddress = true
                    expandedChain = false
                },
            ) {
                Text("Address dropdown")
                    .font(.custom("Roboto-Regular", size: 13))
                    .foregroundStyle(AppThemeColor.labelSecondary)
            }

            DropdownInputField(
                variant: .chain,
                properties: .init(
                    placeholder: "address_book_placeholder_chain",
                    trailingIconAssetName: nil,
                    textColor: AppThemeColor.labelSecondary,
                    placeholderColor: AppThemeColor.labelSecondary,
                ),
                query: $chainQuery,
                badge: nil,
                isExpanded: $expandedChain,
                isFocused: .constant(false),
                showsTrailingIcon: false,
                onExpandRequest: {
                    expandedChain = true
                    expandedAddress = false
                },
            ) {
                Text("Chain dropdown")
                    .font(.custom("Roboto-Regular", size: 13))
                    .foregroundStyle(AppThemeColor.labelSecondary)
            }

            DropdownInputField(
                variant: .noDropdown,
                properties: .init(
                    placeholder: "address_book_placeholder_alias",
                    textFont: .custom("Inter-Regular_Medium", size: 14),
                    textColor: AppThemeColor.labelPrimary,
                    placeholderColor: AppThemeColor.labelPrimary,
                ),
                query: .constant(""),
                badge: nil,
                isExpanded: .constant(false),
                isFocused: .constant(false),
                showsTrailingIcon: false,
            ) {
                EmptyView()
            }
        }
    }
}
