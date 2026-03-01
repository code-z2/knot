import NukeUI
import SwiftUI

/// Displays a remote token logo from a URL, with a circle placeholder fallback.
struct TokenLogo: View {
    let url: URL?
    var size: CGFloat = 32

    var body: some View {
        LazyImage(url: url) { state in
            if let image = state.image {
                image
                    .resizable()
                    .scaledToFill()
            } else {
                Circle()
                    .fill(AppThemeColor.fillSecondary)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }
}
