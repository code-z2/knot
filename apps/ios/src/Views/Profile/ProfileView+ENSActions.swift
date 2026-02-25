import ENS
import RPC
import SwiftUI
import Transactions

struct ProfilePayloadsModel {
    let commit: Call?
    let postCommit: [Call]
    let minAge: UInt64
}

extension ProfileView {
    @MainActor
    func loadProfile() async {
        // Apply cache first for instant display
        if let cached = ensProfileCache.load(for: eoaAddress) {
            initialENSName = cached.name
            initialAvatarURL = cached.avatarURL
            initialBio = cached.bio
            ensName = cached.name
            avatarURL = cached.avatarURL
            bio = cached.bio
            isNameLocked = true
            nameInfoText = nil
            lastQuotedName = cached.name
        }

        do {
            let resolvedName = try await ensService.reverseAddress(address: eoaAddress)
            let normalizedName = ENSService.ensLabel(resolvedName)
            if !normalizedName.isEmpty {
                let fullName = ENSService.canonicalENSName(resolvedName)

                var loadedAvatar = ""
                var loadedBio = ""

                if let avatarRecord = try? await ensService.textRecord(
                    name: fullName,
                    key: "avatar",
                ) {
                    loadedAvatar = avatarRecord.trimmingCharacters(in: .whitespacesAndNewlines)
                }

                if let descriptionRecord = try? await ensService.textRecord(
                    name: fullName,
                    key: "description",
                ) {
                    loadedBio = descriptionRecord
                }

                // Set initial values BEFORE display values to prevent button flash
                initialENSName = normalizedName
                initialAvatarURL = loadedAvatar
                initialBio = loadedBio

                ensName = normalizedName
                isNameLocked = true
                nameInfoText = nil
                lastQuotedName = normalizedName
                avatarURL = loadedAvatar
                bio = loadedBio

                ensProfileCache.save(
                    CachedENSProfileModel(
                        name: normalizedName,
                        avatarURL: loadedAvatar,
                        bio: loadedBio,
                        updatedAt: Date(),
                    ),
                    for: eoaAddress,
                )
                return
            }
        } catch {
            if initialENSName.isEmpty {
                isNameLocked = false
            }
            nameInfoText = nil
        }

        if initialENSName.isEmpty {
            initialENSName = ensName
            initialAvatarURL = avatarURL
            initialBio = bio
        }
    }

