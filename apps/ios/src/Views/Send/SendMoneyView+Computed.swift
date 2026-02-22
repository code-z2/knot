import Balance
import Compose
import SwiftUI

extension SendMoneyView {
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
        }
    }

    var amountButtonVariant: AppButtonVariant {
        switch amountButtonState {
        case .normal:
            .default
        case .loading:
            .neutral
        case .error:
            .destructive
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
        }
    }

    var canAttemptAmountAction: Bool {
        enteredMainAmount > 0 && amountButtonState == .normal
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

        if isRoutingInProgress {
            return ("Finding best route...", AppThemeColor.labelSecondary)
        }

        if let routeError {
            switch routeError {
            case .insufficientBalance:
                return (String(localized: "send_money_insufficient_balance"), AppThemeColor.accentRed)
            case let .noRouteFound(reason):
                return ("No route found: \(reason)", AppThemeColor.accentRed)
            case let .quoteUnavailable(provider, _):
                return ("\(provider) quote unavailable", AppThemeColor.accentRed)
            case .unsupportedChain:
                return ("Unsupported chain", AppThemeColor.accentRed)
            case .unsupportedAsset:
                return ("Unsupported asset", AppThemeColor.accentRed)
            }
        }

        if let route = currentRoute {
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
                case .transfer: "transfer"
                case .swap: "swap"
                case .bridge: "bridge"
                case .accumulate: "bridge"
                }
            }.joined(separator: " → ")
            let summary = "Route: \(stepsDescription). Recipient gets \(amountText) \(route.estimatedAmountOutSymbol)"
            return (summary, AppThemeColor.accentBrown)
        }

        return nil
    }

    var selectedChainExplorerChainId: UInt64? {
        selectedChain?.rpcChainID
    }

    var successStatusDetailText: String? {
        guard let executionResult else { return nil }

        if executionResult.hasDeferredRelayTasks {
            return "Destination submitted. Remaining chain intents are deferred until accumulator fill completes."
        }

        if !executionResult.backgroundRelayTaskIDs.isEmpty {
            return "Submitted. Additional chain submissions are processing in parallel."
        }

        return nil
    }
}
