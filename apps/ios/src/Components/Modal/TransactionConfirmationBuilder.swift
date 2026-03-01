//
//  TransactionConfirmationBuilder.swift
//  Created by Peter Anyaogu on 24/02/2026.
//

import SwiftUI

struct TransactionConfirmationBuilder {
    func transferDetails(
        recipientDisplay: String,
        feeText: String,
        chainName: String,
        chainAssetName: String,
        typeText: String,
    ) -> [TransactionConfirmationDetailModel] {
        baseDetails(
            recipientDisplay: recipientDisplay,
            recipientIcon: .symbol("arrow.up.right"),
            typeText: typeText,
            feeText: feeText,
            chainName: chainName,
            chainAssetName: chainAssetName,
        )
    }

    func ensDetails(
        typeText: String,
        feeText: String,
        chainName: String,
        chainAssetName: String,
    ) -> [TransactionConfirmationDetailModel] {
        baseDetails(
            recipientDisplay: "ETHRegistrarController",
            recipientIcon: .symbol("wallet.pass"),
            typeText: typeText,
            feeText: feeText,
            chainName: chainName,
            chainAssetName: chainAssetName,
        )
    }

    private func baseDetails(
        recipientDisplay: String,
        recipientIcon: AppBadgeIcon?,
        typeText: String,
        feeText: String,
        chainName: String,
        chainAssetName: String,
    ) -> [TransactionConfirmationDetailModel] {
        [
            TransactionConfirmationDetailModel(
                label: "transaction_label_to",
                value: .badge(text: recipientDisplay, icon: recipientIcon),
            ),
            TransactionConfirmationDetailModel(
                label: "transaction_receipt_type",
                value: .text(typeText),
            ),
            TransactionConfirmationDetailModel(
                label: "transaction_receipt_fee",
                value: .text(feeText),
            ),
            TransactionConfirmationDetailModel(
                label: "transaction_receipt_network",
                value: .badge(text: chainName, icon: .network(chainAssetName)),
            ),
        ]
    }
}
