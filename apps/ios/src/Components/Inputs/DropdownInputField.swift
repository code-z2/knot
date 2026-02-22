import SwiftUI
import UIKit

struct DropdownInputField<DropdownContent: View>: View {
    let variant: DropdownInputVariant
    let properties: DropdownInputProperties
    @Binding var query: String
    let badge: DropdownBadgeValue?
    @Binding var isExpanded: Bool
    var isFocused: Binding<Bool>?
    var showsTrailingIcon = true
    var onExpandRequest: (() -> Void)?
    var onBadgeTap: (() -> Void)?
    var onTrailingIconTap: (() -> Void)?
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
                if variantSupportsDropdown, isExpanded, isPopoverVisible {
                    dropdownContainer
                        .offset(y: properties.rowHeight + 4)
                        .zIndex(40)
                        .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
                }
            }
            .animation(AppAnimation.spring, value: isExpanded)
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
                if visible, externalFocusValue {
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

    private var topRow: some View {
        HStack(spacing: AppSpacing.xs) {
            if let leadingIconAssetName = properties.leadingIconAssetName {
                Image(systemName: leadingIconAssetName)
                    .font(.system(size: 16, weight: .medium))
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
                        if focused, variantSupportsDropdown {
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
                        Image(systemName: trailingIconAssetName)
                            .font(.system(size: 24, weight: .medium))
                            .frame(width: 24, height: 24)
                            .foregroundStyle(AppThemeColor.accentBrown)
                    }
                    .buttonStyle(.plain)
                } else {
                    Image(systemName: trailingIconAssetName)
                        .font(.system(size: 24, weight: .medium))
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
            },
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
            true
        case .noDropdown:
            false
        }
    }

    private var resolvedTrailingIconAssetName: String? {
        guard showsTrailingIcon else { return nil }
        if let trailingIconAssetName = properties.trailingIconAssetName {
            return trailingIconAssetName
        }
        if variantSupportsDropdown {
            return "qrcode.viewfinder"
        }
        return nil
    }

    private var showsInputField: Bool {
        switch variant {
        case .noDropdown:
            true
        case .address, .chain, .asset:
            badge == nil
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
                RoundedRectangle(cornerRadius: AppCornerRadius.lg, style: .continuous)
                    .fill(AppThemeColor.fillPrimary),
            )
        } else {
            switch badge.validationState {
            case .valid:
                AppIconTextBadge(
                    text: badge.text,
                    icon: .symbol("checkmark.seal.fill"),
                    textColor: AppThemeColor.labelPrimary,
                    iconColor: AppThemeColor.accentGreen,
                )
            case .invalid:
                AppIconTextBadge(
                    text: badge.text,
                    icon: .symbol("xmark.circle.fill"),
                    textColor: AppThemeColor.labelPrimary,
                    iconColor: AppThemeColor.accentRed,
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
