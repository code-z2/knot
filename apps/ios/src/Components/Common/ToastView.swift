import SwiftUI

enum ToastStyle {
  case neutral
  case success
  case error
}

struct ToastView: View {
  let message: String
  var style: ToastStyle = .neutral

  /// Convenience for ProfileView's `isError` pattern.
  init(message: String, isError: Bool) {
    self.message = message
    self.style = isError ? .error : .success
  }

  init(message: String, style: ToastStyle = .neutral) {
    self.message = message
    self.style = style
  }

  var body: some View {
    Text(message)
      .font(AppTypography.monoSmall)
      .foregroundStyle(foregroundColor)
      .padding(.horizontal, 14)
      .padding(.vertical, 10)
      .background(
        RoundedRectangle(cornerRadius: AppCornerRadius.md, style: .continuous)
          .fill(AppThemeColor.fillPrimary)
      )
      .transition(.move(edge: .bottom).combined(with: .opacity))
  }

  private var foregroundColor: Color {
    switch style {
    case .neutral: AppThemeColor.labelPrimary
    case .success: AppThemeColor.accentGreen
    case .error: AppThemeColor.accentRed
    }
  }
}
