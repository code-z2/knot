import SwiftUI

struct TransactionConfirmationSheet: View {
    let model: TransactionConfirmationModel

    @State private var contentHeight: CGFloat = 0

    var body: some View {
        AppSheet(kind: .height(sheetHeight)) {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                VStack(spacing: AppSpacing.sm) {
                    Text(model.title)
                        .font(AppTypography.heading)
                        .foregroundStyle(AppThemeColor.labelSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.top, AppSpacing.lg)

                    if let assetChange = model.assetChange {
                        VStack(spacing: AppSpacing.xs) {
                            Text(assetChange.fiatAmount)
                                .font(AppTypography.monoBold)
                                .foregroundStyle(AppThemeColor.labelPrimary)

                            Text(assetChange.amount)
                                .font(AppTypography.captionMedium)
                                .foregroundStyle(AppThemeColor.labelSecondary)
                        }
                        .padding(.top, AppSpacing.xs)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.bottom, AppSpacing.sm)

                if let warning = model.warning {
                    Text(warning)
                        .font(AppTypography.bodySmall)
                        .foregroundStyle(AppThemeColor.accentRed)
                }

                VStack(alignment: .leading, spacing: AppSpacing.md) {
                    ForEach(model.details) { detail in
                        VStack(alignment: .leading, spacing: AppSpacing.xs) {
                            Text(detail.label)
                                .font(AppTypography.monoRegularSmall)
                                .foregroundStyle(AppThemeColor.labelSecondary)

                            switch detail.value {
                            case let .text(string):
                                Text(string)
                                    .font(AppTypography.monoMedium)
                                    .foregroundStyle(AppThemeColor.labelPrimary)
                            case let .badge(text, icon):
                                if let icon {
                                    AppIconTextBadge(text: text, icon: icon)
                                } else {
                                    AppTextBadge(text: text)
                                }
                            }
                        }
                    }
                }

                if !model.actions.isEmpty {
                    HStack(spacing: AppSpacing.md) {
                        ForEach(Array(model.actions.enumerated()), id: \.element.id) { index, action in
                            AppButton(
                                fullWidth: true,
                                label: action.label,
                                variant: effectiveVariant(for: action),
                                visualState: action.visualState,
                                showIcon: true,
                                iconSize: 16,
                                action: action.handler,
                            )
                            .disabled(action.visualState == .loading ? false : !action.isEnabled)

                            if index < model.actions.count - 1 {
                                DashedLine()
                                    .stroke(style: StrokeStyle(lineWidth: 2, dash: [4, 4]))
                                    .frame(width: 24, height: 2)
                                    .foregroundColor(AppThemeColor.separatorOpaque)
                            }
                        }
                    }
                    .padding(.top, AppSpacing.lg)
                }
            }
            .padding(.horizontal, AppSpacing.lg)
            .padding(.bottom, AppSpacing.lg)
            .frame(maxHeight: .infinity, alignment: .top)
            .background(
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: TransactionConfirmationSheetHeightKey.self,
                        value: proxy.size.height,
                    )
                },
            )
            .onPreferenceChange(TransactionConfirmationSheetHeightKey.self) { value in
                contentHeight = value
            }
        }
    }

    private var sheetHeight: CGFloat {
        476
    }

    private func effectiveVariant(
        for action: TransactionConfirmationActionModel,
    ) -> AppButtonVariant {
        switch action.visualState {
        case .loading:
            .neutral
        case .error:
            .destructive
        case .success:
            .success
        case .normal:
            action.isEnabled ? action.variant : .neutral
        }
    }
}

private struct TransactionConfirmationSheetHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct DashedLine: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 0, y: rect.height / 2))
        path.addLine(to: CGPoint(x: rect.width, y: rect.height / 2))
        return path
    }
}

#Preview("ENS Confirmation") {
    let confirmationBuilder = TransactionConfirmationBuilder()
    let details = confirmationBuilder.ensDetails(
        typeText: "ENS - Name Registration",
        feeText: "~$1.24",
        chainName: "Ethereum",
        chainAssetName: "ethereum",
    )
    let actionId = UUID()

    TransactionConfirmationSheet(
        model: TransactionConfirmationModel(
            title: "confirm_title",
            details: details,
            actions: [
                TransactionConfirmationActionModel(
                    id: actionId,
                    label: "ens_confirm_commit",
                    variant: .default,
                ) {},
                TransactionConfirmationActionModel(
                    label: "ens_confirm_register",
                    variant: .neutral,
                    isEnabled: false,
                ) {},
            ],
        ),
    )
}
