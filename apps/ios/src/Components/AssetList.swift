import SwiftUI

struct MockAsset: Identifiable, Hashable {
  enum Section: Hashable {
    case suggested
    case all
  }

  enum ItemVariant: Hashable {
    case standard
    case valueOnly
    case withChange(PriceChange)
  }

  struct PriceChange: Hashable {
    enum Direction: Hashable {
      case up
      case down
    }

    let direction: Direction
    let percentageText: String
  }

  let id: String
  let symbol: String
  let name: String
  let amountText: String
  let valueText: String
  let iconAssetName: String
  let section: Section
  let variant: ItemVariant
  let keywords: [String]
}

enum MockAssetData {
  static let portfolio: [MockAsset] = [
    .init(
      id: "usdc", symbol: "USDC", name: "USD Coin", amountText: "36.42", valueText: "$36.21",
      iconAssetName: "Icons/currency_ethereum_circle", section: .suggested, variant: .standard,
      keywords: ["stablecoin", "usd"]
    ),
    .init(
      id: "eth", symbol: "ETH", name: "Ethereum", amountText: "0.0234", valueText: "$84.93",
      iconAssetName: "Icons/currency_ethereum_circle", section: .suggested, variant: .valueOnly,
      keywords: ["ethereum", "gas"]
    ),
    .init(
      id: "bnb", symbol: "BNB", name: "BNB", amountText: "1.28", valueText: "$36.21",
      iconAssetName: "Icons/currency_ethereum_circle", section: .suggested, variant: .standard,
      keywords: ["binance"]
    ),
    .init(
      id: "zsh", symbol: "ZSH", name: "Zcash", amountText: "36.42", valueText: "$36.21",
      iconAssetName: "Icons/currency_ethereum_circle", section: .all, variant: .standard,
      keywords: ["privacy"]
    ),
    .init(
      id: "bat", symbol: "BAT", name: "Basic Attention Token", amountText: "124.10",
      valueText: "$36.21",
      iconAssetName: "Icons/currency_ethereum_circle", section: .all,
      variant: .withChange(.init(direction: .down, percentageText: "3.24%")),
      keywords: ["attention", "browser"]
    ),
    .init(
      id: "btc", symbol: "BTC", name: "Bitcoin", amountText: "0.0005", valueText: "$36.21",
      iconAssetName: "Icons/currency_ethereum_circle", section: .all,
      variant: .withChange(.init(direction: .up, percentageText: "1.18%")),
      keywords: ["bitcoin", "satoshi"]
    ),
    .init(
      id: "usdt", symbol: "USDT", name: "Tether", amountText: "36.42", valueText: "$36.21",
      iconAssetName: "Icons/currency_ethereum_circle", section: .all, variant: .standard,
      keywords: ["stablecoin", "tether"]
    ),
    .init(
      id: "doge", symbol: "DOGE", name: "Dogecoin", amountText: "36.42", valueText: "$36.21",
      iconAssetName: "Icons/currency_ethereum_circle", section: .all, variant: .standard,
      keywords: ["meme", "doge"]
    ),
  ]
}

enum AssetListState: Equatable {
  case loading
  case loaded([MockAsset])
}

struct AssetList: View {
  let query: String
  let state: AssetListState
  var showSectionLabels = true

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
          showSectionLabels: showSectionLabels
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
  let assets: [MockAsset]
  let showSectionLabels: Bool

  private var filteredAssets: [MockAsset] {
    SearchSystem.filter(
      query: query,
      items: assets,
      toDocument: {
        SearchDocument(
          id: $0.id,
          title: $0.symbol,
          keywords: [$0.name, $0.valueText, $0.amountText] + $0.keywords
        )
      },
      itemID: { $0.id }
    )
  }

  private var suggestedAssets: [MockAsset] {
    filteredAssets.filter { $0.section == .suggested }
  }

