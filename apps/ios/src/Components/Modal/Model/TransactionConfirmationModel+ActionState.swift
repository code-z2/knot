import SwiftUI

extension TransactionConfirmationModel {
    func updatingAction(
        id: UUID,
        visualState: AppButtonVisualState,
        isEnabled: Bool,
        disableOthers: Bool,
    ) -> TransactionConfirmationModel {
        let updatedActions = actions.map { action in
            if action.id == id {
                return action.copying(visualState: visualState, isEnabled: isEnabled)
            }
            return action.copying(isEnabled: disableOthers ? false : action.isEnabled)
        }

        return withActions(updatedActions)
    }

    func resettingAction(id: UUID, isEnabled: Bool) -> TransactionConfirmationModel {
        updatingAction(
            id: id,
            visualState: .normal,
            isEnabled: isEnabled,
            disableOthers: false,
        )
    }
}
