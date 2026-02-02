import SwiftUI

@main
struct MetuApp: App {
    var body: some Scene {
        WindowGroup {
            ThemePreviewView()
                .preferredColorScheme(.dark)
        }
    }
}
