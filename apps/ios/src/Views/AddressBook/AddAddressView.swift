import SwiftUI

enum AddAddressField: Hashable {
    case address
    case chain
}

struct AddAddressView: View {
    @Environment(\.dismiss) private var dismiss

    let beneficiaries: [Beneficiary]
    let ensService: ENSService
    let onSave: @MainActor @Sendable (AddBeneficiaryDraft) async -> Void
    let addressValidationMode: DropdownInputValidationMode

    @State private var activeField: AddAddressField?

    @State private var addressQuery = ""
    @State private var chainQuery = ""
    @State private var alias = ""

    @State private var selectedBeneficiary: Beneficiary?
    @State private var selectedChain: ChainOption?
    @State private var finalizedAddressValue: String?
    @State private var isSaving = false
    @State private var addressDetectionTask: Task<Void, Never>?
    @State private var addressValidationState: AddressValidationState = .idle
    @State private var ensResolvedAddress: String?
    @State private var addressValidationTask: Task<Void, Never>?
    @State private var isAddressInputFocused = false
    @State private var isChainInputFocused = false
    @State private var isAliasInputFocused = false

    init(
        beneficiaries: [Beneficiary],
        ensService: ENSService,
        addressValidationMode: DropdownInputValidationMode = .strictAddressOrENS,
        onSave: @escaping @MainActor @Sendable (AddBeneficiaryDraft) async -> Void,
    ) {
        self.beneficiaries = beneficiaries
        self.ensService = ensService
        self.addressValidationMode = addressValidationMode
        self.onSave = onSave
    }

    var body: some View {
        ZStack {
            AppThemeColor.backgroundPrimary.ignoresSafeArea()

            VStack(spacing: 0) {
                addressInputField
                    .zIndex(activeField == .address ? 30 : 1)

                chainInputField
                    .zIndex(activeField == .chain ? 20 : 1)

                aliasInputField

                Spacer()
            }
            .padding(.top, AppHeaderMetrics.contentTopPadding)

            addButton
                .padding(.bottom, 96)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            AppHeader(
                title: "address_book_new_address_title",
                titleFont: .custom("Roboto-Bold", size: 22),
                titleColor: AppThemeColor.labelSecondary,
                onBack: {
                    dismiss()
                },
            )
        }
        .onChange(of: addressQuery) { _, newValue in
            handleAddressQueryDidChange(newValue)
        }
        .onChange(of: chainQuery) { _, newValue in
            guard activeField == .chain else { return }
            if let selectedChain, selectedChain.name != newValue {
                self.selectedChain = nil
            }
        }
        .onDisappear {
            addressDetectionTask?.cancel()
            addressValidationTask?.cancel()
        }
        .onAppear {
            focusFirstIncompleteField()
        }
    }

    private var addressInputField: some View {
        DropdownInputField(
            variant: .address,
            properties: .init(
                placeholder: "address_book_placeholder_address_or_ens",
                trailingIconAssetName: nil,
                textColor: AppThemeColor.labelPrimary,
                placeholderColor: AppThemeColor.labelSecondary,
            ),
            query: $addressQuery,
            badge: addressBadge,
            isExpanded: expandedBinding(for: .address),
            isFocused: $isAddressInputFocused,
            showsTrailingIcon: false,
            onExpandRequest: { activate(.address) },
            onBadgeTap: clearAddressSelectionAndStartEditing,
        ) {
            addressDropdown
        }
    }

    private var chainInputField: some View {
        DropdownInputField(
            variant: .chain,
            properties: .init(
                placeholder: "address_book_placeholder_chain",
                trailingIconAssetName: nil,
                textColor: AppThemeColor.labelSecondary,
                placeholderColor: AppThemeColor.labelSecondary,
            ),
            query: $chainQuery,
            badge: chainBadge,
            isExpanded: expandedBinding(for: .chain),
            isFocused: $isChainInputFocused,
            showsTrailingIcon: false,
            onExpandRequest: { activate(.chain) },
            onBadgeTap: clearChainSelectionAndStartEditing,
        ) {
            chainDropdown
        }
    }

    private var aliasInputField: some View {
        DropdownInputField(
            variant: .noDropdown,
            properties: .init(
                placeholder: "address_book_placeholder_alias",
                trailingIconAssetName: nil,
                textFont: .custom("Inter-Regular_Medium", size: 14),
                textColor: AppThemeColor.labelPrimary,
                placeholderColor: AppThemeColor.labelSecondary,
            ),
            query: $alias,
            badge: nil,
            isExpanded: .constant(false),
            isFocused: $isAliasInputFocused,
            showsTrailingIcon: false,
        ) {
            EmptyView()
        }
    }

