import CoreText
import Foundation

enum FontRegistry {
  static func registerBundledFonts() {
    guard let resourceURL = Bundle.main.resourceURL else { return }
    guard let enumerator = FileManager.default.enumerator(
      at: resourceURL,
      includingPropertiesForKeys: [.isRegularFileKey],
      options: [.skipsHiddenFiles]
    ) else { return }

    for case let fileURL as URL in enumerator {
      let ext = fileURL.pathExtension.lowercased()
      guard ext == "ttf" || ext == "otf" || ext == "ttc" else { continue }

      var error: Unmanaged<CFError>?
      let ok = CTFontManagerRegisterFontsForURL(fileURL as CFURL, .process, &error)
      if ok { continue }

      if let cfError = error?.takeRetainedValue() {
        let nsError = cfError as Error as NSError
        if nsError.domain == kCTFontManagerErrorDomain as String,
           nsError.code == CTFontManagerError.alreadyRegistered.rawValue {
          continue
        }
#if DEBUG
        print("Font registration failed for \(fileURL.lastPathComponent): \(nsError)")
#endif
      }
    }
  }
}
