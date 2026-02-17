import Balance
import SwiftUI

private let suggestedSymbols: Set<String> = ["ETH", "USDC", "USDT"]

enum AssetListState: Equatable {
  case loading
  case loaded([TokenBalance])
}

struct AssetList: View {
  let query: String
  let state: AssetListState
  var displayCurrencyCode: String = "USD"
  var displayLocale: Locale = .current
  var usdToSelectedRate: Decimal = 1
  var showSectionLabels = true
  var onSelect: ((TokenBalance) -> Void)? = nil

  var body: some View {
    Group {
      switch state {
      case .loading:
        AssetListSkeleton(showSectionLabels: showSectionLabels)
          .transition(.opacity)
      case .loaded(let assets):
        AssetListContent(
          query: query,
          assets: assets,
          displayCurrencyCode: displayCurrencyCode,
          displayLocale: displayLocale,
          usdToSelectedRate: usdToSelectedRate,
          showSectionLabels: showSectionLabels,
          onSelect: onSelect
        )
        .transition(.opacity)
      }
    }
    .animation(.easeInOut(duration: 0.22), value: isLoading)
  }

  private var isLoading: Bool {
    if case .loading = state { return true }
    return false
  }
}

private struct AssetListContent: View {
  let query: String
  let assets: [TokenBalance]
  let displayCurrencyCode: String
  let displayLocale: Locale
  let usdToSelectedRate: Decimal
  let showSectionLabels: Bool
  let onSelect: ((TokenBalance) -> Void)?

  private var filteredAssets: [TokenBalance] {
    SearchSystem.filter(
      query: query,
      items: assets,
      toDocument: {
        SearchDocument(
          id: $0.id,
          title: $0.symbol,
          keywords: [
            $0.name,
            formatValueText(for: $0),
            $0.formattedBalance,
          ]
        )
      },
      itemID: { $0.id }
    )
  }

  private var suggestedAssets: [TokenBalance] {
    filteredAssets.filter { suggestedSymbols.contains($0.symbol.uppercased()) }
  }

  private var allAssets: [TokenBalance] {
    filteredAssets.filter { !suggestedSymbols.contains($0.symbol.uppercased()) }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      if !suggestedAssets.isEmpty {
        section(title: "asset_list_section_suggested", assets: suggestedAssets)
      }

      if !allAssets.isEmpty {
        section(title: "asset_list_section_all", assets: allAssets)
      }

      if filteredAssets.isEmpty {
        Text("asset_list_empty")
          .font(.custom("RobotoMono-Medium", size: 12))
          .foregroundStyle(AppThemeColor.labelSecondary)
          .padding(.horizontal, AppSpacing.xs)
      }
    }
  }

  private func section(title: LocalizedStringKey, assets: [TokenBalance]) -> some View {
    VStack(alignment: .leading, spacing: AppSpacing.sm) {
      if showSectionLabels {
        Text(title)
          .font(.custom("RobotoMono-Medium", size: 12))
          .foregroundStyle(AppThemeColor.labelSecondary)
      }

      VStack(alignment: .leading, spacing: AppSpacing.xs) {
        ForEach(Array(assets.enumerated()), id: \.element.id) { index, asset in
          let formattedValueText = formatValueText(for: asset)
          AssetItem(
            asset: asset,
            valueText: formattedValueText,
            onTap: onSelect == nil ? nil : { onSelect?(asset) }
          )
          .modifier(StaggeredAppearModifier(index: index))
        }
      }
    }
  }

  private func formatValueText(for asset: TokenBalance) -> String {
    CurrencyDisplayFormatter.format(
      amount: asset.totalValueUSD * usdToSelectedRate,
      currencyCode: displayCurrencyCode,
      locale: displayLocale
    )
  }
}

private struct AssetItem: View {
  let asset: TokenBalance
  let valueText: String
  var onTap: (() -> Void)? = nil

  var body: some View {
    Group {
      if let onTap {
        Button(action: onTap) {
          rowContent
        }
        .buttonStyle(.plain)
      } else {
        rowContent
      }
    }
  }

  private var rowContent: some View {
    HStack(spacing: 0) {
      HStack(spacing: AppSpacing.md) {
        TokenLogo(url: asset.logoURL, size: 32)

        VStack(alignment: .leading, spacing: 0) {
          Text(asset.symbol)
            .font(.custom("Inter-Regular_Medium", size: 16))
            .foregroundStyle(AppThemeColor.labelVibrantPrimary)

          Text(asset.formattedBalance)
            .font(.custom("RobotoMono-Medium", size: 12))
            .foregroundStyle(AppThemeColor.labelVibrantSecondary)
        }
      }

      Spacer(minLength: AppSpacing.xs)

      VStack(alignment: .trailing, spacing: 2) {
        Text(valueText)
          .font(.custom("Inter-Regular_Medium", size: 12))
          .foregroundStyle(AppThemeColor.labelVibrantPrimary)

        if let change = priceChange {
          AssetPriceChange(change: change)
        }
      }
      .frame(width: 178, alignment: .trailing)
    }
    .padding(.horizontal, AppSpacing.xs)
    .padding(.vertical, 6)
    .frame(minHeight: 44)
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private var priceChange: PriceChange? {
    guard let ratio = asset.priceChangeRatio24h else { return nil }
    let absPercent = abs(ratio) * 100
    let formatter = NumberFormatter()
    formatter.numberStyle = .decimal
    formatter.minimumFractionDigits = 2
    formatter.maximumFractionDigits = 2
    let percentText = (formatter.string(from: absPercent as NSDecimalNumber) ?? "0.00") + "%"
    return PriceChange(
      direction: ratio >= 0 ? .up : .down,
      percentageText: ratio >= 0 ? "+\(percentText)" : "-\(percentText)"
    )
  }
}

struct PriceChange: Hashable {
  enum Direction: Hashable {
    case up
    case down
  }

