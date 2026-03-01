import Foundation
import RPC
import SwiftUI

struct ENSConfirmationActionIDs {
    let commit: UUID
    let register: UUID
}

extension ProfileView {
    func makeEnsDetails(
        typeText: String,
        feeText: String,
        chainName: String,
        chainAssetName: String,
    ) -> [TransactionConfirmationDetailModel] {
        let confirmationBuilder = TransactionConfirmationBuilder()
        return confirmationBuilder.ensDetails(
            typeText: typeText,
            feeText: feeText,
            chainName: chainName,
            chainAssetName: chainAssetName,
        )
    }

    func prepareRevealWindow(for pendingJob: PendingENSRevealJob) async {
        cancelRevealTimers()
        revealWindowTask = Task { @MainActor in
            do {
                let revealNotBefore: Date = if pendingJob.revealNotBeforeUnix > 0 {
                    Date(timeIntervalSince1970: pendingJob.revealNotBeforeUnix)
                } else {
                    try await waitForRevealWindowStart(for: pendingJob)
                }

                let updatedJob = PendingENSRevealJob(
                    eoaAddress: pendingJob.eoaAddress,
                    name: pendingJob.name,
                    chainId: pendingJob.chainId,
                    submissionHash: pendingJob.submissionHash,
                    minCommitmentAgeSeconds: pendingJob.minCommitmentAgeSeconds,
                    revealNotBeforeUnix: revealNotBefore.timeIntervalSince1970,
                    postCommitCalls: pendingJob.postCommitCalls,
                    preparedPayloadCount: pendingJob.preparedPayloadCount,
                )
                pendingENSRevealJob = updatedJob
                commitRevealStore.saveJob(updatedJob)
                startRevealCountdown(until: revealNotBefore)
            } catch {
                print("[ProfileView] ENS reveal window failed: \(error.localizedDescription)")
            }
        }
    }

    func cancelRevealTimers() {
        revealWindowTask?.cancel()
        revealWindowTask = nil
        cancelRevealCountdownOnly()
    }

    func waitForRevealWindowStart(for job: PendingENSRevealJob) async throws -> Date {
        let commitIncludedAt = try await aaExecutionService.waitForRelayInclusion(
            chainId: job.chainId,
            relayTaskID: job.submissionHash,
        )
        return commitIncludedAt.addingTimeInterval(TimeInterval(job.minCommitmentAgeSeconds))
    }

    func estimateFormattedFee() async throws -> String {
        await currencyRateStore.ensureRate(for: "ETH")
        let feeETH = try await aaExecutionService.estimateExecutionFee(
            chainId: ensService.chainID,
        )
        let feeUSD = currencyRateStore.convertSelectedToUSD(feeETH, currencyCode: "ETH")
        let feeFiat = currencyRateStore.convertUSDToSelected(
            feeUSD, currencyCode: preferencesStore.selectedCurrencyCode,
        )

        if feeFiat < 0.01 {
            let sym = currencyRateStore.symbol(
                for: preferencesStore.selectedCurrencyCode, locale: preferencesStore.locale,
            )
            return "<\(sym)0.01"
        }

        return currencyRateStore.formatUSD(
            feeUSD,
            currencyCode: preferencesStore.selectedCurrencyCode,
            locale: preferencesStore.locale,
        )
    }

    private func startRevealCountdown(until revealNotBefore: Date) {
        cancelRevealCountdownOnly()
        revealCountdownTask = Task { @MainActor in
            while true {
                let seconds = max(0, Int(ceil(revealNotBefore.timeIntervalSinceNow)))
                revealCountdownSeconds = seconds

                if seconds == 0 {
                    revealCountdownSeconds = nil
                    updatePendingConfirmationConnectorText(nil)
                    if let actionIDs = ensConfirmationActionIDs {
                        updatePendingConfirmationActions(
                            actionId: actionIDs.commit,
                            visualState: .normal,
                            isEnabled: false,
                            disableOthers: false,
                        )
                        updatePendingConfirmationActions(
                            actionId: actionIDs.register,
                            visualState: .normal,
                            isEnabled: true,
                            disableOthers: false,
                        )
                    }
                    break
                } else {
                    updatePendingConfirmationConnectorText(formatCountdown(seconds: seconds))
                }

                do {
                    try await Task.sleep(for: .seconds(1))
                } catch {
                    return
                }
            }
        }
    }

    private func formatCountdown(seconds: Int) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.second]
        formatter.unitsStyle = .abbreviated
        formatter.zeroFormattingBehavior = [.dropLeading]
        return formatter.string(from: TimeInterval(seconds)) ?? "\(seconds)s"
    }

    private func updatePendingConfirmationConnectorText(_ text: String?) {
        guard let model = pendingConfirmation else { return }
        pendingConfirmation = model.withActionConnectorText(text)
    }

    private func cancelRevealCountdownOnly() {
        revealCountdownTask?.cancel()
        revealCountdownTask = nil
    }
}
