import ENS
import SwiftUI
import Transactions

extension ProfileView {
    @MainActor
    func loadProfile() async {
        do {
            let resolvedName = try await ensService.reverseAddress(address: eoaAddress)
            let normalizedName = normalizeENSLabel(resolvedName)
            if !normalizedName.isEmpty {
                ensName = normalizedName
                isNameLocked = true
                nameInfoText = nil
                lastQuotedName = normalizedName

                let fullName = "\(normalizedName).eth"

                if let avatarRecord = try? await ensService.textRecord(
                    name: fullName,
                    key: "avatar",
                ) {
                    avatarURL = avatarRecord.trimmingCharacters(in: .whitespacesAndNewlines)
                }

                if let descriptionRecord = try? await ensService.textRecord(
                    name: fullName,
                    key: "description",
                ) {
                    bio = descriptionRecord
                }
            }
        } catch {
            isNameLocked = false
            nameInfoText = nil
        }

        initialENSName = ensName
        initialAvatarURL = avatarURL
        initialBio = bio
    }

    @MainActor
    func scheduleQuoteLookup(for input: String) {
        quoteTask?.cancel()

        let normalized = normalizeENSLabel(input)
        guard !normalized.isEmpty else {
            isCheckingName = false
            nameInfoText = nil
            nameInfoTone = .info
            lastQuotedName = ""
            return
        }
        guard normalized != lastQuotedName else { return }

        let quoteWorker = quoteWorker
        quoteTask = Task(priority: .utility) { [normalized] in
            do {
                try await Task.sleep(for: .milliseconds(420))
                try Task.checkCancellation()

                let shouldContinue =
                    !isNameLocked
                        && normalizeENSLabel(ensName) == normalized
                guard shouldContinue else { return }

                isCheckingName = true
                defer {
                    if self.normalizeENSLabel(self.ensName) == normalized {
                        self.isCheckingName = false
                    }
                }

                let quote = try await quoteWorker.quote(name: normalized)
                try Task.checkCancellation()

                guard !isNameLocked else { return }
                guard normalizeENSLabel(ensName) == normalized else { return }

                lastQuotedName = quote.normalizedName
                ensName = quote.normalizedName

                if quote.available {
                    let eth = TokenFormatters.weiToEthString(quote.rentPriceWei)
                    nameInfoText = String.localizedStringWithFormat(
                        NSLocalizedString("profile_name_available_for_price", comment: ""),
                        quote.normalizedName,
                        eth,
                    )
                    nameInfoTone = .success
                } else {
                    nameInfoText = String(localized: "profile_name_unavailable")
                    nameInfoTone = .error
                }
            } catch is CancellationError {
                return
            } catch {
                guard normalizeENSLabel(ensName) == normalized else { return }
                nameInfoText = error.localizedDescription
                nameInfoTone = .error
                isCheckingName = false
            }
        }
    }