    private var addButton: some View {
        Button {
            Task {
                await save()
            }
        } label: {
            Text("address_book_add")
                .font(.custom("Roboto-Bold", size: 15))
                .foregroundStyle(AppThemeColor.backgroundPrimary)
                .padding(.horizontal, 17)
                .padding(.vertical, 15)
                .frame(minWidth: 100)
        }
        .buttonStyle(.borderedProminent)
        .disabled(!canSave || isSaving)
        .opacity(canSave && !isSaving ? 1 : 0)
        .animation(AppAnimation.standard, value: canSave)
        .tint(AppThemeColor.accentBrown)
    }

    private var addressDropdown: some View {
        Group {
            if filteredBeneficiaries.isEmpty {
                Text("address_book_no_beneficiaries_found")
                    .font(.custom("Roboto-Regular", size: 13))
                    .foregroundStyle(AppThemeColor.labelSecondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 36)
            } else {
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 6) {
                        ForEach(filteredBeneficiaries) { beneficiary in
                            BeneficiaryRow(beneficiary: beneficiary) {
                                selectedBeneficiary = beneficiary
                                finalizedAddressValue = beneficiary.address
                                addressQuery = ""
                                addressValidationState = .valid
                                ensResolvedAddress = nil
                                focusFirstIncompleteField()
                            }
                        }
                    }
                }
                .frame(maxHeight: 182)
            }
        }
    }

    private var chainDropdown: some View {
        ChainList(query: chainQuery) { chain in
            selectedChain = chain
            chainQuery = ""
            focusFirstIncompleteField()
        }
        .frame(maxHeight: 360)
    }

    private var filteredBeneficiaries: [Beneficiary] {
        SearchSystem.filter(
            query: addressQuery,
            items: beneficiaries,
            toDocument: {
                SearchDocument(
                    id: $0.id,
                    title: $0.name,
                    keywords: [$0.address, $0.chainLabel ?? ""],
                )
            },
            itemID: { $0.id },
        )
    }

    private var addressBadge: DropdownBadgeValue? {
        let rawValue = selectedBeneficiary?.address ?? finalizedAddressValue
        guard let rawValue, !rawValue.isEmpty else { return nil }
        return DropdownBadgeValue(
            text: displayAddressOrENS(rawValue),
            validationState: addressValidationState,
        )
    }

    private var chainBadge: DropdownBadgeValue? {
        guard let selectedChain else { return nil }
        return DropdownBadgeValue(
            text: selectedChain.name, iconAssetName: selectedChain.assetName, iconStyle: .network,
        )
    }

    private var resolvedAddress: String? {
        if let selectedBeneficiary {
            return selectedBeneficiary.address.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // For ENS names, return the resolved 0x address
        if let ensResolvedAddress {
            return ensResolvedAddress
        }

        if let finalizedAddressValue {
            let trimmed = finalizedAddressValue.trimmingCharacters(in: .whitespacesAndNewlines)
            // Only return raw address if it's an EVM address (not an unresolved ENS name)
            if AddressInputParser.isLikelyEVMAddress(trimmed) {
                return trimmed
            }
            return nil
        }

        let candidate = addressQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !candidate.isEmpty else { return nil }
        guard isAddressInputValid(candidate) else { return nil }
        return candidate
    }

    private var canSave: Bool {
        guard addressValidationState == .valid else { return false }
        guard let resolvedAddress, !resolvedAddress.isEmpty else { return false }
        guard selectedChain != nil else { return false }
        return !alias.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func expandedBinding(for field: AddAddressField) -> Binding<Bool> {
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

    private func activate(_ field: AddAddressField) {
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

    private func collapseAllFields() {
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

    private func clearAddressSelectionAndStartEditing() {
        selectedBeneficiary = nil
        finalizedAddressValue = nil
        addressQuery = ""
        addressValidationState = .idle
        ensResolvedAddress = nil
        addressValidationTask?.cancel()
        activate(.address)
    }

    private func clearChainSelectionAndStartEditing() {
        selectedChain = nil
        chainQuery = ""
        activate(.chain)
    }

    private func focusFirstIncompleteField() {
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

    private func handleAddressQueryDidChange(_ newValue: String) {
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
    private func applyAddressDetectionResult(
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

    private func finalizeAddressIfNeeded() {
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

    private func isAddressInputValid(_ input: String) -> Bool {
        switch addressValidationMode {
        case .flexible:
            !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .strictAddressOrENS:
            AddressInputParser.isLikelyEVMAddress(input) || AddressInputParser.isLikelyENSName(input)
        }
    }

    /// Validate the finalized address: EVM addresses are valid immediately,
    /// ENS names are resolved asynchronously via `ENSService`.
    private func validateAddress(_ value: String) {
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

    private func displayAddressOrENS(_ value: String) -> String {
        if AddressInputParser.isLikelyEVMAddress(value) {
            return AddressShortener.shortened(value)
        }
        return value
    }

    @MainActor
    private func save() async {
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
