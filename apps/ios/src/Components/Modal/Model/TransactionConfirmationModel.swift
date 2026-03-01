//
//  TransactionConfirmationModel.swift
//  Created by Peter Anyaogu on 24/02/2026.
//

import SwiftUI

struct TransactionConfirmationModel: Identifiable {
    let id: UUID

    let title: LocalizedStringKey

    let assetChange: TransactionConfirmationAssetChangeModel?

    let warning: LocalizedStringKey?

    let details: [TransactionConfirmationDetailModel]

    let actions: [TransactionConfirmationActionModel]

    let actionConnectorText: String?

    init(
        id: UUID = UUID(),
        title: LocalizedStringKey,
        assetChange: TransactionConfirmationAssetChangeModel? = nil,
        warning: LocalizedStringKey? = nil,
        details: [TransactionConfirmationDetailModel],
        actions: [TransactionConfirmationActionModel],
        actionConnectorText: String? = nil,
    ) {
        self.id = id
        self.title = title
        self.assetChange = assetChange
        self.warning = warning
        self.details = details
        self.actions = actions
        self.actionConnectorText = actionConnectorText
    }

    func withActions(_ actions: [TransactionConfirmationActionModel]) -> TransactionConfirmationModel {
        TransactionConfirmationModel(
            id: id,
            title: title,
            assetChange: assetChange,
            warning: warning,
            details: details,
            actions: actions,
            actionConnectorText: actionConnectorText,
        )
    }

    func withActionConnectorText(_ actionConnectorText: String?) -> TransactionConfirmationModel {
        TransactionConfirmationModel(
            id: id,
            title: title,
            assetChange: assetChange,
            warning: warning,
            details: details,
            actions: actions,
            actionConnectorText: actionConnectorText,
        )
    }
}