    @MainActor
    func saveProfile() async {
        guard !isSaving else { return }
        isSaving = true
        saveFlowState = .inProgress
        preparedPayloads = 0
        defer { isSaving = false }

        do {
            try await ensureAvatarUploadCompletedIfNeeded()

            let normalizedName = normalizeENSLabel(ensName)
            if normalizedName.isEmpty {
                throw ENSServiceError.actionFailed(
                    NSError(
                        domain: "ENS",
                        code: 3,
                        userInfo: [
                            NSLocalizedDescriptionKey: NSLocalizedString(
                                "profile_error_name_required", comment: "",
                            ),
                        ],
                    ),
                )
            }
            var commitCall: Call?
            var postCommitCalls: [Call] = []
            var minCommitmentAgeSeconds: UInt64 = 60
            let avatar = avatarURL.trimmingCharacters(in: .whitespacesAndNewlines)
            let description = bio.trimmingCharacters(in: .whitespacesAndNewlines)
            var embeddedRecordKeys = Set<String>()

            if !isNameLocked {
                if normalizedName != lastQuotedName || nameInfoTone != .success {
                    throw ENSServiceError.actionFailed(
                        NSError(
                            domain: "ENS",
                            code: 2,
                            userInfo: [
                                NSLocalizedDescriptionKey: NSLocalizedString(
                                    "profile_error_use_available_name", comment: "",
                                ),
                            ],
                        ),
                    )
                }
                var initialRecords: [ENSRecordDraft] = []
                if !avatar.isEmpty, avatar != initialAvatarURL {
                    initialRecords.append(ENSRecordDraft(key: "avatar", value: avatar))
                    embeddedRecordKeys.insert("avatar")
                }
                if !description.isEmpty, description != initialBio {
                    initialRecords.append(ENSRecordDraft(key: "description", value: description))
                    embeddedRecordKeys.insert("description")
                }
                print("⚙️ Requesting ENS registration payloads for \(normalizedName)...")
                let registrationPayloads = try await ensService.registerNamePayloads(
                    name: normalizedName,
                    ownerAddress: eoaAddress,
                    initialRecords: initialRecords,
                )
                print("✅ ENS Registration Payloads generated.")
                print("   - Commit Call Value (Wei): \(registrationPayloads.commitCall.valueWei)")
                print("   - Register Call Value (Wei): \(registrationPayloads.registerCall.valueWei)")
                commitCall = registrationPayloads.commitCall
                postCommitCalls.append(registrationPayloads.registerCall)
                minCommitmentAgeSeconds = max(1, registrationPayloads.minCommitmentAgeSeconds)
                preparedPayloads += registrationPayloads.calls.count
            }

            if avatar != initialAvatarURL, !embeddedRecordKeys.contains("avatar") {
                let avatarPayload = try await ensService.setTextRecordPayload(
                    name: normalizedName,
                    key: "avatar",
                    value: avatar,
                )
                postCommitCalls.append(avatarPayload)
                preparedPayloads += 1
            }

            if description != initialBio, !embeddedRecordKeys.contains("description") {
                let bioPayload = try await ensService.setTextRecordPayload(
                    name: normalizedName,
                    key: "description",
                    value: description,
                )
                postCommitCalls.append(bioPayload)
                preparedPayloads += 1
            }

            guard commitCall != nil || !postCommitCalls.isEmpty else {
                showSuccess(String(localized: "profile_no_changes_to_save"))
                saveFlowState = .succeeded
                return
            }

            let sessionAccount = try await accountService.restoreSession(eoaAddress: eoaAddress)
            if let commitCall {
                print("🚀 Executing ENS Commit Call...")
                let commitSubmissionHash = try await aaExecutionService.executeCalls(
                    accountService: accountService,
                    account: sessionAccount,
                    chainId: ensService.chainID,
                    calls: [commitCall],
                )
                print("✅ ENS Commit Call submitted! Hash: \(commitSubmissionHash)")
                var pendingJob = PendingENSRevealJob(
                    eoaAddress: eoaAddress,
                    name: normalizedName,
                    chainId: ensService.chainID,
                    submissionHash: commitSubmissionHash,
                    minCommitmentAgeSeconds: minCommitmentAgeSeconds,
                    revealNotBeforeUnix: 0,
                    postCommitCalls: postCommitCalls,
                    preparedPayloadCount: preparedPayloads,
                )
                commitRevealStore.saveJob(pendingJob)
                showSuccess(String(localized: "profile_commit_submitted_progress"))

                let revealNotBefore = try await waitForRevealWindowStart(for: pendingJob)
                pendingJob = PendingENSRevealJob(
                    eoaAddress: pendingJob.eoaAddress,
                    name: pendingJob.name,
                    chainId: pendingJob.chainId,
                    submissionHash: pendingJob.submissionHash,
                    minCommitmentAgeSeconds: pendingJob.minCommitmentAgeSeconds,
                    revealNotBeforeUnix: revealNotBefore.timeIntervalSince1970,
                    postCommitCalls: pendingJob.postCommitCalls,
                    preparedPayloadCount: pendingJob.preparedPayloadCount,
                )
                commitRevealStore.saveJob(pendingJob)

                let delay = max(0, revealNotBefore.timeIntervalSinceNow)
                if delay > 0 {
                    try await Task.sleep(for: .seconds(delay))
                }
            }

            if !postCommitCalls.isEmpty {
                print("🚀 Executing \(postCommitCalls.count) Post-Commit (Register/Text) Calls...")
                for (i, call) in postCommitCalls.enumerated() {
                    print("   - Call \(i) Value (Wei): \(call.valueWei)")
                }
                _ = try await aaExecutionService.executeCalls(
                    accountService: accountService,
                    account: sessionAccount,
                    chainId: ensService.chainID,
                    calls: postCommitCalls,
                )
                print("✅ Post-Commit Calls submitted!")
            }

            if commitCall != nil {
                isNameLocked = true
                commitRevealStore.clearJob(for: eoaAddress)
            }

            initialAvatarURL = avatarURL
            initialBio = bio
            initialENSName = ensName
            let message = String.localizedStringWithFormat(
                NSLocalizedString("profile_saved_changes", comment: ""),
                preparedPayloads,
            )
            showSuccess(message)
            saveFlowState = .succeeded
            successTrigger += 1
        } catch {
            errorTrigger += 1
            saveFlowState = .failed(error.localizedDescription)
            showError(error)
        }
    }

    func normalizeENSLabel(_ rawValue: String) -> String {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if trimmed.hasSuffix(".eth") {
            return String(trimmed.dropLast(4))
        }
        return trimmed
    }

    @MainActor
    func cancelEditing() {
        quoteTask?.cancel()
        quoteTask = nil
        avatarUploadTask?.cancel()
        avatarUploadTask = nil
        isUploadingAvatar = false

        ensName = initialENSName
        avatarURL = initialAvatarURL
        bio = initialBio
        localAvatarImage = nil
        pendingAvatarUpload = nil
        selectedPhotoItem = nil

        isCheckingName = false
        nameInfoText = nil
        nameInfoTone = .info
        lastQuotedName = normalizeENSLabel(initialENSName)
        saveFlowState = .idle
    }
}
