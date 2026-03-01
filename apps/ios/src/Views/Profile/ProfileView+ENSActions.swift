import ENS
import RPC
import SwiftUI
import Transactions

struct ProfilePayloadsModel {
    let name: String
    let commit: Call?
    let postCommit: [Call]
    let minAge: UInt64
    let preparedPayloadCount: Int
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

            if !cached.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return
            }
        }

        do {
            let resolvedName = try await ensService.reverseAddress(address: eoaAddress)
            let normalizedName = ensService.ensLabel(resolvedName)
            if !normalizedName.isEmpty {
                let fullName = ensService.canonicalENSName(resolvedName)

                async let avatarFetch: String = await (try? ensService.textRecord(name: fullName, key: "avatar"))?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                async let bioFetch: String = await (try? ensService.textRecord(name: fullName, key: "description")) ?? ""

                let loadedAvatar = await avatarFetch
                let loadedBio = await bioFetch

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
            switch error {
            case let ENSServiceError.actionFailed(cause as ENSError):
                if case .ensUnavailable = cause {
                    break
                }
            default:
                break
            }
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

        let normalized = ensService.ensLabel(input)
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
                        && ensService.ensLabel(ensName) == normalized
                guard shouldContinue else { return }

                isCheckingName = true
                defer {
                    if ensService.ensLabel(self.ensName) == normalized {
                        self.isCheckingName = false
                    }
                }

                let quote = try await quoteWorker.quote(name: normalized)
                try Task.checkCancellation()

                guard !isNameLocked else { return }
                guard ensService.ensLabel(ensName) == normalized else { return }

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
                guard ensService.ensLabel(ensName) == normalized else { return }
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
                async let payloadsFetch = buildProfilePayloads()
                async let feeFetch = estimateFeeETH()

                let payloads = try await payloadsFetch
                guard payloads.preparedPayloadCount > 0 else {
                    pendingProfilePayloads = nil
                    pendingConfirmation = nil
                    showSuccess(String(localized: "profile_no_changes_to_save"))
                    return
                }
                pendingProfilePayloads = payloads
                preparedPayloads = payloads.preparedPayloadCount

                let feeETH = try await feeFetch
                let feeFormatted = await formatFee(feeETH: feeETH)
                let hasSufficientEth = hasSufficientEthBalance(for: feeETH)
                let warning: LocalizedStringKey? = hasSufficientEth ? nil : "send_money_insufficient_balance"
                let chainDefinition = ChainRegistry.resolve(chainID: ensService.chainID)
                let chainName = chainDefinition?.name
                    ?? String(localized: "transaction_chain_unknown")
                let chainAssetName = chainDefinition?.assetName ?? chainName

                if payloads.commit != nil {
                    presentCommitRevealConfirmation(
                        feeText: feeFormatted,
                        chainName: chainName,
                        chainAssetName: chainAssetName,
                        warning: warning,
                        isCommitEnabled: hasSufficientEth,
                    )
                } else {
                    pendingConfirmation = makeSingleStepEnsConfirmationModel(
                        feeText: feeFormatted,
                        chainName: chainName,
                        chainAssetName: chainAssetName,
                        warning: warning,
                        isConfirmEnabled: hasSufficientEth,
                    )
                }
            } catch {
                pendingProfilePayloads = nil
                pendingConfirmation = nil
                showError(error)
            }
        }
    }

    private func presentCommitRevealConfirmation(
        feeText: String,
        chainName: String,
        chainAssetName: String,
        warning: LocalizedStringKey?,
        isCommitEnabled: Bool,
    ) {
        let actionIDs = ENSConfirmationActionIDs(commit: UUID(), register: UUID())
        ensConfirmationActionIDs = actionIDs
        revealCountdownSeconds = nil
        pendingENSRevealJob = nil
        cancelRevealTimers()

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
                    isEnabled: isCommitEnabled,
                ) {
                    confirmCommitAction()
                },
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
    }

    private func makeSingleStepEnsConfirmationModel(
        feeText: String,
        chainName: String,
        chainAssetName: String,
        warning: LocalizedStringKey?,
        isConfirmEnabled: Bool,
    ) -> TransactionConfirmationModel {
        let signActionId = UUID()
        let details = makeEnsDetails(
            typeText: String(localized: "transaction_type_ens_update"),
            feeText: feeText,
            chainName: chainName,
            chainAssetName: chainAssetName,
        )
        return TransactionConfirmationModel(
            title: "confirm_title",
            warning: warning,
            details: details,
            actions: [
                TransactionConfirmationActionModel(
                    id: signActionId,
                    label: "ens_confirm_sign",
                    icon: "person.badge.key.fill",
                    variant: .default,
                    isEnabled: isConfirmEnabled,
                ) {
                    confirmSingleStepAction(actionId: signActionId)
                },
            ],
        )
    }

    private func confirmSingleStepAction(actionId: UUID) {
        updatePendingConfirmationActions(
            actionId: actionId,
            visualState: .loading,
            isEnabled: false,
            disableOthers: true,
        )
        Task { @MainActor in
            isSaving = true
            defer { isSaving = false }
            saveFlowState = .inProgress
            do {
                let payloads = try confirmedPayloads()
                guard !payloads.postCommit.isEmpty else {
                    pendingConfirmation = nil
                    pendingProfilePayloads = nil
                    return
                }

                let sessionAccount = try await accountService.restoreSession(eoaAddress: eoaAddress)
                let submissionID = try await aaExecutionService.executeCalls(
                    accountService: accountService,
                    account: sessionAccount,
                    chainId: ensService.chainID,
                    calls: payloads.postCommit,
                )

                showConfirmationSuccessState(actionId: actionId)
                successTrigger += 1
                try await Task.sleep(for: .milliseconds(250))
                completeProfileSuccess(
                    preparedPayloadCount: payloads.preparedPayloadCount,
                    lockName: false,
                    relayTaskID: submissionID,
                    chainId: ensService.chainID,
                )
            } catch {
                errorTrigger += 1
                saveFlowState = .failed(error.localizedDescription)
                showConfirmationErrorState(actionId: actionId)
            }
        }
    }

    private func confirmCommitAction() {
        guard let actionIDs = ensConfirmationActionIDs else { return }
        updatePendingConfirmationActions(
            actionId: actionIDs.commit,
            visualState: .loading,
            isEnabled: false,
            disableOthers: true,
        )
        updatePendingConfirmationConnectorText(nil)

        Task { @MainActor in
            isSaving = true
            defer { isSaving = false }
            saveFlowState = .inProgress
            do {
                let payloads = try confirmedPayloads()
                guard let commitCall = payloads.commit else {
                    throw ENSServiceError.actionFailed(
                        NSError(
                            domain: "ENS",
                            code: 4,
                            userInfo: [NSLocalizedDescriptionKey: "Missing ENS commit call."],
                        ),
                    )
                }

                let sessionAccount = try await accountService.restoreSession(eoaAddress: eoaAddress)
                let submissionHash = try await aaExecutionService.executeCalls(
                    accountService: accountService,
                    account: sessionAccount,
                    chainId: ensService.chainID,
                    calls: [commitCall],
                )

                let pendingJob = PendingENSRevealJob(
                    eoaAddress: eoaAddress,
                    name: payloads.name,
                    chainId: ensService.chainID,
                    submissionHash: submissionHash,
                    minCommitmentAgeSeconds: payloads.minAge,
                    revealNotBeforeUnix: 0,
                    postCommitCalls: payloads.postCommit,
                    preparedPayloadCount: payloads.preparedPayloadCount,
                )
                pendingENSRevealJob = pendingJob
                commitRevealStore.saveJob(pendingJob)
                showConfirmationSuccessState(actionId: actionIDs.commit)
                successTrigger += 1

                await prepareRevealWindow(for: pendingJob)
            } catch {
                errorTrigger += 1
                saveFlowState = .failed(error.localizedDescription)
                showConfirmationErrorState(actionId: actionIDs.commit)
            }
        }
    }

    func confirmRegisterAction() {
        guard let actionIDs = ensConfirmationActionIDs else { return }
        updatePendingConfirmationActions(
            actionId: actionIDs.register,
            visualState: .loading,
            isEnabled: false,
            disableOthers: true,
        )
        cancelRevealTimers()

        Task { @MainActor in
            isSaving = true
            defer { isSaving = false }
            saveFlowState = .inProgress
            do {
                let pendingJob = try currentPendingENSRevealJob()
                guard !pendingJob.postCommitCalls.isEmpty else {
                    throw ENSServiceError.actionFailed(
                        NSError(
                            domain: "ENS",
                            code: 5,
                            userInfo: [NSLocalizedDescriptionKey: "Missing ENS register call."],
                        ),
                    )
                }

                let sessionAccount = try await accountService.restoreSession(eoaAddress: eoaAddress)
                let submissionID = try await aaExecutionService.executeCalls(
                    accountService: accountService,
                    account: sessionAccount,
                    chainId: pendingJob.chainId,
                    calls: pendingJob.postCommitCalls,
                )

                showConfirmationSuccessState(actionId: actionIDs.register)
                successTrigger += 1
                commitRevealStore.clearJob(for: eoaAddress)
                pendingENSRevealJob = nil
                pendingProfilePayloads = nil
                try await Task.sleep(for: .milliseconds(250))
                completeProfileSuccess(
                    preparedPayloadCount: pendingJob.preparedPayloadCount,
                    lockName: true,
                    relayTaskID: submissionID,
                    chainId: pendingJob.chainId,
                )
            } catch {
                errorTrigger += 1
                saveFlowState = .failed(error.localizedDescription)
                showConfirmationErrorState(actionId: actionIDs.register)
            }
        }
    }

    func updatePendingConfirmationActions(
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

    private func confirmedPayloads() throws -> ProfilePayloadsModel {
        guard let payloads = pendingProfilePayloads else {
            throw ENSServiceError.actionFailed(
                NSError(
                    domain: "ENS",
                    code: 6,
                    userInfo: [NSLocalizedDescriptionKey: "Missing prepared ENS payloads."],
                ),
            )
        }
        return payloads
    }

    private func currentPendingENSRevealJob() throws -> PendingENSRevealJob {
        if let pendingENSRevealJob {
            return pendingENSRevealJob
        }
        if let stored = commitRevealStore.loadJob(for: eoaAddress) {
            pendingENSRevealJob = stored
            return stored
        }
        throw ENSServiceError.actionFailed(
            NSError(
                domain: "ENS",
                code: 7,
                userInfo: [NSLocalizedDescriptionKey: "Missing pending ENS reveal job."],
            ),
        )
    }

    private func resetEnsConfirmationState() {
        cancelRevealTimers()
        ensConfirmationActionIDs = nil
        pendingProfilePayloads = nil
        pendingENSRevealJob = nil
        revealCountdownSeconds = nil
        pendingConfirmation = nil
    }

    private func completeProfileSuccess(
        preparedPayloadCount: Int,
        lockName: Bool,
        relayTaskID: String?,
        chainId: UInt64,
    ) {
        let avatarChanged = avatarURL.trimmingCharacters(in: .whitespacesAndNewlines)
            != initialAvatarURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let bioChanged = bio.trimmingCharacters(in: .whitespacesAndNewlines)
            != initialBio.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasProfileUpdates = avatarChanged || bioChanged
        let nameDisplay = "\(ensName)\(ensService.tld)"
        let message = profileSuccessMessage(
            nameDisplay: nameDisplay,
            isRegistered: lockName,
            hasProfileUpdates: hasProfileUpdates,
        )

        if lockName {
            isNameLocked = true
        }
        initialAvatarURL = avatarURL
        initialBio = bio
        initialENSName = ensName
        ensProfileCache.save(
            CachedENSProfileModel(
                name: ensName,
                avatarURL: avatarURL,
                bio: bio,
                updatedAt: Date(),
            ),
            for: eoaAddress,
        )

        saveFlowState = .succeeded
        preparedPayloads = preparedPayloadCount
        resetEnsConfirmationState()
        profileSuccessDetailText = message
        profileSuccessRelayTaskID = relayTaskID
        profileSuccessChainID = chainId
        showProfileSuccessStep = true
    }

    @MainActor
    func openProfileSuccessExplorerURL() {
        let chainId = profileSuccessChainID ?? ensService.chainID
        let fallbackURL = BlockExplorer.addressURL(chainId: chainId, address: eoaAddress)

        guard let relayTaskID = profileSuccessRelayTaskID else {
            if let fallbackURL {
                openURL(fallbackURL, prefersInApp: true)
            }
            return
        }

        Task { @MainActor in
            do {
                let status = try await aaExecutionService.relayStatus(relayTaskID: relayTaskID)
                if let transactionHash = status.transactionHash,
                   let txURL = BlockExplorer.transactionURL(
                       chainId: chainId,
                       transactionHash: transactionHash,
                   )
                {
                    openURL(txURL, prefersInApp: true)
                    return
                }
            } catch {}

            if let fallbackURL {
                openURL(fallbackURL, prefersInApp: true)
            }
        }
    }

    @MainActor
    func buildProfilePayloads() async throws -> ProfilePayloadsModel {
        try await ensureAvatarUploadCompletedIfNeeded()

        let normalizedName = ensService.ensLabel(ensName)
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
        let canonicalName = ensService.canonicalENSName(normalizedName)

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

        let needsAvatarUpdate = avatar != initialAvatarURL && !embeddedRecordKeys.contains("avatar")
        let needsBioUpdate = description != initialBio && !embeddedRecordKeys.contains("description")

        if needsAvatarUpdate, needsBioUpdate {
            async let avatarPayload = ensService.setTextRecordPayload(
                name: canonicalName, key: "avatar", value: avatar,
            )
            async let bioPayload = ensService.setTextRecordPayload(
                name: canonicalName, key: "description", value: description,
            )
            try await postCommitCalls.append(avatarPayload)
            try await postCommitCalls.append(bioPayload)
        } else if needsAvatarUpdate {
            try await postCommitCalls.append(
                ensService.setTextRecordPayload(
                    name: canonicalName, key: "avatar", value: avatar,
                ),
            )
        } else if needsBioUpdate {
            try await postCommitCalls.append(
                ensService.setTextRecordPayload(
                    name: canonicalName, key: "description", value: description,
                ),
            )
        }

        return ProfilePayloadsModel(
            name: normalizedName,
            commit: commitCall,
            postCommit: postCommitCalls,
            minAge: minCommitmentAgeSeconds,
            preparedPayloadCount: (commitCall != nil ? 1 : 0) + postCommitCalls.count,
        )
    }

    @MainActor
    func cancelEditing() {
        resetEnsConfirmationState()
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
        lastQuotedName = ensService.ensLabel(initialENSName)
        saveFlowState = .idle
    }
}
