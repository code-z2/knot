import Balance
import Compose
import ENS
import Foundation
import RPC
import SwiftUI

extension SendMoneyView {
    func expandedBinding(for field: SendMoneyField) -> Binding<Bool> {
        Binding(
            get: { activeField == field },
            set: { isExpanded in
                if isExpanded {
                    activate(field)
                } else if activeField == field {
                    collapseAllFields()
                }
            },
        )
    }

    func activate(_ field: SendMoneyField) {
        if activeField == .address, field != .address {
            finalizeAddressIfNeeded()
        }

        activeField = field

        switch field {
        case .address:
            isAddressInputFocused = true
            isChainInputFocused = false
            isAssetInputFocused = false
        case .chain:
            isAddressInputFocused = false
            isChainInputFocused = true
            isAssetInputFocused = false
        case .asset:
            isAddressInputFocused = false
            isChainInputFocused = false
            isAssetInputFocused = true
        }
    }

    func collapseAllFields() {
        if activeField == .address {
            finalizeAddressIfNeeded()
        }

        activeField = nil
        isAddressInputFocused = false
        isChainInputFocused = false
        isAssetInputFocused = false
    }

    func clearAddressSelectionAndStartEditing() {
        selectedBeneficiary = nil
        finalizedAddressValue = nil
        addressQuery = ""
        addressValidationState = .idle
        ensResolvedAddress = nil
        addressValidationTask?.cancel()
        activate(.address)
    }

    func clearChainSelectionAndStartEditing() {
        selectedChain = nil
        chainQuery = ""
        activate(.chain)
    }

    func clearAssetSelectionAndStartEditing() {
        selectedAsset = nil
        assetQuery = ""
        activate(.asset)
    }

    func focusFirstIncompleteField() {
        if addressBadge == nil {
            activate(.address)
            return
        }

        if chainBadge == nil {
            activate(.chain)
            return
        }

        if assetBadge == nil {
            activate(.asset)
            return
        }

        activeField = nil
        isAddressInputFocused = false
        isChainInputFocused = false
        isAssetInputFocused = false
    }

    func handleAddressQueryDidChange(_ newValue: String) {
        let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)

        if !trimmed.isEmpty, selectedBeneficiary != nil || finalizedAddressValue != nil {
            selectedBeneficiary = nil
            finalizedAddressValue = nil
            addressValidationState = .idle
            ensResolvedAddress = nil
            addressValidationTask?.cancel()
        }

        addressDetectionTask?.cancel()

        guard !trimmed.isEmpty else { return }