  private var allAssets: [MockAsset] {
    filteredAssets.filter { $0.section == .all }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      if !suggestedAssets.isEmpty {
        section(title: "SUGGESTED", assets: suggestedAssets)
      }

      if !allAssets.isEmpty {
        section(title: "ALL", assets: allAssets)
      }

      if filteredAssets.isEmpty {
        Text("No assets found")
          .font(.custom("RobotoMono-Medium", size: 12))
          .foregroundStyle(AppThemeColor.labelSecondary)
          .padding(.horizontal, 8)
      }
    }
  }

  private func section(title: String, assets: [MockAsset]) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      if showSectionLabels {
        Text(title)
          .font(.custom("RobotoMono-Medium", size: 12))
          .foregroundStyle(AppThemeColor.labelSecondary)
      }

      VStack(alignment: .leading, spacing: 8) {
        ForEach(assets) { asset in
          AssetItem(asset: asset)
        }
      }
    }
  }
}

private struct AssetItem: View {
  let asset: MockAsset

  var body: some View {
    HStack(spacing: 0) {
      HStack(spacing: 16) {
        Image(asset.iconAssetName)
          .resizable()
          .scaledToFit()
          .frame(width: 32, height: 32)

        VStack(alignment: .leading, spacing: 0) {
          Text(asset.symbol)
            .font(.custom("Inter-Regular_Medium", size: 16))
            .foregroundStyle(AppThemeColor.labelVibrantPrimary)

          if showsAmount {
            Text(asset.amountText)
              .font(.custom("RobotoMono-Medium", size: 12))
              .foregroundStyle(AppThemeColor.labelVibrantSecondary)
          }
        }
      }

      Spacer(minLength: 8)

      VStack(alignment: .trailing, spacing: 2) {
        Text(asset.valueText)
          .font(.custom("Inter-Regular_Medium", size: 12))
          .foregroundStyle(AppThemeColor.labelVibrantPrimary)

        if case .withChange(let change) = asset.variant {
          AssetPriceChange(change: change)
        }
      }
      .frame(width: 178, alignment: .trailing)
    }
    .padding(.horizontal, 8)
    .padding(.vertical, 6)
    .frame(minHeight: 44)
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private var showsAmount: Bool {
    switch asset.variant {
    case .valueOnly: false
    case .standard, .withChange: true
    }
  }
}

private struct AssetPriceChange: View {
  let change: MockAsset.PriceChange

  var body: some View {
    HStack(spacing: 8) {
      RoundedRectangle(cornerRadius: 6, style: .continuous)
        .fill(backgroundColor)
        .frame(width: 18, height: 18)
        .overlay {
          Image(iconAssetName)
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .frame(width: 8, height: 8)
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

  private var iconAssetName: String {
    switch change.direction {
    case .up: "Icons/arrow_up"
    case .down: "Icons/arrow_down"
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
    VStack(alignment: .leading, spacing: 12) {
      if showSectionLabels {
        RoundedRectangle(cornerRadius: 4, style: .continuous)
          .fill(AppThemeColor.fillSecondary)
          .frame(width: 70, height: 10)
          .modifier(ShimmerEffect())
      }

      VStack(spacing: 8) {
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
      HStack(spacing: 16) {
        Circle()
          .fill(AppThemeColor.fillSecondary)
          .frame(width: 32, height: 32)

        VStack(alignment: .leading, spacing: 5) {
          RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(AppThemeColor.fillSecondary)
            .frame(width: 46, height: 12)

          RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(AppThemeColor.fillPrimary)
            .frame(width: 34, height: 10)
        }
      }

      Spacer(minLength: 8)

      RoundedRectangle(cornerRadius: 4, style: .continuous)
        .fill(AppThemeColor.fillSecondary)
        .frame(width: 52, height: 12)
        .frame(width: 178, alignment: .trailing)
    }
    .padding(.horizontal, 8)
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

#Preview {
  ZStack {
    AppThemeColor.fixedDarkSurface.ignoresSafeArea()
    ScrollView {
      VStack(spacing: 18) {
        SearchInput(text: .constant(""), width: nil)
        AssetList(query: "", state: .loaded(MockAssetData.portfolio))
        AssetList(query: "", state: .loading)
      }
      .padding()
    }
  }
}
