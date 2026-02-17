import SwiftUI

enum AppSpacing {
  static let xxs: CGFloat = 4
  static let xs: CGFloat = 8
  static let sm: CGFloat = 12
  static let md: CGFloat = 16
  static let lg: CGFloat = 20
  static let xl: CGFloat = 24
  static let xxl: CGFloat = 32
  static let xxxl: CGFloat = 44
}

enum AppCornerRadius {
  static let xs: CGFloat = 4
  static let sm: CGFloat = 8
  static let md: CGFloat = 12
  static let lg: CGFloat = 20
  static let xl: CGFloat = 28
  static let xxl: CGFloat = 36
  static let pill: CGFloat = 44
}

enum AppAnimation {
  static let quickDuration: Double = 0.18
  static let standard = Animation.easeInOut(duration: 0.18)
  static let gentle = Animation.easeInOut(duration: 0.20)
  static let spring = Animation.spring(response: 0.26, dampingFraction: 0.82)
  static let slideTransition: AnyTransition = .asymmetric(
    insertion: .move(edge: .trailing).combined(with: .opacity),
    removal: .move(edge: .trailing).combined(with: .opacity)
  )
}