    @MainActor
    func scheduleQuoteLookup(for input: String) {
        quoteTask?.cancel()

        let normalized = ENSService.ensLabel(input)
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
                        && ENSService.ensLabel(ensName) == normalized
                guard shouldContinue else { return }

                isCheckingName = true
                defer {
                    if ENSService.ensLabel(self.ensName) == normalized {
                        self.isCheckingName = false
                    }
                }

                let quote = try await quoteWorker.quote(name: normalized)
                try Task.checkCancellation()

                guard !isNameLocked else { return }
                guard ENSService.ensLabel(ensName) == normalized else { return }

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
                guard ENSService.ensLabel(ensName) == normalized else { return }
                nameInfoText = error.localizedDescription
                nameInfoTone = .error
                isCheckingName = false
            }
        }
    }

    func presentSaveConfirmation() {
        guard !isPreparingConfirmation else { return }
        isPreparingConfirmation = true

        Task { @MainActor in
            defer { isPreparingConfirmation = false }
            do {
                let payloads = try await buildProfilePayloads()
                let calls = ensCalls(from: payloads)
                guard !calls.isEmpty else {
                    pendingConfirmation = nil
                    showSuccess(String(localized: "profile_no_changes_to_save"))
                    return
                }

                let feeFormatted = try await estimateFormattedFee()
                let chainDefinition = ChainRegistry.resolve(chainID: ensService.chainID)
                let chainName = chainDefinition?.name
                    ?? String(localized: "transaction_chain_unknown")
                let chainAssetName = chainDefinition?.assetName ?? chainName

                pendingConfirmation = makeEnsConfirmationModel(
                    isRegistering: shouldRegisterEnsName,
                    feeText: feeFormatted,
                    chainName: chainName,
                    chainAssetName: chainAssetName,
                )
            } catch {
                pendingConfirmation = nil
                showError(error)
            }
        }
    }

    private var shouldRegisterEnsName: Bool {
        !isNameLocked && !ENSService.ensLabel(ensName).isEmpty
    }

    private func ensCalls(from payloads: ProfilePayloadsModel) -> [Call] {
        var allCalls = payloads.postCommit
        if let commit = payloads.commit {
            allCalls.insert(commit, at: 0)
        }
        return allCalls
    }

    private func makeEnsConfirmationModel(
        isRegistering: Bool,
        feeText: String,
        chainName: String,
        chainAssetName: String,
    ) -> TransactionConfirmationModel {
        let confirmationBuilder = TransactionConfirmationBuilder()
        let typeKey: String.LocalizationValue =
            isRegistering ? "transaction_type_ens_register" : "transaction_type_ens_update"
        let details = confirmationBuilder.ensDetails(
            typeText: String(localized: typeKey),
            feeText: feeText,
            chainName: chainName,
            chainAssetName: chainAssetName,
        )

        return TransactionConfirmationModel(
            title: "confirm_title",
            details: details,
            actions: ensConfirmationActions(isRegistering: isRegistering),
        )
    }

    private func ensConfirmationActions(
        isRegistering: Bool,
    ) -> [TransactionConfirmationActionModel] {
        if isRegistering {
            let commitActionId = UUID()
            return [
                TransactionConfirmationActionModel(
                    id: commitActionId,
                    label: "ens_confirm_commit",
                    variant: .default,
                ) {
                    confirmEnsAction(actionId: commitActionId, isRegistering: true)
                },
                disabledEnsAction(label: "ens_confirm_register", variant: .neutral),
            ]
        }

        let signActionId = UUID()
        return [
            TransactionConfirmationActionModel(
                id: signActionId,
                label: "ens_confirm_sign",
                variant: .default,
            ) {
                confirmEnsAction(actionId: signActionId, isRegistering: false)
            },
        ]
    }

    private func confirmEnsAction(actionId: UUID, isRegistering _: Bool) {
        updatePendingConfirmationActions(
            actionId: actionId,
            visualState: .loading,
            isEnabled: false,
            disableOthers: true,
        )
        Task { @MainActor in
            await saveProfile()
            switch saveFlowState {
            case .failed:
                showConfirmationErrorState(actionId: actionId)
            case .succeeded:
                showConfirmationSuccessState(actionId: actionId)
                try? await Task.sleep(for: .milliseconds(250))
                pendingConfirmation = nil
            case .idle, .inProgress:
                pendingConfirmation = nil
            }
        }
    }

    private func updatePendingConfirmationActions(
        actionId: UUID,
        visualState: AppButtonVisualState,
        isEnabled: Bool,
        disableOthers: Bool,
    ) {
        guard let model = pendingConfirmation else { return }

        let updatedActions = model.actions.map { action in
            if action.id == actionId {
                return TransactionConfirmationActionModel(
                    id: action.id,
                    label: action.label,
                    variant: action.variant,
                    visualState: visualState,
                    isEnabled: isEnabled,
                    handler: action.handler,
                )
            }

            let updatedIsEnabled = disableOthers ? false : action.isEnabled
            return TransactionConfirmationActionModel(
                id: action.id,
                label: action.label,
                variant: action.variant,
                visualState: action.visualState,
                isEnabled: updatedIsEnabled,
                handler: action.handler,
            )
        }

        pendingConfirmation = model.withActions(updatedActions)
    }

    private func showConfirmationErrorState(actionId: UUID) {
        updatePendingConfirmationActions(
            actionId: actionId,
            visualState: .error,
            isEnabled: true,
            disableOthers: false,
        )
    }

    private func showConfirmationSuccessState(actionId: UUID) {
        updatePendingConfirmationActions(
            actionId: actionId,
            visualState: .success,
            isEnabled: false,
            disableOthers: true,
        )
    }

    private func disabledEnsAction(
        label: LocalizedStringKey,
        variant: AppButtonVariant,
        visualState: AppButtonVisualState = .normal,
    ) -> TransactionConfirmationActionModel {
        TransactionConfirmationActionModel(
            label: label,
            variant: variant,
            visualState: visualState,
            isEnabled: false,
        ) {}
    }

    private func estimateFormattedFee() async throws -> String {
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

    @MainActor
    func buildProfilePayloads() async throws -> ProfilePayloadsModel {
        try await ensureAvatarUploadCompletedIfNeeded()

        let normalizedName = ENSService.ensLabel(ensName)
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
        let canonicalName = ENSService.canonicalENSName(normalizedName)

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
            let registrationPayloads = try await ensService.registerNamePayloads(
                name: normalizedName,
                ownerAddress: eoaAddress,
                initialRecords: initialRecords,
            )
            commitCall = registrationPayloads.commitCall
            postCommitCalls.append(registrationPayloads.registerCall)
            minCommitmentAgeSeconds = max(1, registrationPayloads.minCommitmentAgeSeconds)
        }

        if avatar != initialAvatarURL, !embeddedRecordKeys.contains("avatar") {
            let avatarPayload = try await ensService.setTextRecordPayload(
                name: canonicalName,
                key: "avatar",
                value: avatar,
            )
            postCommitCalls.append(avatarPayload)
        }

        if description != initialBio, !embeddedRecordKeys.contains("description") {
            let bioPayload = try await ensService.setTextRecordPayload(
                name: canonicalName,
                key: "description",
                value: description,
            )
            postCommitCalls.append(bioPayload)
        }

        return ProfilePayloadsModel(
            commit: commitCall,
            postCommit: postCommitCalls,
            minAge: minCommitmentAgeSeconds,
        )
    }

    @MainActor
    func saveProfile() async {
        guard !isSaving else { return }
        isSaving = true
        saveFlowState = .inProgress
        preparedPayloads = 0
        defer { isSaving = false }

        do {
            let payloads = try await buildProfilePayloads()
            let commitCall = payloads.commit
            let postCommitCalls = payloads.postCommit
            let minCommitmentAgeSeconds = payloads.minAge
            let normalizedName = ENSService.ensLabel(ensName)

            preparedPayloads = (commitCall != nil ? 1 : 0) + postCommitCalls.count

            guard commitCall != nil || !postCommitCalls.isEmpty else {
                showSuccess(String(localized: "profile_no_changes_to_save"))
                saveFlowState = .succeeded
                return
            }

            let sessionAccount = try await accountService.restoreSession(eoaAddress: eoaAddress)
            if let commitCall {
                let commitSubmissionHash = try await aaExecutionService.executeCalls(
                    accountService: accountService,
                    account: sessionAccount,
                    chainId: ensService.chainID,
                    calls: [commitCall],
                )
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
                _ = try await aaExecutionService.executeCalls(
                    accountService: accountService,
                    account: sessionAccount,
                    chainId: ensService.chainID,
                    calls: postCommitCalls,
                )
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
            if pendingConfirmation == nil {
                showError(error)
            } else {
                print("[ProfileView] ENS confirmation failed: \(error.localizedDescription)")
            }
        }
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
        lastQuotedName = ENSService.ensLabel(initialENSName)
        saveFlowState = .idle
    }
}
