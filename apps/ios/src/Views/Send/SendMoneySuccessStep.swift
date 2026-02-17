import SwiftUI

struct SuccessCheckmark: View {
  var body: some View {
    GeometryReader { proxy in
      Image("LogoMark")
        .renderingMode(.template)
        .resizable()
        .aspectRatio(127.0 / 123.0, contentMode: .fit)
        .foregroundStyle(AppThemeColor.accentGreen)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .mask(alignment: .bottomTrailing) {
          Rectangle()
            .frame(
              width: proxy.size.width * 0.76,
              height: proxy.size.height * 0.62
            )
            .offset(
              x: proxy.size.width * 0.04,
              y: proxy.size.height * 0.07
            )
        }
    }
  }
}
