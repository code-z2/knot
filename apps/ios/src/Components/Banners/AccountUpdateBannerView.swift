import SwiftUI

struct AccountUpdateBannerView: View {
    @Binding var phase: UpdateBannerPhase

    let version: String
    let releaseNotes: String?
    let onUpdateTap: () -> Void

    @State private var isVisible = false

    private let bannerHeight: CGFloat = 42

    var body: some View {
        if phase != .hidden {
            Group {
                switch phase {
                case .hidden:
                    EmptyView()
                case .available:
                    availableBanner
                case .inProgress:
                    inProgressBanner
                case .complete:
                    completeBanner
                }
            }
            .transition(.move(edge: .top).combined(with: .opacity))
            .onAppear {
                withAnimation(.spring(response: 0.45, dampingFraction: 0.78)) {
                    isVisible = true
                }
            }
        }
    }

    // MARK: - Available

    private var availableBanner: some View {
        Button(action: onUpdateTap) {
            HStack(spacing: AppSpacing.xs) {
                Image(systemName: "sparkles")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.yellow)

                Text(String(format: String(localized: "account_update_available_format"), version))
                    .font(.custom("RobotoMono-Medium", size: 11))
                    .lineLimit(1)

                Spacer()

                Text("account_update_tap_to_update")
                    .font(.custom("RobotoMono-Bold", size: 11))
                    .padding(.horizontal, AppSpacing.xs)
                    .padding(.vertical, AppSpacing.xxs)
                    .glassEffect(.clear)
            }
            .foregroundStyle(AppThemeColor.labelPrimary)
            .padding(.horizontal, AppSpacing.md)
            .frame(height: bannerHeight)
            .background(AppThemeColor.accentBrown)
        }
        .buttonStyle(.plain)
        .transition(
            .asymmetric(
                insertion: .move(edge: .top).combined(with: .opacity),
                removal: .scale(scale: 0.92).combined(with: .opacity),
            ),
        )
    }

    // MARK: - In Progress

    private var inProgressBanner: some View {
        HStack(spacing: AppSpacing.xs) {
            ProgressView()
                .tint(AppThemeColor.labelPrimary)
                .scaleEffect(0.7)

            Text("account_update_in_progress")
                .font(.custom("RobotoMono-Medium", size: 11))
                .foregroundStyle(AppThemeColor.labelPrimary)
        }
        .padding(.horizontal, AppSpacing.lg)
        .frame(height: bannerHeight)
        .background(
            Capsule()
                .fill(AppThemeColor.accentBrown),
        )
        .frame(maxWidth: .infinity)
        .transition(.scale(scale: 0.92).combined(with: .opacity))
    }

    // MARK: - Complete

    private var completeBanner: some View {
        HStack(spacing: AppSpacing.xs) {
            Image(systemName: "sparkles")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.yellow)

            Text(String(format: String(localized: "account_update_complete_format"), version))
                .font(.custom("RobotoMono-Medium", size: 11))

            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 13, weight: .medium))
        }
        .foregroundStyle(AppThemeColor.labelPrimary)
        .padding(.horizontal, AppSpacing.md)
        .frame(height: bannerHeight)
        .background(AppThemeColor.accentGreen)
        .transition(
            .asymmetric(
                insertion: .scale(scale: 0.92).combined(with: .opacity),
                removal: .move(edge: .bottom).combined(with: .opacity),
            ),
        )
    }
}

enum UpdateBannerPhase: Equatable {
    case hidden
    case available
    case inProgress
    case complete
}

#Preview("Available") {
    VStack {
        Spacer()
        AccountUpdateBannerView(
            phase: .constant(.available),
            version: "1.2.0",
            releaseNotes: "Bug fixes and performance improvements",
            onUpdateTap: {},
        )
        Spacer()
    }
    .background(AppThemeColor.backgroundPrimary)
}

#Preview("In Progress") {
    VStack {
        Spacer()
        AccountUpdateBannerView(
            phase: .constant(.inProgress),
            version: "1.2.0",
            releaseNotes: nil,
            onUpdateTap: {},
        )
        Spacer()
    }
    .background(AppThemeColor.backgroundPrimary)
}

#Preview("Complete") {
    VStack {
        Spacer()
        AccountUpdateBannerView(
            phase: .constant(.complete),
            version: "1.2.0",
            releaseNotes: nil,
            onUpdateTap: {},
        )
        Spacer()
    }
    .background(AppThemeColor.backgroundPrimary)
}
