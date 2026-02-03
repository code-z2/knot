import SwiftUI

@main
struct AppEntry: App {
  var body: some Scene {
    WindowGroup {
      AppRootView()
        .preferredColorScheme(.dark)
    }
  }

  init() {
    FontRegistry.registerBundledFonts()
  }
}
