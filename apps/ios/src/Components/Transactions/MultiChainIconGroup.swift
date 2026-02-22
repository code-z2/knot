import SwiftUI

struct MultiChainIconGroup: View {
    let networkAssetNames: [String]
    private let iconSize: CGFloat = 24
    private let overlap: CGFloat = 12

    var body: some View {
        ZStack(alignment: .leading) {
            ForEach(Array(networkAssetNames.enumerated()), id: \.offset) { index, assetName in
                Circle()
                    .fill(AppThemeColor.backgroundPrimary)
                    .overlay(
                        Circle().stroke(AppThemeColor.separatorNonOpaque, lineWidth: 1),
                    )
                    .frame(width: iconSize, height: iconSize)
                    .overlay {
                        Image(assetName)
                            .resizable()
                            .scaledToFill()
                            .frame(width: iconSize, height: iconSize)
                            .clipShape(Circle())
                    }
                    .offset(x: CGFloat(index) * overlap)
            }
        }
        .frame(
            width: iconSize + CGFloat(max(networkAssetNames.count - 1, 0)) * overlap,
            height: iconSize,
            alignment: .leading,
        )
    }
}
