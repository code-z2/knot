import SwiftUI

struct LogoMark: View {
  var body: some View {
    Image("LogoMark")
      .renderingMode(.original)
      .resizable()
      .aspectRatio(127.0 / 123.0, contentMode: .fit)
  }
}

#Preview {
  ZStack {
    Color.black.ignoresSafeArea()
    LogoMark()
      .frame(width: 127, height: 123)
  }
}
