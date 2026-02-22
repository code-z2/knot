import Balance
import SwiftUI

extension SendMoneyView {
    var recipientStepContent: some View {
        VStack(spacing: 0) {
            addressInputField
                .zIndex(activeField == .address ? 30 : 1)

            chainInputField
                .zIndex(activeField == .chain ? 20 : 1)

            assetInputField
                .zIndex(activeField == .asset ? 10 : 1)

            Spacer()
        }
        .padding(.top, AppHeaderMetrics.contentTopPadding)
        .overlay(alignment: .bottom) {
            continueButton
                .padding(.bottom, 96)
        }
    }

    var stepTransition: AnyTransition {
        switch stepNavigationDirection {
        case .forward:
            .asymmetric(
                insertion: .move(edge: .trailing).combined(with: .opacity),
                removal: .move(edge: .leading).combined(with: .opacity),
            )
        case .backward:
            .asymmetric(
                insertion: .move(edge: .leading).combined(with: .opacity),
                removal: .move(edge: .trailing).combined(with: .opacity),
            )
        }
    }

    var headerTitle: LocalizedStringKey {
        switch step {
        case .recipient:
            "send_money_title"
        case .amount:
            "send_money_enter_amount_title"
        case .success:
            ""
        }
    }

    var amountStepContent: some View {
        GeometryReader { _ in
            VStack(spacing: 0) {
                SendMoneyAmountDisplay(
                    primaryAmountText: primaryAmountText,
                    primarySymbolText: primarySymbolText,
                    secondaryAmountText: secondaryAmountText,
                    secondarySymbolText: secondarySymbolText,
                    onSwapTap: {
                        withAnimation(AppAnimation.standard) {
                            isAmountDisplayInverted.toggle()
                        }
                    },
                )
                .frame(height: 84, alignment: .bottom)
                .padding(.top, 42)
                .padding(.bottom, AppSpacing.md)

                if let helperMessage = amountHelperMessage {
                    Text(helperMessage.text)
                        .font(.custom("Roboto-Regular", size: 14))
                        .foregroundStyle(helperMessage.color)
                        .padding(.top, 36)
                        .padding(.bottom, 10)
                } else {
                    Spacer()
                        .frame(height: 46)
                }

                if let spendAsset = currentSpendAsset {
                    SendMoneyBalanceWidget(
                        asset: spendAsset,
                        balanceText: spendAssetBalanceText,
                        onSwitchTap: {
                            spendAssetQuery = ""
                            isShowingSpendAssetPicker = true
                        },
                    )
                }

                SendMoneyNumericKeypad(
                    height: 332,
                    rowSpacing: 36,
                ) { key in
                    handleKeypadTap(key)
                }
                .padding(.top, 28)
                .padding(.bottom, AppSpacing.xl)

                amountActionButton
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.horizontal, 48)
        }
    }

