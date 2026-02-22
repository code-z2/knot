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

    func handleBack() {
        if activePage == .main {
            onBack()
        } else {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                activePage = .main
            }
        }
    }

    func dismissModal() {
        activeModal = nil
    }
}
