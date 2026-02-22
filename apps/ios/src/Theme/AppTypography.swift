import SwiftUI

public enum AppTypography {
    // Onboarding
    public static let onboardingTitle = Font.custom("Roboto-Bold", size: 40, relativeTo: .largeTitle)
    public static let onboardingBody = Font.custom("Roboto-Medium", size: 15, relativeTo: .body)

    /// Buttons
    public static let button = Font.custom("Roboto-Bold", size: 15, relativeTo: .headline)

    // Body & UI
    public static let bodyMedium = Font.custom("Roboto-Medium", size: 15, relativeTo: .body)
    public static let bodyRegular = Font.custom("Roboto-Regular", size: 15, relativeTo: .body)
    public static let bodySmall = Font.custom("Roboto-Regular", size: 12, relativeTo: .caption)
    public static let captionMedium = Font.custom("Roboto-Medium", size: 12, relativeTo: .caption)
    public static let captionBold = Font.custom("Roboto-Bold", size: 14, relativeTo: .caption)

    // Mono (amounts, codes)
    public static let monoMedium = Font.custom("RobotoMono-Medium", size: 14, relativeTo: .body)
    public static let monoSmall = Font.custom("RobotoMono-Medium", size: 12, relativeTo: .caption)
    public static let monoBold = Font.custom("RobotoMono-Bold", size: 20, relativeTo: .title3)
    public static let monoBalanceLarge = Font.custom("RobotoMono-Bold", size: 24, relativeTo: .title2)
    public static let monoRegularSmall = Font.custom("RobotoMono-Regular", size: 12, relativeTo: .caption)

    // Headings
    public static let heading = Font.custom("Roboto-Bold", size: 22, relativeTo: .title3)
    public static let headingMedium = Font.custom("Roboto-Bold", size: 16, relativeTo: .headline)
    public static let sectionHeader = Font.custom("RobotoMono-Medium", size: 14, relativeTo: .subheadline)
    public static let listTitle = Font.custom("Roboto-Bold", size: 15, relativeTo: .headline)
    public static let homeTitle = Font.custom("Roboto-Medium", size: 24, relativeTo: .title2)
    public static let condensedMedium = Font.custom("RobotoCondensed-Medium", size: 14, relativeTo: .subheadline)
}
