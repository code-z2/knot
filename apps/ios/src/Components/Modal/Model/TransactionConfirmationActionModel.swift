//
//  TransactionConfirmationActionModel.swift
//  Created by Peter Anyaogu on 24/02/2026.
//

import SwiftUI

struct TransactionConfirmationActionModel: Identifiable {
    let id: UUID

    let label: LocalizedStringKey

    let icon: String?

    let variant: AppButtonVariant

    let visualState: AppButtonVisualState

    let isEnabled: Bool

    let handler: () -> Void

    init(
        id: UUID = UUID(),
        label: LocalizedStringKey,
        icon: String? = nil,
        variant: AppButtonVariant = .default,
        visualState: AppButtonVisualState = .normal,
        isEnabled: Bool = true,
        handler: @escaping () -> Void,
    ) {
        self.id = id
        self.label = label
        self.icon = icon
        self.variant = variant
        self.visualState = visualState
        self.isEnabled = isEnabled
        self.handler = handler
    }
}
