import SwiftUI
import UIKit

@main
struct AppEntry: App {
  var body: some Scene {
    WindowGroup {
      AppRootView()
        .preferredColorScheme(.dark)
    }
  }

  init() {
    #if DEBUG
    FontDebug.printAvailableFonts()
    #endif
  }
}

private enum FontDebug {
  static func printAvailableFonts() {
    let families = UIFont.familyNames.sorted()
    for family in families {
      let names = UIFont.fontNames(forFamilyName: family)
      if !names.isEmpty {
        print("Family: \(family) Font names: \(names)")
      }
    }
  }
}
