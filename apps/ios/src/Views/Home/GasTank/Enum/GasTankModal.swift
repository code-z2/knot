import SwiftUI

enum GasTankModal: String, Identifiable {
  case addMoney

  var id: String {
    rawValue
  }

  var sheetKind: AppSheetKind {
    switch self {
    case .addMoney:
      .height(720)
    }
  }
}
