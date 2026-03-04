//
//  SendMoneySuccessView.swift
//  Created by Peter Anyaogu on 24/02/2026.
//

import SwiftUI

struct SendMoneySuccessView: View {
    let successStatusDetailText: String?

    let onRepeatTransfer: () -> Void

    let onViewTransaction: () -> Void

    var body: some View {
        ZStack {
            AppBackgroundView()

            VStack(spacing: 0) {
                Spacer(minLength: 120)

                VStack(spacing: 56) {
                    VStack(spacing: 48) {
                        SuccessCheckmark()
                            .frame(width: 127, height: 123)

                        VStack(spacing: AppSpacing.xl) {
                            Text("send_money_success_title")
                                .font(.custom("Roboto-Medium", size: 34))
                                .foregroundStyle(AppThemeColor.labelPrimary)
                                .multilineTextAlignment(.center)

                            Text("send_money_success_subtitle")
                                .font(.custom("Roboto-Regular", size: 20))
                                .foregroundStyle(AppThemeColor.labelPrimary)
                                .multilineTextAlignment(.center)

                            if let successStatusDetailText {
                                Text(successStatusDetailText)
                                    .font(.custom("Roboto-Regular", size: 14))
                                    .foregroundStyle(AppThemeColor.labelSecondary)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, AppSpacing.lg)
                            }
                        }
                    }

                    HStack(spacing: AppSpacing.sm) {
                        AppButton(label: "send_money_repeat_transfer", variant: .outline) {
                            onRepeatTransfer()
                        }

                        AppButton(label: "send_money_view_tx", variant: .outline) {
                            onViewTransaction()
                        }
                    }
                }

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 38)
        }
    }
}

#Preview {
    NavigationStack {
        SendMoneySuccessView(
            successStatusDetailText: "Confirmed on Base",
            onRepeatTransfer: {},
            onViewTransaction: {},
        )
        .appNavigation(
            titleKey: "",
            displayMode: .inline,
            hidesBackButton: false,
        )
    }
}
