import SwiftUI

struct BackNavigationButton: View {
  private let hitSize: CGFloat = 44
  private let visualSize: CGFloat = 44
  let tint: Color
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Image(systemName: "chevron.backward")
        .font(.system(size: 17, weight: .semibold))
        .foregroundStyle(tint)
        .frame(width: hitSize, height: hitSize)
        .contentShape(.circle)
    }
    .clipShape(.circle)
    .modifier(BackNavigationBackgroundModifier())
    .frame(width: visualSize, height: visualSize)
    .buttonStyle(.plain)
    .accessibilityLabel("Back")
  }
}

private struct BackNavigationBackgroundModifier: ViewModifier {
  func body(content: Content) -> some View {
    if #available(iOS 26.0, *) {
      content
        .glassEffect(.regular.interactive(), in: .circle)
    } else {
      content
        .background(AppThemeColor.fillPrimary)
    }
  }
}

#Preview {
  ZStack {
    AppThemeColor.fixedDarkSurface.ignoresSafeArea()
    BackNavigationButton(tint: AppThemeColor.labelSecondary) {}
  }
}