    var successStepContent: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 120)

            VStack(spacing: 56) {
                VStack(spacing: 48) {
                    SuccessCheckmark()
                        .frame(width: 127, height: 123)

                    VStack(spacing: AppSpacing.xl) {
                        Text("send_money_success_title")
                            .font(.custom("Roboto-Medium", size: 34))
                            .foregroundStyle(AppThemeColor.labelPrimary)
                            .multilineTextAlignment(.center)

                        Text("send_money_success_subtitle")
                            .font(.custom("Roboto-Regular", size: 20))
                            .foregroundStyle(AppThemeColor.labelPrimary)
                            .multilineTextAlignment(.center)

                        if let successStatusDetailText {
                            Text(successStatusDetailText)
                                .font(.custom("Roboto-Regular", size: 14))
                                .foregroundStyle(AppThemeColor.labelSecondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, AppSpacing.lg)
                        }
                    }
                }

                HStack(spacing: AppSpacing.sm) {
                    AppButton(label: "send_money_repeat_transfer", variant: .outline) {
                        repeatTransfer()
                    }

                    AppButton(label: "send_money_view_tx", variant: .outline) {
                        openSuccessExplorerURL()
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 38)
    }

    var addressInputField: some View {
        DropdownInputField(
            variant: .address,
            properties: .init(
                label: "send_money_to_label",
                placeholder: "send_money_address_placeholder",
                trailingIconAssetName: nil,
                textColor: AppThemeColor.labelPrimary,
                placeholderColor: AppThemeColor.labelSecondary,
            ),
            query: $addressQuery,
            badge: addressBadge,
            isExpanded: expandedBinding(for: .address),
            isFocused: $isAddressInputFocused,
            showsTrailingIcon: addressBadge == nil,
            onExpandRequest: { activate(.address) },
            onBadgeTap: clearAddressSelectionAndStartEditing,
            onTrailingIconTap: presentScanner,
        ) {
            addressDropdown
        }
    }

    var chainInputField: some View {
        DropdownInputField(
            variant: .chain,
            properties: .init(
                label: "send_money_chain_label",
                placeholder: "send_money_chain_placeholder",
                trailingIconAssetName: nil,
                textColor: AppThemeColor.labelPrimary,
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

    var assetInputField: some View {
        DropdownInputField(
            variant: .asset,
            properties: .init(
                label: "send_money_asset_label",
                placeholder: "send_money_asset_placeholder",
                trailingIconAssetName: nil,
                textColor: AppThemeColor.labelPrimary,
                placeholderColor: AppThemeColor.labelSecondary,
            ),
            query: $assetQuery,
            badge: assetBadge,
            isExpanded: expandedBinding(for: .asset),
            isFocused: $isAssetInputFocused,
            showsTrailingIcon: false,
            onExpandRequest: { activate(.asset) },
            onBadgeTap: clearAssetSelectionAndStartEditing,
        ) {
            assetDropdown
        }
    }

    var continueButton: some View {
        AppButton(label: "send_money_continue", variant: .default) {
            proceedToAmountStep()
        }
        .disabled(!canContinue)
        .opacity(canContinue ? 1 : 0)
        .animation(AppAnimation.standard, value: canContinue)
    }

    var amountActionButton: some View {
        AppButton(
            label: amountButtonLabel,
            variant: amountButtonVariant,
            visualState: amountButtonState,
            showIcon: amountButtonShowsIcon,
            iconName: amountButtonIconName,
            iconSize: 16,
        ) {
            confirmAmount()
        }
        .disabled(!canAttemptAmountAction)
        .opacity(amountActionButtonOpacity)
        .animation(AppAnimation.standard, value: canAttemptAmountAction)
        .animation(AppAnimation.standard, value: amountButtonState)
    }

    var spendAssetModal: some View {
        VStack(alignment: .leading, spacing: 0) {
            SearchInput(text: $spendAssetQuery, placeholderKey: "search_placeholder", width: nil)
                .padding(.horizontal, AppSpacing.lg)
                .padding(.top, 13)
                .padding(.bottom, 21)

            Rectangle()
                .fill(AppThemeColor.separatorOpaque)
                .frame(height: 4)

            ScrollView {
                AssetList(
                    query: spendAssetQuery,
                    state: .loaded(balanceStore.balances),
                    displayCurrencyCode: preferencesStore.selectedCurrencyCode,
                    displayLocale: preferencesStore.locale,
                    usdToSelectedRate: selectedFiatRateFromUSD,
                    showSectionLabels: true,
                ) { asset in
                    selectedSpendAsset = asset
                    spendAssetQuery = ""
                    isShowingSpendAssetPicker = false
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 28)
            }
            .scrollIndicators(.hidden)
            .padding(.horizontal, AppSpacing.lg)
            .padding(.top, AppSpacing.xl)
            .padding(.bottom, AppSpacing.xl)
        }
    }

    var addressDropdown: some View {
        Group {
            if filteredBeneficiaries.isEmpty {
                Text("send_money_no_beneficiaries_found")
                    .font(.custom("Roboto-Regular", size: 13))
                    .foregroundStyle(AppThemeColor.labelSecondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 36)
            } else {
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(filteredBeneficiaries) { beneficiary in
                            BeneficiaryRow(beneficiary: beneficiary) {
                                selectionHapticTrigger += 1
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
                .scrollIndicators(.hidden)
            }
        }
    }

    var chainDropdown: some View {
        ChainList(query: chainQuery) { chain in
            selectionHapticTrigger += 1
            selectedChain = chain
            chainQuery = ""
            focusFirstIncompleteField()
        }
    }

    var assetDropdown: some View {
        ScrollView {
            AssetList(
                query: assetQuery,
                state: .loaded(balanceStore.balances),
                displayCurrencyCode: preferencesStore.selectedCurrencyCode,
                displayLocale: preferencesStore.locale,
                usdToSelectedRate: selectedFiatRateFromUSD,
                showSectionLabels: true,
            ) { asset in
                selectionHapticTrigger += 1
                selectedAsset = asset
                assetQuery = ""
                focusFirstIncompleteField()
            }
        }
        .scrollIndicators(.hidden)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}
