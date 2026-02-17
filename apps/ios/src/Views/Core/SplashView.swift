import SwiftUI

struct SplashView: View {
  @State private var isVisible = false

  var body: some View {
    ZStack {
      AppThemeColor.fixedDarkSurface.ignoresSafeArea()
      LogoMark()
        .frame(width: 127, height: 123)
        .scaleEffect(isVisible ? 1.0 : 0.85)
        .opacity(isVisible ? 1.0 : 0)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .ignoresSafeArea()
    .onAppear {
      withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
        isVisible = true
      }
    }
  }
}

#Preview {
  SplashView()
    .preferredColorScheme(.dark)
}
