import SwiftUI

extension PreferencesView {
    @ViewBuilder
    func modalContent(for modal: PreferencesModalModel) -> some View {
        switch modal {
        case .appearance:
            AppearancePickerModal(
                selectedAppearance: preferencesStore.appearance,
                onSelect: { appearance in
                    preferencesStore.appearance = appearance
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
