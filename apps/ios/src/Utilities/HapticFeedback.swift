import UIKit

enum HapticFeedback {
  static func selection(enabled: Bool) {
    guard enabled else { return }
    #if targetEnvironment(simulator)
    return
    #else
    UISelectionFeedbackGenerator().selectionChanged()
    #endif
  }

  static func mediumImpact(enabled: Bool) {
    guard enabled else { return }
    #if targetEnvironment(simulator)
    return
    #else
    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    #endif
  }
}
