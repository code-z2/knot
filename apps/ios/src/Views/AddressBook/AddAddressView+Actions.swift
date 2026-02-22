import SwiftUI

extension AddAddressView {
    func expandedBinding(for field: AddAddressField) -> Binding<Bool> {
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

    func activate(_ field: AddAddressField) {
        if activeField == .address, field != .address {
            finalizeAddressIfNeeded()
        }

        activeField = field

        if field == .chain, let selectedChain, chainQuery.isEmpty {
            chainQuery = selectedChain.name
        }

        switch field {
        case .address:
            isAddressInputFocused = true
            isChainInputFocused = false
            isAliasInputFocused = false
        case .chain:
            isAddressInputFocused = false
            isChainInputFocused = true
            isAliasInputFocused = false
        }
    }

    func collapseAllFields() {
        if activeField == .address {
            finalizeAddressIfNeeded()
        }

        if selectedChain == nil {
            chainQuery = ""
        } else {
            chainQuery = selectedChain?.name ?? ""
        }

        activeField = nil
        isAddressInputFocused = false
        isChainInputFocused = false
        isAliasInputFocused = false
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

    func focusFirstIncompleteField() {
        if addressBadge == nil {
            activate(.address)
            return
        }

        if chainBadge == nil {
            activate(.chain)
            return
        }

        activeField = nil
        isAddressInputFocused = false
        isChainInputFocused = false
        isAliasInputFocused = alias.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func handleAddressQueryDidChange(_ newValue: String) {
        let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)

        if !trimmed.isEmpty, selectedBeneficiary != nil || finalizedAddressValue != nil {
            selectedBeneficiary = nil
            finalizedAddressValue = nil
        }

        addressDetectionTask?.cancel()

        guard !trimmed.isEmpty else { return }

        let snapshot = trimmed
        let mode = addressValidationMode

        addressDetectionTask = Task(priority: .userInitiated) { @MainActor in
            let detection = AddressInputParser.detectCandidate(snapshot, mode: mode)

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
        guard !candidate.isEmpty else {
            return
        }

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
        switch addressValidationMode {
        case .flexible:
            !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .strictAddressOrENS:
            AddressInputParser.isLikelyEVMAddress(input) || AddressInputParser.isLikelyENSName(input)
        }
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
    func save() async {
        guard !isSaving else { return }

        finalizeAddressIfNeeded()

        guard
            let address = resolvedAddress,
            let chain = selectedChain?.name,
            !address.isEmpty
        else {
            return
        }

        let trimmedAlias = alias.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedAlias.isEmpty else { return }

        isSaving = true
        defer { isSaving = false }

        await onSave(
            .init(
                name: trimmedAlias,
                address: address,
                chain: chain,
            ),
        )

        dismiss()
    }
}
