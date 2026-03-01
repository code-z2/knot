// ProfileSuccessView.swift
// Created by Peter Anyaogu on 26/02/2026.

import SwiftUI

struct ProfileSuccessView: View {
    let detailText: String?
    let onViewTransaction: () -> Void

    var body: some View {
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

                        if let detailText {
                            Text(detailText)
                                .font(.custom("Roboto-Regular", size: 20))
                                .foregroundStyle(AppThemeColor.labelPrimary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, AppSpacing.lg)
                        }
                    }
                }

                AppButton(label: "send_money_view_tx", variant: .outline) {
                    onViewTransaction()
                }
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 38)
    }
}

#Preview {
    NavigationStack {
        ProfileSuccessView(
            detailText: "knot.eth registered and profile updated.",
            onViewTransaction: {},
        )
        .appNavigation(
            titleKey: "",
            displayMode: .inline,
            hidesBackButton: false,
        )
    }
}
