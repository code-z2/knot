import SwiftUI

struct SplashView: View {
    var body: some View {
        ZStack {
            AppThemeColor.fixedDarkSurface.ignoresSafeArea()
            VStack {
                LogoMark()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(width: 199, height: 195)
            .padding(36)
        }
    }
}

#Preview {
    SplashView()
        .preferredColorScheme(.dark)
}
