import SwiftUI

struct GasTankUsageSegment: Identifiable {
    let id: String
    let titleKey: LocalizedStringKey
    let value: Double
    let color: Color

    var percentageLabel: String {
        let percent = Int((value * 100).rounded())
        return "\(percent)%"
    }
}

struct GasTankUsageBarView: View {
    let segments: [GasTankUsageSegment]
    let isDimmed: Bool

    @State private var animateSegments = false

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(AppThemeColor.fillSecondary)
                        .frame(height: 8)

                    HStack(spacing: 0) {
                        ForEach(segments) { segment in
                            Rectangle()
                                .fill(segment.color)
                                .frame(width: segmentWidth(for: segment, totalWidth: proxy.size.width))
                        }
                    }
                    .clipShape(Capsule())
                    .opacity(isDimmed ? 0.4 : 1)
                }
            }
            .frame(height: 8)

            HStack(spacing: AppSpacing.sm) {
                ForEach(segments) { segment in
                    HStack(spacing: AppSpacing.xxs) {
                        Circle()
                            .fill(segment.color)
                            .frame(width: 8, height: 8)

                        Text(segment.titleKey)
                            .font(AppTypography.bodySmall)
                            .foregroundStyle(AppThemeColor.labelSecondary)

                        Text(segment.percentageLabel)
                            .font(AppTypography.bodySmall)
                            .foregroundStyle(AppThemeColor.labelSecondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .opacity(isDimmed ? 0.5 : 1)
        }
        .task {
            guard !animateSegments else { return }
            animateSegments = true
        }
        .animation(.spring(response: 0.5, dampingFraction: 0.86), value: animateSegments)
        .animation(
            .spring(response: 0.5, dampingFraction: 0.86),
            value: segments.map(\.value)
        )
    }

    private func segmentWidth(
        for segment: GasTankUsageSegment,
        totalWidth: CGFloat,
    ) -> CGFloat {
        guard animateSegments else { return 0 }
        return max(0, totalWidth * segment.value)
    }
}
