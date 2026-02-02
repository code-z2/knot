import SwiftUI

enum AppThemeColor {
    // Core surfaces
    static let backgroundPrimaryDark = Color(hex: "#000000")
    static let backgroundPrimaryLight = Color(hex: "#FFFFFF")

    static let labelPrimaryDark = Color(hex: "#FFFFFF")
    static let labelPrimaryLight = Color(hex: "#000000")

    static let labelSecondaryDark = Color(hex: "#EBEBF599")
    static let labelSecondaryLight = Color(hex: "#3C3C4399")

    static let labelVibrantPrimaryDark = Color(hex: "#FFFFFF")
    static let labelVibrantPrimaryLight = Color(hex: "#333333")
    static let labelVibrantSecondary = Color(hex: "#999999")

    // Brand + semantic
    static let accentBrownDark = Color(hex: "#B78A66")
    static let accentBrownLight = Color(hex: "#AC7F5E")

    static let accentRed = Color(hex: "#FF4245")
    static let accentGreen = Color(hex: "#30D158")
    static let destructiveBackground = Color(hex: "#FF424524")

    // UI primitives
    static let fillPrimary = Color(hex: "#7878805C")
    static let fillSecondaryDark = Color(hex: "#78788052")
    static let fillSecondaryLight = Color(hex: "#78788029")
    static let fillTertiary = Color(hex: "#7676803D")

    static let separatorNonOpaqueDark = Color(hex: "#FFFFFF2B")
    static let separatorNonOpaqueLight = Color(hex: "#0000001F")

    static let separatorOpaqueDark = Color(hex: "#38383A")
    static let separatorOpaqueLight = Color(hex: "#C6C6C8")

    static let gray2Dark = Color(hex: "#636366")
    static let gray2Light = Color(hex: "#AEAEB2")

    static let toggleAXLabelOffDark = Color(hex: "#A6A6A6")
    static let toggleAXLabelOffLight = Color(hex: "#B3B3B3")

    static let grayBlack = Color(hex: "#000000")
    static let grayWhite = Color(hex: "#FFFFFF")
    static let offWhite = Color(hex: "#FFFDFD")

    // Fixed-dark screens (AI + onboarding in both modes)
    static let fixedDarkSurface = Color(hex: "#000000")
    static let fixedDarkText = Color(hex: "#FFFFFF")
    static let onboardingProgressActive = offWhite

    // Dark-first app defaults
    static let backgroundPrimary = backgroundPrimaryDark
    static let labelPrimary = labelPrimaryDark
    static let labelSecondary = labelSecondaryDark
    static let labelVibrantPrimary = labelVibrantPrimaryDark
    static let accentBrown = accentBrownDark
    static let fillSecondary = fillSecondaryDark
    static let separatorNonOpaque = separatorNonOpaqueDark
    static let separatorOpaque = separatorOpaqueDark
    static let gray2 = gray2Dark
    static let toggleAXLabelOff = toggleAXLabelOffDark
}
