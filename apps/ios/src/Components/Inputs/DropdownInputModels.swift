import SwiftUI

enum DropdownInputVariant: Hashable {
    case address
    case chain
    case asset
    case noDropdown
}

enum DropdownInputValidationMode: Hashable, Sendable {
    case strictAddressOrENS
    case flexible
}

enum DropdownBadgeIconStyle: Hashable {
    case network
    case symbol
}

enum AddressValidationState: Hashable {
    case idle
    case validating
    case valid
    case invalid
}

struct DropdownBadgeValue: Equatable {
    let text: String
    var iconAssetName: String?
    var iconURL: URL?
    var iconStyle: DropdownBadgeIconStyle = .network
    var validationState: AddressValidationState = .idle
}

struct DropdownInputProperties {
    var label: LocalizedStringKey?
    var placeholder: LocalizedStringKey
    var leadingIconAssetName: String?
    var trailingIconAssetName: String?
    var rowHeight: CGFloat
    var horizontalPadding: CGFloat
    var textFont: Font
    var textColor: Color
    var placeholderColor: Color?

    init(
        label: LocalizedStringKey? = nil,
        placeholder: LocalizedStringKey,
        leadingIconAssetName: String? = nil,
        trailingIconAssetName: String? = nil,
        rowHeight: CGFloat = 56,
        horizontalPadding: CGFloat = 24,
        textFont: Font = .custom("Roboto-Medium", size: 14),
        textColor: Color = AppThemeColor.labelSecondary,
        placeholderColor: Color? = nil,
    ) {
        self.label = label
        self.placeholder = placeholder
        self.leadingIconAssetName = leadingIconAssetName
        self.trailingIconAssetName = trailingIconAssetName
        self.rowHeight = rowHeight
        self.horizontalPadding = horizontalPadding
        self.textFont = textFont
        self.textColor = textColor
        self.placeholderColor = placeholderColor
    }
}
