import SwiftUI

public enum AppTypography {
  // Onboarding
  public static let onboardingTitle = Font.custom("Roboto-Bold", size: 40)
  public static let onboardingBody = Font.custom("Roboto-Medium", size: 15)

  // Buttons
  public static let button = Font.custom("Roboto-Bold", size: 15)

  // Body & UI
  public static let bodyMedium = Font.custom("Roboto-Medium", size: 15)
  public static let bodyRegular = Font.custom("Roboto-Regular", size: 15)
  public static let bodySmall = Font.custom("Roboto-Regular", size: 12)
  public static let captionMedium = Font.custom("Roboto-Medium", size: 12)
  public static let captionBold = Font.custom("Roboto-Bold", size: 14)

  // Mono (amounts, codes)
  public static let monoMedium = Font.custom("RobotoMono-Medium", size: 14)
  public static let monoSmall = Font.custom("RobotoMono-Medium", size: 12)
  public static let monoBold = Font.custom("RobotoMono-Bold", size: 20)
  public static let monoBalanceLarge = Font.custom("RobotoMono-Bold", size: 24)
  public static let monoRegularSmall = Font.custom("RobotoMono-Regular", size: 12)

  // Headings
  public static let heading = Font.custom("Roboto-Bold", size: 22)
  public static let headingMedium = Font.custom("Roboto-Bold", size: 16)
  public static let sectionHeader = Font.custom("RobotoMono-Medium", size: 14)
  public static let listTitle = Font.custom("Roboto-Bold", size: 15)
  public static let homeTitle = Font.custom("Roboto-Medium", size: 24)
  public static let condensedMedium = Font.custom("RobotoCondensed-Medium", size: 14)
}