        let snapshot = trimmed
        addressDetectionTask = Task(priority: .userInitiated) { @MainActor in
            let detection = AddressInputParser.detectCandidate(snapshot)

            guard !Task.isCancelled else { return }

            applyAddressDetectionResult(detection, sourceInput: snapshot)
        }
    }

    @MainActor
    func applyAddressDetectionResult(
        _ detection: AddressDetectionResult,
        sourceInput: String,
    ) {
        let current = addressQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard current == sourceInput else { return }
        guard selectedBeneficiary == nil else { return }

        switch detection {
        case let .evmAddress(address):
            finalizedAddressValue = address
            selectedBeneficiary = nil
            addressQuery = ""
            validateAddress(address)
            focusFirstIncompleteField()
        case let .ensName(ensName):
            finalizedAddressValue = ensName
            selectedBeneficiary = nil
            addressQuery = ""
            validateAddress(ensName)
            focusFirstIncompleteField()
        case .invalid:
            finalizedAddressValue = nil
            addressValidationState = .idle
            ensResolvedAddress = nil
        }
    }

    func finalizeAddressIfNeeded() {
        if let selectedBeneficiary {
            finalizedAddressValue = selectedBeneficiary.address
            if addressValidationState != .valid {
                validateAddress(selectedBeneficiary.address)
            }
            return
        }

        let candidate = addressQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !candidate.isEmpty else { return }

        if isAddressInputValid(candidate) {
            finalizedAddressValue = candidate
            if addressValidationState != .valid {
                validateAddress(candidate)
            }
        } else {
            finalizedAddressValue = nil
        }
    }

    func isAddressInputValid(_ input: String) -> Bool {
        AddressInputParser.isLikelyEVMAddress(input) || AddressInputParser.isLikelyENSName(input)
    }

    /// Validate the finalized address: EVM addresses are valid immediately,
    /// ENS names are resolved asynchronously via `ENSService`.
    func validateAddress(_ value: String) {
        addressValidationTask?.cancel()

        if AddressInputParser.isLikelyEVMAddress(value) {
            addressValidationState = .valid
            ensResolvedAddress = nil
            return
        }

        if AddressInputParser.isLikelyENSName(value) {
            addressValidationState = .validating
            ensResolvedAddress = nil
            addressValidationTask = Task {
                do {
                    let resolved = try await ensService.resolveName(name: value)
                    guard !Task.isCancelled else { return }
                    ensResolvedAddress = resolved
                    addressValidationState = .valid
                } catch {
                    guard !Task.isCancelled else { return }
                    ensResolvedAddress = nil
                    addressValidationState = .invalid
                }
            }
            return
        }

        addressValidationState = .invalid
        ensResolvedAddress = nil
    }

    func displayAddressOrENS(_ value: String) -> String {
        if AddressInputParser.isLikelyEVMAddress(value) {
            return AddressShortener.shortened(value)
        }
        return value
    }

    @MainActor
    func reload() async {
        do {
            beneficiaries = try store.list(eoaAddress: eoaAddress)
        } catch {
            showError(error)
        }
    }

    @MainActor
    func showError(_ error: Error) {
        presentErrorMessage(error.localizedDescription)
    }

    func presentScanner() {
        collapseAllFields()
        isShowingScanner = true
    }

    @MainActor
    func handleScannedCode(_ rawCode: String) -> Bool {
        guard let candidate = AddressInputParser.extractCandidate(from: rawCode) else {
            return false
        }

        selectedBeneficiary = nil
        finalizedAddressValue = candidate
        addressQuery = ""
        validateAddress(candidate)
        focusFirstIncompleteField()
        return true
    }

    func proceedToAmountStep() {
        guard canContinue else { return }
        finalizeAddressIfNeeded()
        guard
            let toAddressOrENS = resolvedAddress,
            let selectedChain,
            let selectedAsset
        else { return }

        onContinue(
            .init(
                toAddressOrENS: toAddressOrENS,
                chainID: String(selectedChain.rpcChainID),
                chainName: selectedChain.name,
                assetID: selectedAsset.id,
                assetSymbol: selectedAsset.symbol,
            ),
        )

        selectedSpendAsset = selectedAsset
        amountInput = ""
        isAmountDisplayInverted = false
        amountButtonState = .normal
        executionResult = nil
        txHash = nil
        showSuccessStep = false
        showAmountStep = true
    }

    func confirmAmount() {
        guard canAttemptAmountAction else { return }
        amountActionTask?.cancel()

        if isInsufficientBalance {
            showInsufficientBalanceFeedback()
            return
        }

        guard let route = currentRoute else {
            resolveRoute()
            return
        }

        amountButtonState = .loading
        amountActionTask = Task { @MainActor in
            defer { amountButtonState = .normal }
            do {
                pendingConfirmation = try await buildTransferConfirmationModel(route: route)
            } catch is CancellationError {
                return
            } catch {
                presentErrorMessage(error.localizedDescription)
            }
        }
    }

    private func showInsufficientBalanceFeedback() {
        amountButtonState = .error
        amountActionTask = Task { @MainActor in
            do {
                try await Task.sleep(for: .milliseconds(1100))
            } catch {
                return
            }
            amountButtonState = .normal
        }
    }

    @MainActor
    private func buildTransferConfirmationModel(
        route: TransferRouteModel,
    ) async throws -> TransactionConfirmationModel {
        let estimatedFee = try await sendFlowService.estimateRouteFee(
            eoaAddress: eoaAddress,
            route: route,
        )
        try Task.checkCancellation()

        let confirmationBuilder = TransactionConfirmationBuilder()
        var details = await confirmationBuilder.transferDetails(
            recipientDisplay: transferRecipientDisplay,
            feeText: formattedRouteFeeDisplay(estimatedFee: estimatedFee),
            chainName: transferChainDisplay,
            chainAssetName: transferChainAssetName,
            typeText: String(localized: "transaction_type_transfer"),
        )

        if let routeSummary = routeSummaryText(from: route) {
            details.append(
                TransactionConfirmationDetailModel(
                    label: "transaction_route_label",
                    value: .text(routeSummary),
                ),
            )
        }

        let confirmActionId = UUID()
        return TransactionConfirmationModel(
            title: "confirm_title",
            assetChange: TransactionConfirmationAssetChangeModel(
                amount: transferAmountDisplay,
                fiatAmount: transferFiatDisplay,
            ),
            warning: nil,
            details: details,
            actions: [
                TransactionConfirmationActionModel(
                    id: confirmActionId,
                    label: "send_money_confirm_sign",
                    variant: .default,
                ) {
                    handleConfirmSend(actionId: confirmActionId)
                },
            ],
        )
    }

    private func handleConfirmSend(actionId: UUID) {
        updatePendingConfirmationActions(
            actionId: actionId,
            visualState: .loading,
            isEnabled: false,
            disableOthers: true,
        )
        executeConfirmedSend(actionId: actionId)
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

    private func clearConfirmationAfterSuccess() {
        pendingConfirmation = nil
    }

    private var transferRecipientDisplay: String {
        displayAddressOrENS(selectedBeneficiary?.address ?? finalizedAddressValue ?? addressQuery)
    }

    private var transferAmountText: String {
        isAmountDisplayInverted ? secondaryAmountText : amountInput
    }

    private var transferFiatText: String {
        isAmountDisplayInverted ? amountInput : secondaryAmountText
    }

    private var transferAmountDisplay: String {
        let symbol = currentSpendAsset?.symbol ?? ""
        guard !symbol.isEmpty else { return transferAmountText }
        return "\(transferAmountText) \(symbol)"
    }

    private var transferFiatDisplay: String {
        let symbol = currencyRateStore.symbol(for: selectedFiatCode, locale: preferencesStore.locale)
        return "-\(symbol)\(transferFiatText)"
    }

    private var transferChainDisplay: String {
        selectedChain?.name ?? String(localized: "transaction_chain_unknown")
    }

    private var transferChainAssetName: String {
        selectedChain?.assetName ?? transferChainDisplay
    }

    @MainActor
    private func formattedRouteFeeDisplay(estimatedFee: Decimal) async -> String {
        await currencyRateStore.ensureRate(for: "ETH")
        let feeUSD = currencyRateStore.convertSelectedToUSD(estimatedFee, currencyCode: "ETH")
        let feeFiat = currencyRateStore.convertUSDToSelected(
            feeUSD,
            currencyCode: selectedFiatCode,
        )

        if feeFiat < 0.01 {
            let symbol = currencyRateStore.symbol(
                for: selectedFiatCode,
                locale: preferencesStore.locale,
            )
            return "~<\(symbol)0.01"
        }

        return "~\(currencyRateStore.formatUSD(feeUSD, currencyCode: selectedFiatCode, locale: preferencesStore.locale))"
    }

    private func routeSummaryText(from route: TransferRouteModel) -> String? {
        guard route.steps.count > 1 else { return nil }

        let summary = route.steps.map { step in
            switch step.action {
            case .transfer:
                String(localized: "transaction_route_step_transfer")
            case .swap:
                String(localized: "transaction_route_step_swap")
            case .bridge:
                String(localized: "transaction_route_step_bridge")
            case .accumulate:
                String(localized: "transaction_route_step_accumulate")
            }
        }

        return summary.joined(separator: " → ")
    }

    private func executeConfirmedSend(actionId: UUID) {
        guard let route = currentRoute else { return }

        amountButtonState = .loading
        amountActionTask = Task { @MainActor in
            do {
                let submission = try await sendFlowService.submitRoute(
                    eoaAddress: eoaAddress,
                    route: route,
                )
                showConfirmationSuccessState(actionId: actionId)
                executionResult = submission
                txHash = submission.destinationRelayTaskID

                amountButtonState = .normal
                successHapticTrigger += 1
                try await Task.sleep(for: .milliseconds(250))
                clearConfirmationAfterSuccess()
                showSuccessStep = true
            } catch {
                amountButtonState = .error
                errorHapticTrigger += 1
                showConfirmationErrorState(actionId: actionId)
                print("[SendMoneyView] Transfer confirmation failed: \(error.localizedDescription)")
                do {
                    try await Task.sleep(for: .milliseconds(2000))
                } catch {
                    return
                }
                amountButtonState = .normal
            }
        }
    }

    /// Debounced route resolution triggered when amount/asset/chain changes.
    func resolveRoute() {
        routeDebounceTask?.cancel()
        currentRoute = nil
        routeError = nil

        guard enteredMainAmount > 0,
              let spendAsset = currentSpendAsset,
              let selectedChain,
              let toAddress = resolvedAddress
        else {
            return
        }

        let destToken = selectedAsset?.contractAddress ?? spendAsset.contractAddress
        let destTokenSymbol = selectedAsset?.symbol ?? spendAsset.symbol
        let destTokenDecimals = selectedAsset?.decimals ?? spendAsset.decimals

        isRoutingInProgress = true
        routeDebounceTask = Task { @MainActor in
            defer { isRoutingInProgress = false }
            // Debounce: wait for input to stabilize.
            do {
                try await Task.sleep(for: .milliseconds(500))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }

            do {
                guard !Task.isCancelled else { return }

                let route = try await sendFlowService.resolveRoute(
                    eoaAddress: eoaAddress,
                    toAddress: toAddress,
                    sourceAsset: spendAsset,
                    destinationChainId: selectedChain.rpcChainID,
                    destinationToken: destToken,
                    destinationTokenSymbol: destTokenSymbol,
                    destinationTokenDecimals: destTokenDecimals,
                    amount: assetAmount,
                    accumulatorAddress: accumulatorAddress,
                )

                guard !Task.isCancelled else { return }
                currentRoute = route
                routeError = nil
            } catch let sendError as SendFlowServiceError {
                guard !Task.isCancelled else { return }
                switch sendError {
                case let .routeResolutionFailed(error):
                    routeError = error
                case .invalidRoute:
                    routeError = .noRouteFound(reason: sendError.localizedDescription)
                case .submissionFailed, .unknown:
                    routeError = .noRouteFound(reason: sendError.localizedDescription)
                }
                currentRoute = nil
            } catch {
                guard !Task.isCancelled else { return }
                routeError = .noRouteFound(reason: error.localizedDescription)
                currentRoute = nil
            }
        }
    }

    func repeatTransfer() {
        executionResult = nil
        txHash = nil
        showSuccessStep = false
        showAmountStep = false
    }

    func openSuccessExplorerURL() {
        guard
            let chainId = selectedChainExplorerChainId,
            let address = resolvedAddress,
            let url = BlockExplorer.addressURL(chainId: chainId, address: address)
        else {
            return
        }
        openURL(url, prefersInApp: true)
    }

    func handleKeypadTap(_ key: SendMoneyKeypadKey) {
        guard amountButtonState == .normal else { return }
        keypadHapticTrigger += 1
        switch key {
        case let .digit(digit):
            if amountInput == "0" {
                amountInput = digit
            } else {
                amountInput.append(digit)
            }
        case .decimal:
            if amountInput.isEmpty {
                amountInput = "0."
            } else if !amountInput.contains(".") {
                amountInput.append(".")
            }
        case .backspace:
            guard !amountInput.isEmpty else { return }
            amountInput.removeLast()
        }
    }

    func decimal(from input: String) -> Decimal? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return 0 }

        var normalized =
            trimmed
                .replacingOccurrences(of: "\u{00A0}", with: "")
                .replacingOccurrences(of: " ", with: "")

        if normalized.contains(","), normalized.contains(".") {
            // Treat commas as grouping separators when both are present.
            normalized = normalized.replacingOccurrences(of: ",", with: "")
        } else if normalized.contains(",") {
            // Support decimal-comma input by normalizing to decimal-point.
            normalized = normalized.replacingOccurrences(of: ",", with: ".")
        }

        return Decimal(string: normalized, locale: Locale(identifier: "en_US_POSIX"))
    }

    func format(
        _ value: Decimal,
        minFractionDigits: Int,
        maxFractionDigits: Int,
    ) -> String {
        let cappedMaxFractionDigits = max(0, min(maxFractionDigits, 4))
        let cappedMinFractionDigits = min(max(0, minFractionDigits), cappedMaxFractionDigits)
        let truncatedValue = DecimalTruncation.truncate(value, fractionDigits: cappedMaxFractionDigits)
        let formatter = NumberFormatter()
        formatter.locale = Locale.current
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = cappedMinFractionDigits
        formatter.maximumFractionDigits = cappedMaxFractionDigits
        return formatter.string(from: truncatedValue as NSDecimalNumber) ?? "0.0"
    }

    /// Formats a `Decimal` as a plain digit string (no grouping separators)
    /// suitable for use as raw keypad input.
    func plainDecimalString(_ value: Decimal, maxFractionDigits: Int) -> String {
        let capped = max(0, min(maxFractionDigits, 4))
        let truncated = DecimalTruncation.truncate(value, fractionDigits: capped)
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = capped
        return formatter.string(from: truncated as NSDecimalNumber) ?? "0"
    }

    func toast(message: String) -> some View {
        ToastView(message: message)
    }

    @MainActor
    private func presentErrorMessage(_ message: String) {
        errorMessage = message
        errorResetTask?.cancel()
        errorResetTask = Task { @MainActor in
            do {
                try await Task.sleep(for: .seconds(2.5))
            } catch {
                return
            }
            if errorMessage == message {
                errorMessage = nil
            }
        }
    }
}
