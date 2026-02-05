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
}
