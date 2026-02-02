import SwiftUI

struct LogoMark: View {
    var body: some View {
        Image("LogoMark")
            .renderingMode(.original)
            .frame(width: 127, height: 123)
    }
}

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        LogoMark()
    }
}
