import SwiftUI

struct ChainOption: Identifiable, Hashable {
  let id: String
  let name: String
  let assetName: String
  let keywords: [String]
}

enum ChainCatalog {
  static let all: [ChainOption] = [
    .init(id: "ethereum", name: "Ethereum", assetName: "ethereum", keywords: ["eth", "mainnet"]),
    .init(id: "base", name: "Base", assetName: "base", keywords: ["coinbase"]),
    .init(id: "arbitrum", name: "Arbitrum", assetName: "arbitrum", keywords: ["arb"]),
    .init(id: "optimism", name: "Optimism", assetName: "optimism", keywords: ["op"]),
    .init(id: "polygon", name: "Polygon", assetName: "polygon", keywords: ["matic", "pol"]),
    .init(id: "bnb-smart-chain", name: "BNB Smart Chain", assetName: "bnb-smart-chain", keywords: ["bnb", "bsc", "binance"]),
    .init(id: "blast", name: "Blast", assetName: "blast", keywords: []),
    .init(id: "linea", name: "Linea", assetName: "linea", keywords: []),
    .init(id: "lisk", name: "Lisk", assetName: "lisk", keywords: []),
    .init(id: "mode", name: "Mode", assetName: "mode", keywords: []),
    .init(id: "monad", name: "Monad", assetName: "monad", keywords: []),
    .init(id: "plasma", name: "Plasma", assetName: "plasma", keywords: []),
    .init(id: "scroll", name: "Scroll", assetName: "scroll", keywords: []),
    .init(id: "soneium", name: "Soneium", assetName: "soneium", keywords: []),
    .init(id: "unichain", name: "Unichain", assetName: "unichain", keywords: []),
    .init(id: "world-chain", name: "World Chain", assetName: "world-chain", keywords: ["world"]),
    .init(id: "zksync", name: "zkSync", assetName: "zksync", keywords: ["zk"]),
    .init(id: "zora", name: "Zora", assetName: "zora", keywords: []),
    .init(id: "hyperevm", name: "HyperEVM", assetName: "hyperevm", keywords: ["hyper"]),
    .init(id: "ink", name: "Ink", assetName: "ink", keywords: [])
  ]

  static let popularIDs: Set<String> = ["ethereum", "base", "arbitrum"]

  static let suggested: [ChainOption] = all.filter { popularIDs.contains($0.id) }
  static let remaining: [ChainOption] = all.filter { !popularIDs.contains($0.id) }
}

struct ChainList: View {
  let query: String
  let selectedChainID: String?
  let onSelect: (ChainOption) -> Void

  private var suggestedChains: [ChainOption] {
    SearchSystem.filter(
      query: query,
      items: ChainCatalog.suggested,
      toDocument: {
        SearchDocument(
          id: $0.id,
          title: $0.name,
          keywords: [$0.id] + $0.keywords
        )
      },
      itemID: { $0.id }
    )
  }

  private var allChains: [ChainOption] {
    SearchSystem.filter(
      query: query,
      items: ChainCatalog.remaining,
      toDocument: {
        SearchDocument(
          id: $0.id,
          title: $0.name,
          keywords: [$0.id] + $0.keywords
        )
      },
      itemID: { $0.id }
    )
  }

  var body: some View {
    ScrollView(showsIndicators: false) {
      VStack(alignment: .leading, spacing: 18) {
        if !suggestedChains.isEmpty {
          section(title: "SUGGESTED", chains: suggestedChains)
        }
        if !allChains.isEmpty {
          section(title: "ALL", chains: allChains)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.trailing, 4)
    }
  }

  private func section(title: String, chains: [ChainOption]) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      Text(title)
        .font(.custom("RobotoMono-Medium", size: 12))
        .foregroundStyle(AppThemeColor.labelSecondary)
        .textCase(.uppercase)

      VStack(alignment: .leading, spacing: 12) {
        ForEach(chains) { chain in
          ChainRow(
            chain: chain,
            isSelected: chain.id == selectedChainID,
            onTap: { onSelect(chain) }
          )
        }
      }
    }
  }
}

private struct ChainRow: View {
  let chain: ChainOption
  let isSelected: Bool
  let onTap: () -> Void

  var body: some View {
    Button(action: onTap) {
      HStack(spacing: 16) {
        Image(chain.assetName)
          .resizable()
          .scaledToFit()
          .frame(width: 32, height: 32)
          .clipShape(Circle())

        Text(chain.name)
          .font(.custom("Inter-Regular_Medium", size: 16))
          .foregroundStyle(AppThemeColor.labelVibrantPrimary)

        Spacer(minLength: 0)
      }
      .padding(.horizontal, 8)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(
        RoundedRectangle(cornerRadius: 8, style: .continuous)
          .fill(isSelected ? AppThemeColor.fillPrimary : .clear)
      )
    }
    .buttonStyle(.plain)
  }
}

#Preview {
  ZStack {
    AppThemeColor.fixedDarkSurface.ignoresSafeArea()
    VStack(spacing: 12) {
      SearchInput(text: .constant(""), width: nil)
      ChainList(query: "", selectedChainID: "base", onSelect: { _ in })
    }
    .padding()
  }
}
