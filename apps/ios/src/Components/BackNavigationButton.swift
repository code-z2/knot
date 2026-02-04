import SwiftUI

struct BackNavigationButton: View {
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Image("Icons/chevron_left")
        .renderingMode(.template)
        .resizable()
        .aspectRatio(contentMode: .fit)
        .frame(width: 24, height: 24)
        .foregroundStyle(AppThemeColor.glyphPrimary)
        .padding(6)
        .overlay(
          Circle().stroke(AppThemeColor.gray2, lineWidth: 2)
        )
    }
    .buttonStyle(.plain)
  }
}

#Preview {
  ZStack {
    AppThemeColor.fixedDarkSurface.ignoresSafeArea()
    BackNavigationButton {}
  }
}

