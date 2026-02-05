import SwiftUI

struct BackNavigationButton: View {
  private let hitSize: CGFloat = 44
  private let visualSize: CGFloat = 38
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
    .buttonStyle(.plain)
    .background(glassBackground)
    .accessibilityLabel("Back")
  }

  @ViewBuilder
  private var glassBackground: some View {
    if #available(iOS 26.0, *) {
      Circle()
        .frame(width: visualSize, height: visualSize)
        .glassEffect(.regular.interactive(), in: .circle)
    } else {
      Circle()
        .fill(.ultraThinMaterial)
        .frame(width: visualSize, height: visualSize)
    }
  }
}

#Preview {
  ZStack {
    AppThemeColor.fixedDarkSurface.ignoresSafeArea()
    BackNavigationButton(tint: AppThemeColor.labelSecondary) {}
  }
}

