import SwiftUI
import UIKit

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
  var iconAssetName: String? = nil
  var iconURL: URL? = nil
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
    placeholderColor: Color? = nil
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

struct DropdownInputField<DropdownContent: View>: View {
  let variant: DropdownInputVariant
  let properties: DropdownInputProperties
  @Binding var query: String
  let badge: DropdownBadgeValue?
  @Binding var isExpanded: Bool
  var isFocused: Binding<Bool>? = nil
  var showsTrailingIcon = true
  var onExpandRequest: (() -> Void)? = nil
  var onBadgeTap: (() -> Void)? = nil
  var onTrailingIconTap: (() -> Void)? = nil
  @ViewBuilder let dropdownContent: () -> DropdownContent

  @FocusState private var isInputFocused: Bool
  @State private var rowFrame: CGRect = .zero

  var body: some View {
    topRow
      .overlay(alignment: .top) {
        Rectangle()
          .fill(AppThemeColor.separatorOpaque)
          .frame(height: 1)
      }
      .overlay(alignment: .topLeading) {
        if variantSupportsDropdown && isExpanded && isPopoverVisible {
          dropdownContainer
            .offset(y: properties.rowHeight + 4)
            .zIndex(40)
            .transition(.opacity)
        }
      }
      .zIndex(isExpanded ? 40 : 1)
      .onChange(of: isExpanded) { _, expanded in
        if !expanded {
          isInputFocused = false
          setExternalFocus(false)
        }
      }
      .onChange(of: externalFocusValue) { _, shouldFocus in
        if showsInputField {
          isInputFocused = shouldFocus
        }
      }
      .onChange(of: showsInputField) { _, visible in
        if visible && externalFocusValue {
          DispatchQueue.main.async {
            isInputFocused = true
          }
        }
      }
      .onChange(of: isInputFocused) { _, focused in
        if variantSupportsDropdown, !focused {
          isExpanded = false
        }
        setExternalFocus(focused)
      }
  }

  @ViewBuilder
  private var topRow: some View {
    HStack(spacing: 8) {
      if let leadingIconAssetName = properties.leadingIconAssetName {
        Image(leadingIconAssetName)
          .renderingMode(.template)
          .resizable()
          .scaledToFit()
          .frame(width: 16, height: 16)
          .foregroundStyle(properties.textColor)
      }

      if let label = properties.label {
        Text(label)
          .font(.custom("Roboto-Medium", size: 15))
          .foregroundStyle(AppThemeColor.labelPrimary)
      }

      if showsInputField {
        TextField("", text: $query, prompt: placeholderPrompt)
          .font(properties.textFont)
          .foregroundStyle(properties.textColor)
          .textInputAutocapitalization(.never)
          .autocorrectionDisabled(true)
          .focused($isInputFocused)
          .onTapGesture {
            if variantSupportsDropdown {
              onExpandRequest?()
            }
            setExternalFocus(true)
          }
          .onChange(of: isInputFocused) { _, focused in
            if focused && variantSupportsDropdown {
              onExpandRequest?()
            }
          }
      } else if let badge {
        Button {
          onBadgeTap?()
          if variantSupportsDropdown {
            onExpandRequest?()
          }
          setExternalFocus(true)
          DispatchQueue.main.async {
            isInputFocused = true
          }
        } label: {
          badgeView(badge)
        }
        .buttonStyle(.plain)
      }

      Spacer(minLength: 0)

      if let trailingIconAssetName = resolvedTrailingIconAssetName {
        if let onTrailingIconTap {
          Button(action: onTrailingIconTap) {
            Image(trailingIconAssetName)
              .renderingMode(.template)
              .resizable()
              .scaledToFit()
              .frame(width: 24, height: 24)
              .foregroundStyle(AppThemeColor.accentBrown)
          }
          .buttonStyle(.plain)
        } else {
          Image(trailingIconAssetName)
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .frame(width: 24, height: 24)
            .foregroundStyle(AppThemeColor.accentBrown)
        }
      }
    }
    .padding(.horizontal, properties.horizontalPadding)
    .frame(height: properties.rowHeight)
    .background(
      GeometryReader { proxy in
        Color.clear
          .preference(key: DropdownInputRowFramePreferenceKey.self, value: proxy.frame(in: .global))
      }
    )
    .contentShape(Rectangle())
    .onTapGesture {
      if showsInputField {
        isInputFocused = true
        setExternalFocus(true)
      }
      if variantSupportsDropdown {
        onExpandRequest?()
      }
    }
    .onPreferenceChange(DropdownInputRowFramePreferenceKey.self) { rowFrame = $0 }
  }

