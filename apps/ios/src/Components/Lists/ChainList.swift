import RPC
import SwiftUI

struct ChainOption: Identifiable, Hashable {
    let id: String
    let name: String
    let assetName: String
    let rpcChainID: UInt64
    let keywords: [String]
}

enum ChainCatalog {
    private static let mainnetPopularIDs: Set<String> = ["ethereum", "base", "arbitrum"]
    private static let testnetPopularIDs: Set<String> = ["sepolia", "base-sepolia", "arbitrum-sepolia"]

    static var configured: [ChainOption] {
        ChainRegistry.getChains().map { descriptor in
            ChainOption(
                id: descriptor.slug,
                name: descriptor.name,
                assetName: descriptor.assetName,
                rpcChainID: descriptor.chainID,
                keywords: descriptor.keywords,
            )
        }
    }

    static var suggested: [ChainOption] {
        let source = configured
        guard !source.isEmpty else { return [] }
        let popularIDs =
            ChainSupportRuntime.resolveMode() == .limitedTestnet ? testnetPopularIDs : mainnetPopularIDs
        let result = source.filter { popularIDs.contains($0.id) }
        if !result.isEmpty { return result }
        return Array(source.prefix(3))
    }

    static var remaining: [ChainOption] {
        let suggestedIDs = Set(suggested.map(\.id))
        return configured.filter { !suggestedIDs.contains($0.id) }
    }
}

struct ChainList: View {
    let query: String
    let onSelect: (ChainOption) -> Void

    private var suggestedChains: [ChainOption] {
        SearchSystem.filter(
            query: query,
            items: ChainCatalog.suggested,
            toDocument: {
                SearchDocument(
                    id: $0.id,
                    title: $0.name,
                    keywords: [$0.id, String($0.rpcChainID)] + $0.keywords,
                )
            },
            itemID: { $0.id },
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
                    keywords: [$0.id, String($0.rpcChainID)] + $0.keywords,
                )
            },
            itemID: { $0.id },
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
            .padding(.trailing, AppSpacing.xxs)
        }
    }

    private func section(title: String, chains: [ChainOption]) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Text(title)
                .font(.custom("RobotoMono-Medium", size: 12))
                .foregroundStyle(AppThemeColor.labelSecondary)
                .textCase(.uppercase)

            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                ForEach(chains) { chain in
                    ChainRow(
                        chain: chain,
                        onTap: { onSelect(chain) },
                    )
                }
            }
        }
    }
}

private struct ChainRow: View {
    let chain: ChainOption
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: AppSpacing.md) {
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
            .padding(.horizontal, AppSpacing.xs)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    ZStack {
        AppThemeColor.fixedDarkSurface.ignoresSafeArea()
        VStack(spacing: AppSpacing.sm) {
            SearchInput(text: .constant(""), width: nil)
            ChainList(query: "", onSelect: { _ in })
        }
        .padding()
    }
}
