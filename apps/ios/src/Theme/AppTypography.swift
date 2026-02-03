import SwiftUI

public enum AppTypography {
    // Matches Figma text styles for splash/onboarding.
    public static let onboardingTitle = Font.custom("Roboto-Bold", size: 40).weight(.bold)
    public static let onboardingBody = Font.custom("Roboto-Medium", size: 15).weight(.medium)
    public static let button = Font.custom("Roboto-Bold", size: 15).weight(.bold)
}
