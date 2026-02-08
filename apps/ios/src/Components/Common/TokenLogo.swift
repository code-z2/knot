import SwiftUI

/// Displays a remote token logo from a URL, with a circle placeholder fallback.
struct TokenLogo: View {
  let url: URL?
  var size: CGFloat = 32

  var body: some View {
    AsyncImage(url: url) { phase in
      switch phase {
      case .success(let image):
        image
          .resizable()
          .scaledToFill()
      default:
        Circle()
          .fill(AppThemeColor.fillSecondary)
      }
    }
    .frame(width: size, height: size)
    .clipShape(Circle())
  }
}
