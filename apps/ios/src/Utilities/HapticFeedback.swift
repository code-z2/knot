import SwiftUI

enum AppHaptic {
    case selection
    case lightImpact
    case mediumImpact
    case success
    case error
    case warning

    var sensoryFeedback: SensoryFeedback {
        switch self {
        case .selection: .selection
        case .lightImpact: .impact(flexibility: .rigid, intensity: 0.5)
        case .mediumImpact: .impact(flexibility: .rigid, intensity: 0.7)
        case .success: .success
        case .error: .error
        case .warning: .warning
        }
    }
}
