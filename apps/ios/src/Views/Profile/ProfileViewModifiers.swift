import SwiftUI

struct ProfileGlassCapsuleButtonModifier: ViewModifier {
  func body(content: Content) -> some View {
    if #available(iOS 26.0, *) {
      content
        .buttonStyle(.glass)
    } else {
      content
        .background(
          Capsule()
            .fill(AppThemeColor.fillPrimary)
        )
    }
  }
}

struct ProfileProminentActionButtonModifier: ViewModifier {
  func body(content: Content) -> some View {
    if #available(iOS 26.0, *) {
      content
        .buttonStyle(.glassProminent)
    } else {
      content
        .foregroundStyle(AppThemeColor.backgroundPrimary)
        .background(
          Capsule()
            .fill(Color.blue)
        )
    }
  }
}
