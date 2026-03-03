// PreferencesView+Actions.swift
// Created by Peter Anyaogu on 03/03/2026.

import SwiftUI

extension PreferencesView {
    @ViewBuilder
    func modalContent(for modal: PreferencesModalModel) -> some View {
        switch modal {
        case .appearance:
            AppearancePickerModal(
                selectedAppearance: preferencesStore.appearance,
                onSelect: { appearance in
                    preferencesStore.selectAppearance(appearance)
                    dismissModal()
                },
            )
        }
    }

    func present(_ modal: PreferencesModalModel) {
        activeModal = modal
    }

    func dismissModal() {
        activeModal = nil
    }
}
