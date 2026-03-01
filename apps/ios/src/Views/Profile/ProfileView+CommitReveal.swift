// ProfileView+CommitReveal.swift
// Created by Peter Anyaogu on 26/02/2026.

import RPC
import SwiftUI

extension ProfileView {
    @MainActor
    func resumePendingCommitRevealIfNeeded() async {
        guard pendingConfirmation == nil else { return }
        guard let pendingJob = commitRevealStore.loadJob(for: eoaAddress) else { return }

        if isNameLocked || pendingJob.postCommitCalls.isEmpty {
            commitRevealStore.clearJob(for: eoaAddress)
            return
        }

        pendingProfilePayloads = nil
        pendingENSRevealJob = pendingJob
        preparedPayloads = pendingJob.preparedPayloadCount

        let feeText: String
        let hasSufficientEth: Bool
        do {
            let feeETH = try await estimateFeeETH()
            feeText = await formatFee(feeETH: feeETH)
            hasSufficientEth = hasSufficientEthBalance(for: feeETH)
        } catch {
            feeText = "unknown"
            hasSufficientEth = true
        }

        let warning: LocalizedStringKey? = hasSufficientEth ? nil : "send_money_insufficient_balance"

        let chainDefinition = ChainRegistry.resolve(chainID: pendingJob.chainId)
        let chainName = chainDefinition?.name ?? String(localized: "transaction_chain_unknown")
        let chainAssetName = chainDefinition?.assetName ?? chainName

        let actionIDs = ENSConfirmationActionIDs(commit: UUID(), register: UUID())
        ensConfirmationActionIDs = actionIDs

        let details = makeEnsDetails(
            typeText: String(localized: "transaction_type_ens_register"),
            feeText: feeText,
            chainName: chainName,
            chainAssetName: chainAssetName,
        )

        pendingConfirmation = TransactionConfirmationModel(
            title: "confirm_title",
            warning: warning,
            details: details,
            actions: [
                TransactionConfirmationActionModel(
                    id: actionIDs.commit,
                    label: "ens_confirm_commit",
                    variant: .default,
                    visualState: .success,
                    isEnabled: hasSufficientEth,
                ) {},
                TransactionConfirmationActionModel(
                    id: actionIDs.register,
                    label: "ens_confirm_register",
                    variant: .default,
                    visualState: .normal,
                    isEnabled: false,
                ) {
                    confirmRegisterAction()
                },
            ],
        )

        await prepareRevealWindow(for: pendingJob)
    }
}
