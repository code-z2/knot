import SwiftUI

extension Color {
  init(hex: String) {
    let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
    var value: UInt64 = 0
    Scanner(string: cleaned).scanHexInt64(&value)

    let red: Double
    let green: Double
    let blue: Double
    let alpha: Double

    switch cleaned.count {
    case 6:
      red = Double((value >> 16) & 0xFF) / 255
      green = Double((value >> 8) & 0xFF) / 255
      blue = Double(value & 0xFF) / 255
      alpha = 1
    case 8:
      red = Double((value >> 24) & 0xFF) / 255
      green = Double((value >> 16) & 0xFF) / 255
      blue = Double((value >> 8) & 0xFF) / 255
      alpha = Double(value & 0xFF) / 255
    default:
      red = 0
      green = 0
      blue = 0
      alpha = 1
    }

    self.init(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
  }
}
