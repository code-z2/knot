import Balance
import SwiftUI

enum SendMoneyKeypadKey: Hashable {
  case digit(String)
  case decimal
  case backspace
}

struct SendMoneyAmountDisplay: View {
  let primaryAmountText: String
  let primarySymbolText: String
  let secondaryAmountText: String
  let secondarySymbolText: String
  let onSwapTap: () -> Void

  var body: some View {
    HStack(alignment: .center, spacing: 0) {
      Spacer(minLength: 0)

      VStack(spacing: 2) {
        HStack(spacing: 4) {
          Text(primaryAmountText)
            .font(.custom("RobotoMono-Medium", size: 48))
            .foregroundStyle(AppThemeColor.labelVibrantPrimary)
            .lineLimit(1)
            .minimumScaleFactor(0.25)
            .allowsTightening(true)
            .layoutPriority(1)

          Text(primarySymbolText)
            .font(.custom("RobotoCondensed-Medium", size: 18))
            .foregroundStyle(AppThemeColor.labelVibrantSecondary)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .allowsTightening(true)
        }
        .frame(maxWidth: .infinity, minHeight: 58, maxHeight: 58, alignment: .bottom)

        HStack(spacing: 4) {
          Text(secondaryAmountText)
            .font(.custom("RobotoMono-Medium", size: 14))
            .foregroundStyle(AppThemeColor.labelSecondary)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .allowsTightening(true)
            .layoutPriority(1)

          Text(secondarySymbolText)
            .font(.custom("RobotoCondensed-Medium", size: 12))
            .foregroundStyle(AppThemeColor.labelVibrantSecondary)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .allowsTightening(true)
        }
        .frame(maxWidth: .infinity, minHeight: 18, maxHeight: 18, alignment: .top)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)

      Button(action: onSwapTap) {
        Image(systemName: "arrow.up.arrow.down")
          .font(.system(size: 16, weight: .medium))
          .frame(width: 16, height: 16)
          .foregroundStyle(AppThemeColor.glyphSecondary)
          .padding(8)
      }
      .buttonStyle(.plain)
      .accessibilityLabel(Text("send_money_accessibility_switch_amount_view"))
    }
    .frame(maxWidth: .infinity)
  }
}

struct SendMoneyBalanceWidget: View {
  let asset: TokenBalance
  let balanceText: String
  let onSwitchTap: () -> Void

  var body: some View {
    HStack(spacing: 16) {
        TokenLogo(url: asset.logoURL, size: 32)
            .frame(width: 37, height: 37)

      VStack(alignment: .leading, spacing: 2) {
        Text("\(asset.symbol) \(String(localized: "send_money_balance_suffix"))")
          .font(.custom("RobotoMono-Regular", size: 12))
          .foregroundStyle(AppThemeColor.labelSecondary)

        Text(balanceText)
          .font(.custom("RobotoMono-Medium", size: 16))
          .foregroundStyle(AppThemeColor.labelPrimary)
      }

      Spacer(minLength: 0)

      AppButton(
        label: "send_money_switch",
        variant: .neutral,
        size: .compact,
        underlinedLabel: true,
        foregroundColorOverride: AppThemeColor.labelSecondary,
        backgroundColorOverride: .clear
      ) {
        onSwitchTap()
      }
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 12)
    .frame(maxWidth: .infinity, minHeight: 65, alignment: .leading)
    .background(
      RoundedRectangle(cornerRadius: 16, style: .continuous)
        .fill(AppThemeColor.fillPrimary)
        .overlay(
          RoundedRectangle(cornerRadius: 16, style: .continuous)
            .stroke(AppThemeColor.fillSecondary, lineWidth: 1)
        )
    )
  }
}

struct SendMoneyNumericKeypad: View {
  var height: CGFloat = 332
  var rowSpacing: CGFloat = 36
  let onTapKey: (SendMoneyKeypadKey) -> Void

  private let rows: [[SendMoneyKeypadKey]] = [
    [.digit("1"), .digit("2"), .digit("3")],
    [.digit("4"), .digit("5"), .digit("6")],
    [.digit("7"), .digit("8"), .digit("9")],
    [.decimal, .digit("0"), .backspace],
  ]

  var body: some View {
    VStack(spacing: rowSpacing) {
      ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
        HStack(spacing: 0) {
          ForEach(Array(row.enumerated()), id: \.offset) { _, key in
            keypadKey(key)
              .frame(maxWidth: .infinity)
          }
        }
      }
    }
    .frame(maxWidth: .infinity)
    .frame(height: height)
  }

  @ViewBuilder
  private func keypadKey(_ key: SendMoneyKeypadKey) -> some View {
    Button {
      onTapKey(key)
    } label: {
      Group {
        switch key {
        case .digit(let value):
          Text(value)
        case .decimal:
          Text("•")
        case .backspace:
          Image(systemName: "delete.left")
            .font(.system(size: 12, weight: .semibold))
            .frame(width: 12, height: 12)
        }
      }
      .font(.custom("Roboto-Medium", size: 20))
      .foregroundStyle(AppThemeColor.labelPrimary)
      .frame(width: 72, height: 40)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }
}
