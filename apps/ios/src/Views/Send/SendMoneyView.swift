import AA
import AccountSetup
import Balance
import Compose
import ENS
import RPC
import SwiftUI
import Transactions

struct SendMoneyView: View {
  let eoaAddress: String
  let store: BeneficiaryStore
  let balanceStore: BalanceStore
  let preferencesStore: PreferencesStore
  let currencyRateStore: CurrencyRateStore
  let routeComposer: RouteComposer
  let aaExecutionService: AAExecutionService
  let accountService: AccountSetupService
  let ensService: ENSService
  var onBack: () -> Void = {}
  var onContinue: (SendMoneyDraft) -> Void = { _ in }
  @Environment(\.openURL) private var openURL

  init(
    eoaAddress: String,
    store: BeneficiaryStore,
    balanceStore: BalanceStore,
    preferencesStore: PreferencesStore,
    currencyRateStore: CurrencyRateStore,
    routeComposer: RouteComposer,
    aaExecutionService: AAExecutionService,
    accountService: AccountSetupService,
    ensService: ENSService,
    onBack: @escaping () -> Void = {},
    onContinue: @escaping (SendMoneyDraft) -> Void = { _ in }
  ) {
    self.eoaAddress = eoaAddress
    self.store = store
    self.balanceStore = balanceStore
    self.preferencesStore = preferencesStore
    self.currencyRateStore = currencyRateStore
    self.routeComposer = routeComposer
    self.aaExecutionService = aaExecutionService
    self.accountService = accountService
    self.ensService = ensService
    self.onBack = onBack
    self.onContinue = onContinue
  }

  @State private var beneficiaries: [Beneficiary] = []
  @State private var errorMessage: String?

  @State private var activeField: SendMoneyField?
  @State private var addressQuery = ""
  @State private var chainQuery = ""
  @State private var assetQuery = ""

  @State private var selectedBeneficiary: Beneficiary?
  @State private var selectedChain: ChainOption?
  @State private var selectedAsset: TokenBalance?
  @State private var finalizedAddressValue: String?

  @State private var isAddressInputFocused = false
  @State private var isChainInputFocused = false
  @State private var isAssetInputFocused = false
  @State private var addressDetectionTask: Task<Void, Never>?
  @State private var addressValidationState: AddressValidationState = .idle
  @State private var ensResolvedAddress: String?
  @State private var addressValidationTask: Task<Void, Never>?
  @State private var isShowingScanner = false
  @State private var step: SendMoneyStep = .recipient

  @State private var amountInput = ""
  @State private var isAmountDisplayInverted = false
  @State private var selectedSpendAsset: TokenBalance?
  @State private var isShowingSpendAssetPicker = false
  @State private var spendAssetQuery = ""
  @State private var amountButtonState: AppButtonVisualState = .normal
  @State private var amountActionTask: Task<Void, Never>?

  // Route resolution state
  @State private var currentRoute: TransferRoute?
  @State private var routeError: RouteError?
  @State private var isRoutingInProgress = false
  @State private var routeDebounceTask: Task<Void, Never>?
  @State private var txHash: String?

  // Haptic triggers
  @State private var keypadHapticTrigger = 0
  @State private var successHapticTrigger = 0
  @State private var errorHapticTrigger = 0
  @State private var selectionHapticTrigger = 0