  let direction: Direction
  let percentageText: String
}

private struct AssetPriceChange: View {
  let change: PriceChange

  var body: some View {
    HStack(spacing: AppSpacing.xs) {
      RoundedRectangle(cornerRadius: 6, style: .continuous)
        .fill(backgroundColor)
        .frame(width: 18, height: 18)
        .overlay {
          Image(systemName: iconSystemName)
            .font(.system(size: 12, weight: .semibold))
            .frame(width: 12, height: 12)
            .foregroundStyle(accentColor)
        }

      Text(change.percentageText)
        .font(.custom("RobotoMono-Regular", size: 13))
        .tracking(-0.26)
        .foregroundStyle(accentColor)
    }
  }

  private var accentColor: Color {
    switch change.direction {
    case .up: AppThemeColor.accentGreen
    case .down: AppThemeColor.accentRed
    }
  }

  private var backgroundColor: Color {
    switch change.direction {
    case .up: AppThemeColor.accentGreen.opacity(0.12)
    case .down: AppThemeColor.accentRed.opacity(0.10)
    }
  }

  private var iconSystemName: String {
    switch change.direction {
    case .up: "arrow.up"
    case .down: "arrow.down"
    }
  }
}

private struct AssetListSkeleton: View {
  let showSectionLabels: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      skeletonSection(title: "SUGGESTED", count: 3)
      skeletonSection(title: "ALL", count: 5)
    }
  }

  private func skeletonSection(title: String, count: Int) -> some View {
    VStack(alignment: .leading, spacing: AppSpacing.sm) {
      if showSectionLabels {
        RoundedRectangle(cornerRadius: AppCornerRadius.xs, style: .continuous)
          .fill(AppThemeColor.fillSecondary)
          .frame(width: 70, height: 10)
          .modifier(ShimmerEffect())
      }

      VStack(spacing: AppSpacing.xs) {
        ForEach(0..<count, id: \.self) { _ in
          AssetItemSkeletonRow()
        }
      }
    }
  }
}

private struct AssetItemSkeletonRow: View {
  var body: some View {
    HStack(spacing: 0) {
      HStack(spacing: AppSpacing.md) {
        Circle()
          .fill(AppThemeColor.fillSecondary)
          .frame(width: 32, height: 32)

        VStack(alignment: .leading, spacing: 5) {
          RoundedRectangle(cornerRadius: AppCornerRadius.xs, style: .continuous)
            .fill(AppThemeColor.fillSecondary)
            .frame(width: 46, height: 12)

          RoundedRectangle(cornerRadius: AppCornerRadius.xs, style: .continuous)
            .fill(AppThemeColor.fillPrimary)
            .frame(width: 34, height: 10)
        }
      }

      Spacer(minLength: AppSpacing.xs)

      RoundedRectangle(cornerRadius: AppCornerRadius.xs, style: .continuous)
        .fill(AppThemeColor.fillSecondary)
        .frame(width: 52, height: 12)
        .frame(width: 178, alignment: .trailing)
    }
    .padding(.horizontal, AppSpacing.xs)
    .padding(.vertical, 6)
    .frame(minHeight: 44)
    .frame(maxWidth: .infinity, alignment: .leading)
    .modifier(ShimmerEffect())
  }
}

private struct ShimmerEffect: ViewModifier {
  @State private var xOffset: CGFloat = -240

  func body(content: Content) -> some View {
    content
      .overlay {
        LinearGradient(
          colors: [
            Color.clear,
            AppThemeColor.grayWhite.opacity(0.15),
            Color.clear,
          ],
          startPoint: .leading,
          endPoint: .trailing
        )
        .rotationEffect(.degrees(10))
        .offset(x: xOffset)
      }
      .mask(content)
      .onAppear {
        withAnimation(.linear(duration: 1.15).repeatForever(autoreverses: false)) {
          xOffset = 280
        }
      }
  }
}

private struct StaggeredAppearModifier: ViewModifier {
  let index: Int
  @State private var isVisible = false

  func body(content: Content) -> some View {
    content
      .opacity(isVisible ? 1 : 0)
      .offset(y: isVisible ? 0 : 8)
      .onAppear {
        withAnimation(.easeOut(duration: 0.25).delay(Double(index) * 0.035)) {
          isVisible = true
        }
      }
  }
}

#Preview {
  ZStack {
    AppThemeColor.fixedDarkSurface.ignoresSafeArea()
    ScrollView {
      VStack(spacing: 18) {
        SearchInput(text: .constant(""), width: nil)
        AssetList(query: "", state: .loading)
      }
      .padding()
    }
  }
}
