import SwiftUI
import UIKit

@main
struct AppEntry: App {
  init() {
    FontLaunchAudit.logFontsOnLaunch()
  }

  var body: some Scene {
    WindowGroup {
      AppRootView()
    }
  }
}
