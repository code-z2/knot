import SwiftUI

extension ProfileView {
    @MainActor
    func resumePendingCommitRevealIfNeeded() async {
        guard let pendingJob = commitRevealStore.loadJob(for: eoaAddress) else { return }
        saveFlowState = .inProgress

        do {
            showSuccess(String(localized: "profile_commit_submitted_progress"))

            var effectiveJob = pendingJob
            let revealNotBefore: Date
            if pendingJob.revealNotBeforeUnix > 0 {
                revealNotBefore = Date(timeIntervalSince1970: pendingJob.revealNotBeforeUnix)
            } else {
                let computed = try await waitForRevealWindowStart(for: pendingJob)
                revealNotBefore = computed
                effectiveJob = PendingENSRevealJob(
                    eoaAddress: pendingJob.eoaAddress,
                    name: pendingJob.name,
                    chainId: pendingJob.chainId,
                    submissionHash: pendingJob.submissionHash,
                    minCommitmentAgeSeconds: pendingJob.minCommitmentAgeSeconds,
                    revealNotBeforeUnix: computed.timeIntervalSince1970,
                    postCommitCalls: pendingJob.postCommitCalls,
                    preparedPayloadCount: pendingJob.preparedPayloadCount,
                )
                commitRevealStore.saveJob(effectiveJob)
            }

            let delay = max(0, revealNotBefore.timeIntervalSinceNow)
            if delay > 0 {
                try await Task.sleep(for: .seconds(delay))
            }

            let sessionAccount = try await accountService.restoreSession(eoaAddress: eoaAddress)
            if !effectiveJob.postCommitCalls.isEmpty {
                _ = try await aaExecutionService.executeCalls(
                    accountService: accountService,
                    account: sessionAccount,
                    chainId: effectiveJob.chainId,
                    calls: effectiveJob.postCommitCalls,
                )
            }

            isNameLocked = true
            commitRevealStore.clearJob(for: eoaAddress)
            let message = String.localizedStringWithFormat(
                NSLocalizedString("profile_saved_changes", comment: ""),
                effectiveJob.preparedPayloadCount,
            )
            showSuccess(message)
            saveFlowState = .succeeded
        } catch {
            saveFlowState = .failed(error.localizedDescription)
            showError(error)
        }
    }

    func waitForRevealWindowStart(for job: PendingENSRevealJob) async throws -> Date {
        let commitIncludedAt = try await aaExecutionService.waitForRelayInclusion(
            chainId: job.chainId,
            relayTaskID: job.submissionHash,
        )
        return commitIncludedAt.addingTimeInterval(TimeInterval(job.minCommitmentAgeSeconds))
    }
}
