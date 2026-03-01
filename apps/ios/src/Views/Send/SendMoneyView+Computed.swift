import Balance
import Compose
import Foundation
import SwiftUI

enum RouteResolutionState {
    case idle
    case resolving
    case resolved(TransferRouteModel)
    case failed(RouteError)
}

extension SendMoneyView {
    var currentStep: SendMoneyStep {
        if showSuccessStep {
            return .success
        }

        if showAmountStep {
            return .amount
        }

        return .recipient
    }

    var filteredBeneficiaries: [Beneficiary] {
        SearchSystem.filter(
            query: addressQuery,
            items: beneficiaries,
            toDocument: {
                SearchDocument(
                    id: $0.id.uuidString,
                    title: $0.name,
                    keywords: [$0.address, $0.chainLabel ?? ""],
                )
            },
            itemID: { $0.id.uuidString },
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
            text: selectedChain.name,
            iconAssetName: selectedChain.assetName,
            iconStyle: .network,
        )
    }

    var assetBadge: DropdownBadgeValue? {
        guard let selectedAsset else { return nil }
        return DropdownBadgeValue(
            text: selectedAsset.symbol,
            iconURL: selectedAsset.logoURL,
            iconStyle: .network,
        )
    }

    var resolvedAddress: String? {
        if let selectedBeneficiary {
            return selectedBeneficiary.address.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // If ENS was resolved, use the resolved 0x address.
        if let ensResolvedAddress {
            return ensResolvedAddress
        }

        if let finalizedAddressValue, AddressInputParser.isLikelyEVMAddress(finalizedAddressValue) {
            return finalizedAddressValue.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let candidate = addressQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !candidate.isEmpty else { return nil }
        guard AddressInputParser.isLikelyEVMAddress(candidate) else { return nil }
        return candidate
    }

    var canContinue: Bool {
        guard addressValidationState == .valid else { return false }
        guard let resolvedAddress, !resolvedAddress.isEmpty else { return false }
        guard selectedChain != nil else { return false }
        return selectedAsset != nil
    }

    var currentSpendAsset: TokenBalanceModel? {
        selectedSpendAsset ?? selectedAsset
    }

    var amountButtonLabel: LocalizedStringKey {
        switch amountButtonState {
        case .normal:
            "send_money_confirm"
        case .loading:
            "send_money_sending"
        case .error:
            "send_money_failed"
        case .success:
            "send_money_confirm"
        }
    }

    var amountButtonVariant: AppButtonVariant {
        switch amountButtonState {
        case .normal:
            if case .resolved = routeState { .default } else { .neutral }
        case .loading:
            .neutral
        case .error:
            .destructive
        case .success:
            .default
        }
    }

    var amountButtonShowsIcon: Bool {
        amountButtonState != .normal
    }

    var amountButtonIconName: String? {
        switch amountButtonState {
        case .normal:
            nil
        case .loading:
            nil
        case .error:
            "xmark.circle.fill"
        case .success:
            "checkmark.circle.fill"
        }
    }

    var canAttemptAmountAction: Bool {
        guard enteredMainAmount > 0, amountButtonState == .normal else { return false }
        if case .resolved = routeState { return true }
        return false
    }

    var amountActionButtonOpacity: Double {
        if amountButtonState != .normal {
            return 1
        }
        return enteredMainAmount > 0 ? 1 : 0.45
    }

    var selectedFiatCode: String {
        preferencesStore.selectedCurrencyCode
    }

    var selectedFiatRateFromUSD: Decimal {
        currencyRateStore.rateFromUSD(to: selectedFiatCode)
    }

    var assetUSDPrice: Decimal {
        currentSpendAsset?.quoteRate ?? 1
    }

    var enteredMainAmount: Decimal {
        decimal(from: amountInput) ?? 0
    }

    var usdAmount: Decimal {
        if isAmountDisplayInverted {
            return enteredMainAmount * assetUSDPrice
        }
        guard selectedFiatRateFromUSD > 0 else {
            return enteredMainAmount
        }
        return currencyRateStore.convertSelectedToUSD(
            enteredMainAmount,
            currencyCode: selectedFiatCode,
        )
    }

    var assetAmount: Decimal {
        if isAmountDisplayInverted {
            return enteredMainAmount
        }
        guard assetUSDPrice > 0 else { return 0 }
        return usdAmount / assetUSDPrice
    }

    var displayFiatAmount: Decimal {
        currencyRateStore.convertUSDToSelected(
            usdAmount,
            currencyCode: selectedFiatCode,
        )
    }

    var availableAssetBalance: Decimal {
        currentSpendAsset?.totalBalance ?? 0
    }

    var isInsufficientBalance: Bool {
        assetAmount > availableAssetBalance && enteredMainAmount > 0
    }

    var primaryAmountText: String {
        typedMainAmountText
    }

    var primarySymbolText: String {
        if isAmountDisplayInverted {
            return currentSpendAsset!.symbol
        }
        return currencyRateStore.symbol(
            for: selectedFiatCode,
            locale: preferencesStore.locale,
        )
    }

    var secondaryAmountText: String {
        let value = isAmountDisplayInverted ? displayFiatAmount : assetAmount
        return format(value, minFractionDigits: 1, maxFractionDigits: 4)
    }

    var typedMainAmountText: String {
        let raw = amountInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return "0.0" }
        return raw
    }

    var secondarySymbolText: String {
        if isAmountDisplayInverted {
            return currencyRateStore.symbol(
                for: selectedFiatCode,
                locale: preferencesStore.locale,
            )
        }
        return currentSpendAsset!.symbol
    }

    var spendAssetBalanceText: String {
        guard let spendAsset = currentSpendAsset else { return "0" }
        return currencyRateStore.formatUSD(
            spendAsset.totalValueUSD,
            currencyCode: selectedFiatCode,
            locale: preferencesStore.locale,
        )
    }

    var amountHelperMessage: (text: String, color: Color)? {
        if isInsufficientBalance {
            return (String(localized: "send_money_insufficient_balance"), AppThemeColor.accentRed)
        }

        switch routeState {
        case .idle:
            return nil

        case .resolving:
            return (String(localized: "send_money_route_finding"), AppThemeColor.labelSecondary)

        case let .failed(routeError):
            switch routeError {
            case .insufficientBalance:
                return (String(localized: "send_money_insufficient_balance"), AppThemeColor.accentRed)
            case let .noRouteFound(reason):
                return (
                    String.localizedStringWithFormat(
                        NSLocalizedString("send_money_route_not_found_format", comment: ""),
                        reason,
                    ),
                    AppThemeColor.accentRed,
                )
            case let .quoteUnavailable(provider, _):
                return (
                    String.localizedStringWithFormat(
                        NSLocalizedString("send_money_route_provider_unavailable_format", comment: ""),
                        provider,
                    ),
                    AppThemeColor.accentRed,
                )
            case .unsupportedChain:
                return (String(localized: "send_money_route_unsupported_chain"), AppThemeColor.accentRed)
            case .unsupportedAsset:
                return (String(localized: "send_money_route_unsupported_asset"), AppThemeColor.accentRed)
            }

        case let .resolved(route):
            let isPhaseOneDirectTransfer =
                route.jobId == nil
                    && route.steps.count == 1
                    && route.steps.first?.action == .transfer

            if isPhaseOneDirectTransfer {
                return nil
            }

            let amountText = format(route.estimatedAmountOut, minFractionDigits: 1, maxFractionDigits: 4)
            let stepsDescription = route.steps.map { step in
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
            }.joined(separator: " → ")
            let summary = String.localizedStringWithFormat(
                NSLocalizedString("send_money_route_summary_format", comment: ""),
                stepsDescription,
                amountText,
                route.estimatedAmountOutSymbol,
            )
            return (summary, AppThemeColor.accentBrown)
        }
    }

    var selectedChainExplorerChainId: UInt64? {
        selectedChain?.rpcChainID
    }

    var successStatusDetailText: String? {
        guard let executionResult else { return nil }

        if executionResult.hasDeferredRelayTasks {
            return String(localized: "send_money_destination_submitted")
        }

        if !executionResult.backgroundRelayTaskIDs.isEmpty {
            return String(localized: "send_money_parallel_submissions")
        }

        return nil
    }
}
