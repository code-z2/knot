import SwiftUI

struct SplashView: View {
    var body: some View {
        GeometryReader { geo in
            ZStack {
                AppThemeColor.fixedDarkSurface.ignoresSafeArea()
                LogoMark()
                    .frame(width: 127, height: 123)
                    .position(
                        x: (geo.size.width * 0.3333) + 4 + (127 / 2),
                        y: (geo.size.height * 0.4167) + 10.83 + (123 / 2)
                    )
            }
        }
    }
}

#Preview {
    SplashView()
        .preferredColorScheme(.dark)
}