  var body: some View {
    ZStack {
      AppThemeColor.backgroundPrimary.ignoresSafeArea()

      if step == .recipient {
        recipientStepContent
      } else if step == .amount {
        amountStepContent
      } else {
        successStepContent
      }

      if let errorMessage {
        toast(message: errorMessage)
          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
          .padding(.bottom, 28)
          .padding(.horizontal, AppSpacing.lg)
      }
    }
    .safeAreaInset(edge: .top, spacing: 0) {
      AppHeader(
        title: headerTitle,
        titleFont: .custom("Roboto-Bold", size: 22),
        titleColor: AppThemeColor.labelSecondary,
        onBack: handleHeaderBack
      )
    }
    .task {
      await reload()
      selectedSpendAsset = selectedAsset
      if step == .recipient {
        focusFirstIncompleteField()
      }
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
    .onChange(of: assetQuery) { _, newValue in
      guard activeField == .asset else { return }
      if let selectedAsset, selectedAsset.symbol != newValue {
        self.selectedAsset = nil
      }
    }
    .onChange(of: selectedAsset?.id) { _, _ in
      if step == .recipient {
        selectedSpendAsset = selectedAsset
      }
    }
    .onChange(of: amountInput) { _, _ in
      if step == .amount {
        resolveRoute()
      }
    }
    .onChange(of: selectedSpendAsset?.id) { _, _ in
      if step == .amount {
        resolveRoute()
      }
    }
    .onDisappear {
      addressDetectionTask?.cancel()
      amountActionTask?.cancel()
      routeDebounceTask?.cancel()
    }
    .fullScreenCover(isPresented: $isShowingScanner) {
      SendMoneyScanView(
        onDismiss: {
          isShowingScanner = false
        },
        onCodeScanned: handleScannedCode
      )
    }
    .sheet(isPresented: $isShowingSpendAssetPicker) {
      AppSheet(kind: .full) {
        spendAssetModal
      }
    }
    .sensoryFeedback(AppHaptic.selection.sensoryFeedback, trigger: keypadHapticTrigger) { _, _ in
      preferencesStore.hapticsEnabled
    }
    .sensoryFeedback(AppHaptic.selection.sensoryFeedback, trigger: selectionHapticTrigger) { _, _ in
      preferencesStore.hapticsEnabled
    }
    .sensoryFeedback(AppHaptic.success.sensoryFeedback, trigger: successHapticTrigger) { _, _ in
      preferencesStore.hapticsEnabled
    }
    .sensoryFeedback(AppHaptic.error.sensoryFeedback, trigger: errorHapticTrigger) { _, _ in
      preferencesStore.hapticsEnabled
    }
  }

  private var recipientStepContent: some View {
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

  private var headerTitle: LocalizedStringKey {
    switch step {
    case .recipient:
      return "send_money_title"
    case .amount:
      return "send_money_enter_amount_title"
    case .success:
      return ""
    }
  }

  private var amountStepContent: some View {
    GeometryReader { proxy in

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
          }
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
            }
          )
        }

