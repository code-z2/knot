import SwiftUI

enum AddAddressField: Hashable {
    case address
    case chain
}

struct AddAddressView: View {
    @Environment(\.dismiss) var dismiss

    let beneficiaries: [Beneficiary]
    let ensService: ENSService
    let onSave: @MainActor @Sendable (AddBeneficiaryDraft) async -> Void
    let addressValidationMode: DropdownInputValidationMode

    @State var activeField: AddAddressField?

    @State var addressQuery = ""
    @State var chainQuery = ""
    @State var alias = ""

    @State var selectedBeneficiary: Beneficiary?
    @State var selectedChain: ChainOption?
    @State var finalizedAddressValue: String?
    @State var isSaving = false
    @State var addressDetectionTask: Task<Void, Never>?
    @State var addressValidationState: AddressValidationState = .idle
    @State var ensResolvedAddress: String?
    @State var addressValidationTask: Task<Void, Never>?
    @State var isAddressInputFocused = false
    @State var isChainInputFocused = false
    @State var isAliasInputFocused = false

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

    var addressInputField: some View {
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

    var chainInputField: some View {
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

    var aliasInputField: some View {
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

    var addButton: some View {
        AddAddressPrimaryButton(
            canSave: canSave,
            isSaving: isSaving,
            onTap: {
                Task { await save() }
            },
        )
    }

    var addressDropdown: some View {
        AddAddressAddressDropdownView(
            beneficiaries: filteredBeneficiaries,
            onSelect: { beneficiary in
                selectedBeneficiary = beneficiary
                finalizedAddressValue = beneficiary.address
                addressQuery = ""
                addressValidationState = .valid
                ensResolvedAddress = nil
                focusFirstIncompleteField()
            },
        )
    }

    var chainDropdown: some View {
        AddAddressChainDropdownView(
            query: $chainQuery,
            onSelect: { chain in
                selectedChain = chain
                chainQuery = ""
                focusFirstIncompleteField()
            },
        )
    }

    var filteredBeneficiaries: [Beneficiary] {
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

    var addressBadge: DropdownBadgeValue? {
        let rawValue = selectedBeneficiary?.address ?? finalizedAddressValue
        guard let rawValue, !rawValue.isEmpty else { return nil }
        return DropdownBadgeValue(
            text: displayAddressOrENS(rawValue),
            validationState: addressValidationState,
        )
    }

    var chainBadge: DropdownBadgeValue? {
        guard let selectedChain else { return nil }
        return DropdownBadgeValue(
            text: selectedChain.name, iconAssetName: selectedChain.assetName, iconStyle: .network,
        )
    }

    var resolvedAddress: String? {
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

    var canSave: Bool {
        guard addressValidationState == .valid else { return false }
        guard let resolvedAddress, !resolvedAddress.isEmpty else { return false }
        guard selectedChain != nil else { return false }
        return !alias.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
