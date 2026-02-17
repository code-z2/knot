import SwiftUI
import UIKit

private func parseHex(_ hex: String) -> (r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat) {
  let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
  var value: UInt64 = 0
  Scanner(string: cleaned).scanHexInt64(&value)

  switch cleaned.count {
  case 6:
    return (
      r: CGFloat((value >> 16) & 0xFF) / 255,
      g: CGFloat((value >> 8) & 0xFF) / 255,
      b: CGFloat(value & 0xFF) / 255,
      a: 1
    )
  case 8:
    return (
      r: CGFloat((value >> 24) & 0xFF) / 255,
      g: CGFloat((value >> 16) & 0xFF) / 255,
      b: CGFloat((value >> 8) & 0xFF) / 255,
      a: CGFloat(value & 0xFF) / 255
    )
  default:
    return (r: 0, g: 0, b: 0, a: 1)
  }
}

extension Color {
  init(hex: String) {
    let c = parseHex(hex)
    self.init(.sRGB, red: Double(c.r), green: Double(c.g), blue: Double(c.b), opacity: Double(c.a))
  }
}

extension UIColor {
  convenience init(hex: String) {
    let c = parseHex(hex)
    self.init(red: c.r, green: c.g, blue: c.b, alpha: c.a)
  }
}
