import SwiftUI

struct PreferenceRow: View {
    enum Trailing {
        case chevron
        case toggle(isOn: Binding<Bool>)
        case valueChevron(String)
        case localizedValueChevron(LocalizedStringKey)
        case custom(AnyView)
    }

    let title: Text
    let iconName: String
    let iconBackground: Color
    let trailing: Trailing
    var action: (() -> Void)?

    var body: some View {
        Group {
            if let action {
                Button(action: action) { rowContent }
                    .buttonStyle(.plain)
            } else {
                rowContent
            }
        }
    }

    var rowContent: some View {
        HStack {
            HStack(spacing: AppSpacing.sm) {
                IconBadge(
                    style: .solid(
                        background: iconBackground,
                        icon: AppThemeColor.grayWhite,
                    ),
                    contentPadding: 6,
                    cornerRadius: AppCornerRadius.sm,
                    borderWidth: 0,
                ) {
                    Image(systemName: iconName)
                        .font(.system(size: 14, weight: .medium))
                        .frame(width: 14, height: 14)
                }

                title
                    .font(.custom("Roboto-Medium", size: 15))
                    .foregroundStyle(AppThemeColor.labelPrimary)
            }

            Spacer(minLength: 0)

            switch trailing {
            case .chevron:
                ChevronIcon()
            case let .toggle(isOn):
                ToggleSwitch(isOn: isOn)
            case let .valueChevron(value):
                HStack(spacing: 10) {
                    Text(value)
                        .font(.custom("Roboto-Regular", size: 15))
                        .foregroundStyle(AppThemeColor.labelSecondary)
                    ChevronIcon()
                }
            case let .localizedValueChevron(value):
                HStack(spacing: 10) {
                    Text(value)
                        .font(.custom("Roboto-Regular", size: 15))
                        .foregroundStyle(AppThemeColor.labelSecondary)
                    ChevronIcon()
                }
            case let .custom(view):
                view
            }
        }
        .frame(maxWidth: .infinity)
    }
}
