import SwiftUI

enum HomeModal: String, Identifiable {
    case assets

    var id: String {
        rawValue
    }

    var sheetKind: AppSheetKind {
        switch self {
        case .assets:
            .full
        }
    }
}