  private var dropdownContainer: some View {
    VStack(alignment: .leading, spacing: 0) {
      dropdownContent()
    }
    .padding(10)
    .frame(maxWidth: .infinity, alignment: .leading)
    .frame(height: popoverHeight, alignment: .top)
    .background(AppThemeColor.backgroundPrimary)
  }

  private var variantSupportsDropdown: Bool {
    switch variant {
    case .address, .chain, .asset:
      return true
    case .noDropdown:
      return false
    }
  }

  private var resolvedTrailingIconAssetName: String? {
    guard showsTrailingIcon else { return nil }
    if let trailingIconAssetName = properties.trailingIconAssetName {
      return trailingIconAssetName
    }
    if variantSupportsDropdown {
      return "Icons/scan"
    }
    return nil
  }

  private var showsInputField: Bool {
    switch variant {
    case .noDropdown:
      return true
    case .address, .chain, .asset:
      return badge == nil
    }
  }

  private var placeholderPrompt: Text {
    Text(properties.placeholder)
      .font(properties.textFont)
      .foregroundStyle(properties.placeholderColor ?? properties.textColor)
  }

  private var isPopoverVisible: Bool {
    isFocused?.wrappedValue ?? true
  }

  private var popoverHeight: CGFloat {
    let screenHeight = currentWindowHeight
    guard screenHeight > 0 else { return 480 }
    let available = screenHeight - rowFrame.maxY - 8
    return max(available, 120)
  }

  private var currentWindowHeight: CGFloat {
    let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
    let keyWindow =
      scenes
      .flatMap(\.windows)
      .first(where: \.isKeyWindow)
    return keyWindow?.bounds.height ?? 0
  }

  private var externalFocusValue: Bool {
    isFocused?.wrappedValue ?? false
  }

  private func setExternalFocus(_ value: Bool) {
    isFocused?.wrappedValue = value
  }

  @ViewBuilder
  private func badgeView(_ badge: DropdownBadgeValue) -> some View {
    if let iconAssetName = badge.iconAssetName {
      let icon: AppBadgeIcon =
        badge.iconStyle == .symbol ? .symbol(iconAssetName) : .network(iconAssetName)
      AppIconTextBadge(text: badge.text, icon: icon)
    } else if badge.iconURL != nil {
      HStack(spacing: 6) {
        TokenLogo(url: badge.iconURL, size: 16)
        Text(badge.text)
          .font(.custom("Roboto-Medium", size: 13))
          .foregroundStyle(AppThemeColor.labelPrimary)
      }
      .padding(.horizontal, 10)
      .padding(.vertical, 6)
      .background(
        RoundedRectangle(cornerRadius: 8, style: .continuous)
          .fill(AppThemeColor.fillPrimary)
      )
    } else {
      switch badge.validationState {
      case .valid:
        AppIconTextBadge(
          text: badge.text,
          icon: .symbol("Icons/check_verified_01"),
          textColor: .green
        )
      case .invalid:
        AppIconTextBadge(
          text: badge.text,
          icon: .symbol("Icons/x_close"),
          textColor: .red
        )
      case .validating:
        HStack(spacing: 6) {
          AppTextBadge(text: badge.text)
          ProgressView()
            .controlSize(.small)
        }
      case .idle:
        AppTextBadge(text: badge.text)
      }
    }
  }
}

private struct DropdownInputRowFramePreferenceKey: PreferenceKey {
  static var defaultValue: CGRect = .zero

  static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
    value = nextValue()
  }
}

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
          placeholderColor: AppThemeColor.labelSecondary
        ),
        query: $addressQuery,
        badge: nil,
        isExpanded: $expandedAddress,
        isFocused: .constant(false),
        showsTrailingIcon: false,
        onExpandRequest: {
          expandedAddress = true
          expandedChain = false
        }
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
          placeholderColor: AppThemeColor.labelSecondary
        ),
        query: $chainQuery,
        badge: nil,
        isExpanded: $expandedChain,
        isFocused: .constant(false),
        showsTrailingIcon: false,
        onExpandRequest: {
          expandedChain = true
          expandedAddress = false
        }
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
          placeholderColor: AppThemeColor.labelPrimary
        ),
        query: .constant(""),
        badge: nil,
        isExpanded: .constant(false),
        isFocused: .constant(false),
        showsTrailingIcon: false
      ) {
        EmptyView()
      }
    }
  }
}
