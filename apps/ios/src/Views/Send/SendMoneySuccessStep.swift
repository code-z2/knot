import SwiftUI

struct SuccessCheckmark: View {
  @State private var isVisible = false

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
        .scaleEffect(isVisible ? 1.0 : 0.6)
        .opacity(isVisible ? 1.0 : 0)
    }
    .onAppear {
      withAnimation(.spring(response: 0.45, dampingFraction: 0.65)) {
        isVisible = true
      }
    }
  }
}
