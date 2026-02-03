import SwiftUI

public enum AppThemeColor {
  // Core surfaces
  public static let backgroundPrimaryDark = Color(hex: "#000000")
  public static let backgroundPrimaryLight = Color(hex: "#FFFFFF")

  public static let labelPrimaryDark = Color(hex: "#FFFFFF")
  public static let labelPrimaryLight = Color(hex: "#000000")

  public static let labelSecondaryDark = Color(hex: "#EBEBF599")
  public static let labelSecondaryLight = Color(hex: "#3C3C4399")

  public static let labelVibrantPrimaryDark = Color(hex: "#FFFFFF")
  public static let labelVibrantPrimaryLight = Color(hex: "#333333")
  public static let labelVibrantSecondary = Color(hex: "#999999")

  // Brand + semantic
  public static let accentBrownDark = Color(hex: "#B78A66")
  public static let accentBrownLight = Color(hex: "#AC7F5E")

  public static let accentRed = Color(hex: "#FF383C")
  public static let accentGreen = Color(hex: "#30D158")
  public static let destructiveBackground = Color(hex: "#FF383C24")

  // UI primitives
  public static let fillPrimary = Color(hex: "#7878805C")
  public static let fillSecondaryDark = Color(hex: "#78788052")
  public static let fillSecondaryLight = Color(hex: "#78788029")
  public static let fillTertiary = Color(hex: "#7676803D")

  public static let separatorNonOpaqueDark = Color(hex: "#FFFFFF2B")
  public static let separatorNonOpaqueLight = Color(hex: "#0000001F")

  public static let separatorOpaqueDark = Color(hex: "#38383A")
  public static let separatorOpaqueLight = Color(hex: "#C6C6C8")

  public static let gray2Dark = Color(hex: "#636366")
  public static let gray2Light = Color(hex: "#AEAEB2")

  public static let toggleAXLabelOffDark = Color(hex: "#A6A6A6")
  public static let toggleAXLabelOffLight = Color(hex: "#B3B3B3")

  public static let glyphPrimaryDark = Color(hex: "#A6A6A6")
  public static let glyphSecondaryDary = Color(hex: "#4D4D4D")

  public static let grayBlack = Color(hex: "#000000")
  public static let grayWhite = Color(hex: "#FFFFFF")
  public static let offWhite = Color(hex: "#FFFDFD")

  // Fixed-dark screens (AI + onboarding in both modes)
  public static let fixedDarkSurface = Color(hex: "#000000")
  public static let fixedDarkText = Color(hex: "#FFFFFF")
  public static let onboardingProgressActive = offWhite

  // Dark-first app defaults
  public static let backgroundPrimary = backgroundPrimaryDark
  public static let labelPrimary = labelPrimaryDark
  public static let labelSecondary = labelSecondaryDark
  public static let labelVibrantPrimary = labelVibrantPrimaryDark
  public static let accentBrown = accentBrownDark
  public static let fillSecondary = fillSecondaryDark
  public static let separatorNonOpaque = separatorNonOpaqueDark
  public static let separatorOpaque = separatorOpaqueDark
  public static let gray2 = gray2Dark
  public static let toggleAXLabelOff = toggleAXLabelOffDark
  public static let glyphPrimary = glyphPrimaryDark
  public static let glyphSecondary = glyphSecondaryDary
}
