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

    func handleHeaderBack() {
        if isShowingSpendAssetPicker {
            isShowingSpendAssetPicker = false
            return
        }

        if step == .success {
            onBack()
            return
        }

        if step == .amount {
            withAnimation(AppAnimation.standard) {
                stepNavigationDirection = .backward
                step = .recipient
            }
            return
        }

        onBack()
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
        withAnimation(AppAnimation.standard) {
            stepNavigationDirection = .forward
            step = .amount
        }
    }

    func confirmAmount() {
        guard canAttemptAmountAction else { return }
        amountActionTask?.cancel()

        if isInsufficientBalance {
            amountButtonState = .error
            amountActionTask = Task { @MainActor in
                do {
                    try await Task.sleep(for: .milliseconds(1100))
                } catch {
                    return
                }
                amountButtonState = .normal
            }
            return
        }

        guard let route = currentRoute else {
            resolveRoute()
            return
        }

        amountButtonState = .loading
        amountActionTask = Task { @MainActor in
            do {
                let submission = try await sendFlowService.submitRoute(
                    eoaAddress: eoaAddress,
                    route: route,
                )
                executionResult = submission
                txHash = submission.destinationRelayTaskID

                amountButtonState = .normal
                successHapticTrigger += 1
                withAnimation(AppAnimation.gentle) {
                    stepNavigationDirection = .forward
                    step = .success
                }
            } catch let error as SendFlowServiceError {
                amountButtonState = .error
                errorHapticTrigger += 1
                presentErrorMessage(error.localizedDescription)
                do {
                    try await Task.sleep(for: .milliseconds(2000))
                } catch {
                    return
                }
                amountButtonState = .normal
            } catch {
                amountButtonState = .error
                errorHapticTrigger += 1
                presentErrorMessage(error.localizedDescription)
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
        withAnimation(AppAnimation.standard) {
            stepNavigationDirection = .backward
            step = .recipient
        }
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

        var normalized = trimmed
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
