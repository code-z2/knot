import UIKit

enum FontLaunchAudit {
  static func logFontsOnLaunch() {
    #if DEBUG
    let installedFonts: [(family: String, name: String)] = UIFont.familyNames
      .sorted()
      .flatMap { family in
        UIFont.fontNames(forFamilyName: family)
          .sorted()
          .map { (family: family, name: $0) }
      }

    let trackedFamilies = ["Inter", "Roboto"]
    for trackedFamily in trackedFamilies {
      let matchedFonts = installedFonts.filter {
        $0.family.localizedCaseInsensitiveContains(trackedFamily)
          || $0.name.localizedCaseInsensitiveContains(trackedFamily)
      }

      if matchedFonts.isEmpty {
        print("[FontLaunchAudit] No \(trackedFamily) fonts detected at launch.")
        continue
      }

      print("[FontLaunchAudit] \(trackedFamily) fonts detected at launch (\(matchedFonts.count)):")
      for entry in matchedFonts {
        print("[FontLaunchAudit] - family=\"\(entry.family)\" name=\"\(entry.name)\"")
      }
    }
    #endif
  }
}
