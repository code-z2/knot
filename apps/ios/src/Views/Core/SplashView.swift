import SwiftUI

struct SplashView: View {
    var body: some View {
        ZStack {
            AppThemeColor.fixedDarkSurface.ignoresSafeArea()
            LogoMark()
                .frame(width: 127, height: 123)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
    }
}

#Preview {
    SplashView()
        .preferredColorScheme(.dark)
}
