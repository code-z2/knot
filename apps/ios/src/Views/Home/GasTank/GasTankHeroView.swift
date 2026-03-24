import SwiftUI

struct GasTankHeroAsset: Identifiable, Hashable {
    let id: String
    let assetName: String
    let width: CGFloat
    let height: CGFloat
    let x: CGFloat
    let y: CGFloat
    let rotation: Double
}

struct GasTankHeroView: View {
    let animateAssets: Bool

    private let assets: [GasTankHeroAsset] = [
        .init(id: "ethereum", assetName: "ethereum-3d", width: 76, height: 76, x: -42, y: -6, rotation: -10),
        .init(id: "bitcoin", assetName: "bitcoin-3d", width: 72, height: 72, x: -2, y: -2, rotation: 8),
        .init(id: "usdc", assetName: "usdc-3d", width: 70, height: 70, x: 42, y: -8, rotation: 10),
        .init(id: "usdt", assetName: "usdt-3d", width: 54, height: 54, x: -20, y: 26, rotation: -5),
        .init(id: "dai", assetName: "dai-3d", width: 38, height: 38, x: 20, y: 34, rotation: 10),
        .init(id: "knot", assetName: "knot-3d", width: 34, height: 34, x: 0, y: 38, rotation: -8),
    ]

    var body: some View {
        ZStack {
            ForEach(Array(assets.enumerated()), id: \.element.id) { index, asset in
                Image(asset.assetName)
                    .resizable()
                    .scaledToFit()
                    .frame(width: asset.width, height: asset.height)
                    .rotationEffect(.degrees(animateAssets ? asset.rotation : 0))
                    .offset(
                        x: animateAssets ? asset.x : 0,
                        y: animateAssets ? asset.y : 0,
                    )
                    .scaleEffect(animateAssets ? 1 : 0.72)
                    .opacity(animateAssets ? 1 : 0)
                    .animation(
                        .spring(response: 0.52, dampingFraction: 0.8)
                            .delay(Double(index) * 0.05),
                        value: animateAssets
                    )
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 136)
        .padding(.top, AppSpacing.sm)
        .padding(.bottom, AppSpacing.md)
    }
}