        SendMoneyNumericKeypad(
          height: 332,
          rowSpacing: 36
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

  private var successStepContent: some View {
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

  private var addressInputField: some View {
    DropdownInputField(
      variant: .address,
      properties: .init(
        label: "send_money_to_label",
        placeholder: "send_money_address_placeholder",
        trailingIconAssetName: nil,
        textColor: AppThemeColor.labelPrimary,
        placeholderColor: AppThemeColor.labelSecondary
      ),
      query: $addressQuery,
      badge: addressBadge,
      isExpanded: expandedBinding(for: .address),
      isFocused: $isAddressInputFocused,
      showsTrailingIcon: addressBadge == nil,
      onExpandRequest: { activate(.address) },
      onBadgeTap: clearAddressSelectionAndStartEditing,
      onTrailingIconTap: presentScanner
    ) {
      addressDropdown
    }
  }

  private var chainInputField: some View {
    DropdownInputField(
      variant: .chain,
      properties: .init(
        label: "send_money_chain_label",
        placeholder: "send_money_chain_placeholder",
        trailingIconAssetName: nil,
        textColor: AppThemeColor.labelPrimary,
        placeholderColor: AppThemeColor.labelSecondary
      ),
      query: $chainQuery,
      badge: chainBadge,
      isExpanded: expandedBinding(for: .chain),
      isFocused: $isChainInputFocused,
      showsTrailingIcon: false,
      onExpandRequest: { activate(.chain) },
      onBadgeTap: clearChainSelectionAndStartEditing
    ) {
      chainDropdown
    }
  }

  private var assetInputField: some View {
    DropdownInputField(
      variant: .asset,
      properties: .init(
        label: "send_money_asset_label",
        placeholder: "send_money_asset_placeholder",
        trailingIconAssetName: nil,
        textColor: AppThemeColor.labelPrimary,
        placeholderColor: AppThemeColor.labelSecondary
      ),
      query: $assetQuery,
      badge: assetBadge,
      isExpanded: expandedBinding(for: .asset),
      isFocused: $isAssetInputFocused,
      showsTrailingIcon: false,
      onExpandRequest: { activate(.asset) },
      onBadgeTap: clearAssetSelectionAndStartEditing
    ) {
      assetDropdown
    }
  }

  private var continueButton: some View {
    AppButton(label: "send_money_continue", variant: .default) {
      proceedToAmountStep()
    }
    .disabled(!canContinue)
    .opacity(canContinue ? 1 : 0)
    .animation(AppAnimation.standard, value: canContinue)
  }

  private var amountActionButton: some View {
    AppButton(
      label: amountButtonLabel,
      variant: amountButtonVariant,
      visualState: amountButtonState,
      showIcon: amountButtonShowsIcon,
      iconName: amountButtonIconName,
      iconSize: 16
    ) {
      confirmAmount()
    }
    .disabled(!canAttemptAmountAction)
    .opacity(amountActionButtonOpacity)
    .animation(AppAnimation.standard, value: canAttemptAmountAction)
    .animation(AppAnimation.standard, value: amountButtonState)
  }

  private var spendAssetModal: some View {
    VStack(alignment: .leading, spacing: 0) {
      SearchInput(text: $spendAssetQuery, placeholderKey: "search_placeholder", width: nil)
        .padding(.horizontal, AppSpacing.lg)
        .padding(.top, 13)
        .padding(.bottom, 21)

      Rectangle()
        .fill(AppThemeColor.separatorOpaque)
        .frame(height: 4)

      ScrollView(showsIndicators: false) {
        AssetList(
          query: spendAssetQuery,
          state: .loaded(balanceStore.balances),
          displayCurrencyCode: preferencesStore.selectedCurrencyCode,
          displayLocale: preferencesStore.locale,
          usdToSelectedRate: selectedFiatRateFromUSD,
          showSectionLabels: true
        ) { asset in
          selectedSpendAsset = asset
          spendAssetQuery = ""
          isShowingSpendAssetPicker = false
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, 28)
      }
      .padding(.horizontal, AppSpacing.lg)
      .padding(.top, AppSpacing.xl)
      .padding(.bottom, AppSpacing.xl)
    }
  }

  private var addressDropdown: some View {
    Group {
      if filteredBeneficiaries.isEmpty {
        Text("send_money_no_beneficiaries_found")
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
      }
    }
  }

  private var chainDropdown: some View {
    ChainList(query: chainQuery) { chain in
      selectionHapticTrigger += 1
      selectedChain = chain
      chainQuery = ""
      focusFirstIncompleteField()
    }
  }

  private var assetDropdown: some View {
    ScrollView(showsIndicators: false) {
      AssetList(
        query: assetQuery,
        state: .loaded(balanceStore.balances),
        displayCurrencyCode: preferencesStore.selectedCurrencyCode,
        displayLocale: preferencesStore.locale,
        usdToSelectedRate: selectedFiatRateFromUSD,
        showSectionLabels: true
      ) {
        asset in
        selectionHapticTrigger += 1
        selectedAsset = asset
        assetQuery = ""
        focusFirstIncompleteField()
      }
    }
    .frame(maxWidth: .infinity, alignment: .topLeading)
  }

  private var filteredBeneficiaries: [Beneficiary] {
    SearchSystem.filter(
      query: addressQuery,
      items: beneficiaries,
      toDocument: {
        SearchDocument(
          id: $0.id.uuidString,
          title: $0.name,
          keywords: [$0.address, $0.chainLabel ?? ""]
        )
      },
      itemID: { $0.id.uuidString }
    )
  }

  private var addressBadge: DropdownBadgeValue? {
    let rawValue = selectedBeneficiary?.address ?? finalizedAddressValue
    guard let rawValue, !rawValue.isEmpty else { return nil }
    return DropdownBadgeValue(
      text: displayAddressOrENS(rawValue),
      validationState: addressValidationState
    )
  }

  private var chainBadge: DropdownBadgeValue? {
    guard let selectedChain else { return nil }
    return DropdownBadgeValue(
      text: selectedChain.name,
      iconAssetName: selectedChain.assetName,
      iconStyle: .network
    )
  }

  private var assetBadge: DropdownBadgeValue? {
    guard let selectedAsset else { return nil }
    return DropdownBadgeValue(
      text: selectedAsset.symbol,
      iconURL: selectedAsset.logoURL,
      iconStyle: .network
    )
  }

  private var resolvedAddress: String? {
    if let selectedBeneficiary {
      return selectedBeneficiary.address.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // If ENS was resolved, use the resolved 0x address
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

  private var canContinue: Bool {
    guard addressValidationState == .valid else { return false }
    guard let resolvedAddress, !resolvedAddress.isEmpty else { return false }
    guard selectedChain != nil else { return false }
    return selectedAsset != nil
  }

  private var currentSpendAsset: TokenBalance? {
    selectedSpendAsset ?? selectedAsset
  }

  private var amountButtonLabel: LocalizedStringKey {
    switch amountButtonState {
    case .normal:
      return "send_money_confirm"
    case .loading:
      return "send_money_sending"
    case .error:
      return "send_money_failed"
    }
  }

  private var amountButtonVariant: AppButtonVariant {
    switch amountButtonState {
    case .normal:
      return .default
    case .loading:
      return .neutral
    case .error:
      return .destructive
    }
  }

  private var amountButtonShowsIcon: Bool {
    amountButtonState != .normal
  }

  private var amountButtonIconName: String? {
    switch amountButtonState {
    case .normal:
      return nil
    case .loading:
      return nil
    case .error:
      return "xmark.circle.fill"
    }
  }

  private var canAttemptAmountAction: Bool {
    enteredMainAmount > 0 && amountButtonState == .normal
  }

  private var amountActionButtonOpacity: Double {
    if amountButtonState != .normal {
      return 1
    }
    return enteredMainAmount > 0 ? 1 : 0.45
  }

  private var selectedFiatCode: String {
    preferencesStore.selectedCurrencyCode
  }

  private var selectedFiatRateFromUSD: Decimal {
    currencyRateStore.rateFromUSD(to: selectedFiatCode)
  }

  private var assetUSDPrice: Decimal {
    currentSpendAsset?.quoteRate ?? 1
  }

  private var enteredMainAmount: Decimal {
    decimal(from: amountInput) ?? 0
  }

  private var usdAmount: Decimal {
    if isAmountDisplayInverted {
      return enteredMainAmount * assetUSDPrice
    }
    guard selectedFiatRateFromUSD > 0 else {
      return enteredMainAmount
    }
    return currencyRateStore.convertSelectedToUSD(
      enteredMainAmount,
      currencyCode: selectedFiatCode
    )
  }

  private var assetAmount: Decimal {
    if isAmountDisplayInverted {
      return enteredMainAmount
    }
    guard assetUSDPrice > 0 else { return 0 }
    return usdAmount / assetUSDPrice
  }

  private var displayFiatAmount: Decimal {
    currencyRateStore.convertUSDToSelected(
      usdAmount,
      currencyCode: selectedFiatCode
    )
  }

  private var availableAssetBalance: Decimal {
    currentSpendAsset?.totalBalance ?? 0
  }

  private var isInsufficientBalance: Bool {
    assetAmount > availableAssetBalance && enteredMainAmount > 0
  }

  private var primaryAmountText: String {
    let value = isAmountDisplayInverted ? assetAmount : displayFiatAmount
    return format(value, minFractionDigits: 1, maxFractionDigits: 2)
  }

  private var primarySymbolText: String {
    if isAmountDisplayInverted {
      return currentSpendAsset!.symbol
    }
    return currencyRateStore.symbol(
      for: selectedFiatCode,
      locale: preferencesStore.locale
    )
  }

  private var secondaryAmountText: String {
    let value = isAmountDisplayInverted ? displayFiatAmount : assetAmount
    return format(value, minFractionDigits: 1, maxFractionDigits: 4)
  }

  private var secondarySymbolText: String {
    if isAmountDisplayInverted {
      return currencyRateStore.symbol(
        for: selectedFiatCode,
        locale: preferencesStore.locale
      )
    }
    return currentSpendAsset!.symbol
  }

  private var spendAssetBalanceText: String {
    guard let spendAsset = currentSpendAsset else { return "0" }
    return currencyRateStore.formatUSD(
      spendAsset.totalValueUSD,
      currencyCode: selectedFiatCode,
      locale: preferencesStore.locale
    )
  }

  private var amountHelperMessage: (text: String, color: Color)? {
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
      case .noRouteFound(let reason):
        return ("No route found: \(reason)", AppThemeColor.accentRed)
      case .quoteUnavailable(let provider, _):
        return ("\(provider) quote unavailable", AppThemeColor.accentRed)
      case .unsupportedChain:
        return ("Unsupported chain", AppThemeColor.accentRed)
      case .unsupportedAsset:
        return ("Unsupported asset", AppThemeColor.accentRed)
      }
    }

    if let route = currentRoute {
      let amountText = format(route.estimatedAmountOut, minFractionDigits: 1, maxFractionDigits: 4)
      let stepsDescription = route.steps.map { step in
        switch step.action {
        case .transfer: return "transfer"
        case .swap: return "swap"
        case .bridge: return "bridge"
        case .accumulate: return "bridge"
        }
      }.joined(separator: " → ")
      let summary = String(
        localized: "send_money_swap_summary_format",
        defaultValue:
          "Will \(stepsDescription). recipient gets \(amountText) \(route.estimatedAmountOutSymbol)"
      )
      return (summary, AppThemeColor.accentBrown)
    }

    return nil
  }

  private func expandedBinding(for field: SendMoneyField) -> Binding<Bool> {
    Binding(
      get: { activeField == field },
      set: { isExpanded in
        if isExpanded {
          activate(field)
        } else if activeField == field {
          collapseAllFields()
        }
      }
    )
  }

  private func activate(_ field: SendMoneyField) {
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

  private func collapseAllFields() {
    if activeField == .address {
      finalizeAddressIfNeeded()
    }

    activeField = nil
    isAddressInputFocused = false
    isChainInputFocused = false
    isAssetInputFocused = false
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

  private func clearAssetSelectionAndStartEditing() {
    selectedAsset = nil
    assetQuery = ""
    activate(.asset)
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

    if assetBadge == nil {
      activate(.asset)
      return
    }

    activeField = nil
    isAddressInputFocused = false
    isChainInputFocused = false
    isAssetInputFocused = false
  }

  private func handleAddressQueryDidChange(_ newValue: String) {
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
  private func applyAddressDetectionResult(
    _ detection: AddressDetectionResult,
    sourceInput: String
  ) {
    let current = addressQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    guard current == sourceInput else { return }
    guard selectedBeneficiary == nil else { return }

    switch detection {
    case .evmAddress(let address):
      finalizedAddressValue = address
      selectedBeneficiary = nil
      addressQuery = ""
      validateAddress(address)
      focusFirstIncompleteField()
    case .ensName(let ensName):
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

  private func isAddressInputValid(_ input: String) -> Bool {
    AddressInputParser.isLikelyEVMAddress(input) || AddressInputParser.isLikelyENSName(input)
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
  private func reload() async {
    do {
      beneficiaries = try store.list(eoaAddress: eoaAddress)
    } catch {
      showError(error)
    }
  }

  @MainActor
  private func showError(_ error: Error) {
    errorMessage = error.localizedDescription
    Task { @MainActor in
      try? await Task.sleep(for: .seconds(2.5))
      if errorMessage == error.localizedDescription {
        errorMessage = nil
      }
    }
  }

  private func presentScanner() {
    collapseAllFields()
    isShowingScanner = true
  }

  private func handleHeaderBack() {
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
        step = .recipient
      }
      return
    }

    onBack()
  }

  @MainActor
  private func handleScannedCode(_ rawCode: String) -> Bool {
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

  private func proceedToAmountStep() {
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
        assetSymbol: selectedAsset.symbol
      )
    )

    selectedSpendAsset = selectedAsset
    amountInput = ""
    isAmountDisplayInverted = false
    amountButtonState = .normal
    withAnimation(AppAnimation.standard) {
      step = .amount
    }
  }

  private func confirmAmount() {
    guard canAttemptAmountAction else { return }
    amountActionTask?.cancel()

    if isInsufficientBalance {
      amountButtonState = .error
      amountActionTask = Task { @MainActor in
        try? await Task.sleep(for: .milliseconds(1100))
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
        let account = try await accountService.restoreSession(eoaAddress: eoaAddress)

        if route.jobId != nil {
          let result = try await aaExecutionService.executeChainCalls(
            accountService: accountService,
            account: account,
            destinationChainId: route.destinationChainId,
            chainCalls: route.chainCalls
          )
          txHash = result.destinationSubmission
        } else {
          guard let singleBundle = route.chainCalls.first else { return }
          let hash = try await aaExecutionService.executeCalls(
            accountService: accountService,
            account: account,
            chainId: singleBundle.chainId,
            calls: singleBundle.calls
          )
          txHash = hash
        }

        amountButtonState = .normal
        successHapticTrigger += 1
        withAnimation(AppAnimation.gentle) {
          step = .success
        }
      } catch {
        amountButtonState = .error
        errorHapticTrigger += 1
        errorMessage = error.localizedDescription
        amountActionTask = Task { @MainActor in
          try? await Task.sleep(for: .milliseconds(2000))
          amountButtonState = .normal
          errorMessage = nil
        }
      }
    }
  }

  /// Debounced route resolution triggered when amount/asset/chain changes.
  private func resolveRoute() {
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
      // Debounce: wait for input to stabilize
      try? await Task.sleep(for: .milliseconds(500))
      guard !Task.isCancelled else { return }

      do {
        // Compute accumulator address
        let smartAccountClient = SmartAccountClient()
        let accAddress = try? await smartAccountClient.computeAccumulatorAddress(
          account: eoaAddress,
          chainId: selectedChain.rpcChainID
        )

        guard !Task.isCancelled else { return }

        let route = try await routeComposer.getRoute(
          fromAddress: eoaAddress,
          toAddress: toAddress,
          sourceAsset: spendAsset,
          destChainId: selectedChain.rpcChainID,
          destToken: destToken,
          destTokenSymbol: destTokenSymbol,
          destTokenDecimals: destTokenDecimals,
          amount: assetAmount,
          accumulatorAddress: accAddress
        )

        guard !Task.isCancelled else { return }
        currentRoute = route
        routeError = nil
      } catch let error as RouteError {
        guard !Task.isCancelled else { return }
        routeError = error
        currentRoute = nil
      } catch {
        guard !Task.isCancelled else { return }
        routeError = .noRouteFound(reason: error.localizedDescription)
        currentRoute = nil
      }

      isRoutingInProgress = false
    }
  }

  private func repeatTransfer() {
    withAnimation(AppAnimation.standard) {
      step = .recipient
    }
  }

  private func openSuccessExplorerURL() {
    guard
      let chainId = selectedChainExplorerChainId,
      let address = resolvedAddress,
      let url = BlockExplorer.addressURL(chainId: chainId, address: address)
    else {
      return
    }
    openURL(url, prefersInApp: true)
  }

  private var selectedChainExplorerChainId: UInt64? {
    selectedChain?.rpcChainID
  }

  private func handleKeypadTap(_ key: SendMoneyKeypadKey) {
    guard amountButtonState == .normal else { return }
    keypadHapticTrigger += 1
    switch key {
    case .digit(let digit):
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

  private func decimal(from input: String) -> Decimal? {
    let sanitized = input.trimmingCharacters(in: .whitespacesAndNewlines)
      .replacingOccurrences(of: ",", with: "")
    guard !sanitized.isEmpty else { return 0 }
    return Decimal(string: sanitized)
  }

  private func format(
    _ value: Decimal,
    minFractionDigits: Int,
    maxFractionDigits: Int
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

  private func toast(message: String) -> some View {
    ToastView(message: message)
  }
}

#Preview {
  SendMoneyView(
    eoaAddress: "0xF5bB7F874D8e3f41821175c0Aa9910d30d10e193",
    store: BeneficiaryStore(),
    balanceStore: BalanceStore(),
    preferencesStore: PreferencesStore(),
    currencyRateStore: CurrencyRateStore(),
    routeComposer: RouteComposer(),
    aaExecutionService: AAExecutionService(),
    accountService: AccountSetupService(),
    ensService: ENSService()
  )
}
