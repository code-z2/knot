import SwiftUI

struct CurrencySelectionPage: View {
  let currencies: [CurrencyOption]
  let selectedCode: String
  let onSelect: (String) -> Void

  var body: some View {
    List {
      Section {
        ForEach(currencies) { currency in
          CurrencySelectionRow(
            title: Text(currency.code),
            subtitle: Text(currency.name),
            isSelected: currency.code == selectedCode,
            onTap: { onSelect(currency.code) }
          ) {
            IconBadge(
              style: .solid(
                background: badgeColor(for: currency.code),
                icon: AppThemeColor.grayWhite
              ),
              contentPadding: 6,
              cornerRadius: 9,
              borderWidth: 0
            ) {
              Image(systemName: currency.iconAssetName)
                .renderingMode(.template)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 14, height: 14)
            }
          }
        }
      }
    }
    .listStyle(.insetGrouped)
    .scrollContentBackground(.hidden)
    .scrollIndicators(.hidden)
  }

  private func badgeColor(for code: String) -> Color {
    switch code.uppercased() {
    case "USD":
      return Color(hex: "#3C9A5F")
    case "EUR":
      return Color(hex: "#2E6FD8")
    case "GBP":
      return Color(hex: "#3657A7")
    case "NGN":
      return Color(hex: "#008753")
    case "JPY":
      return Color(hex: "#BC002D")
    case "INR":
      return Color(hex: "#FF9933")
    case "RUB":
      return Color(hex: "#1C57A5")
    case "ARS":
      return Color(hex: "#627EEA")
    case "BRL":
      return Color(hex: "#008753")
    case "CNY":
      return Color(hex: "#FF9933")
    case "GHS":
      return Color(hex: "#BC002D")
    case "KRW":
      return Color(hex: "#627EEA")
    default:
      return AppThemeColor.accentBrown
    }
  }
}

private struct CurrencySelectionRow<Leading: View>: View {
  let title: Text
  let subtitle: Text?
  let isSelected: Bool
  let onTap: () -> Void
  let leading: () -> Leading

  var body: some View {
    Button(action: onTap) {
      HStack(spacing: 16) {
        leading()

        VStack(alignment: .leading) {
          title
            .font(.custom("Roboto-Medium", size: 15))
            .foregroundStyle(AppThemeColor.labelPrimary)
          if let subtitle {
            subtitle
              .font(.custom("RobotoMono-Medium", size: 12))
              .foregroundStyle(AppThemeColor.labelSecondary)
          }
        }

        Spacer(minLength: 0)

        if isSelected {
          Image(systemName: "checkmark")
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(AppThemeColor.accentBrown)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .buttonStyle(.plain)
  }
}

#Preview("Currency Selection") {
  ZStack {
    AppThemeColor.backgroundPrimary.ignoresSafeArea()
    CurrencySelectionPage(
      currencies: PreferencesStore.defaultCurrencies,
      selectedCode: "USD",
      onSelect: { _ in }
    )
    .padding(.top, AppHeaderMetrics.contentTopPadding)
  }
}
