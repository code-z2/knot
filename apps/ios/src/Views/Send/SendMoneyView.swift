import RPC
import SwiftUI
import UIKit

private enum SendMoneyField: Hashable {
  case address
  case chain
  case asset
}

private enum SendMoneyStep: Hashable {
  case recipient
  case amount
  case success
}

struct SendMoneyDraft: Sendable {
  let toAddressOrENS: String
  let chainID: String
  let chainName: String
  let assetID: String
  let assetSymbol: String
}

struct SendMoneyView: View {
  let eoaAddress: String
  let store: BeneficiaryStore
  let preferencesStore: PreferencesStore
  let currencyRateStore: CurrencyRateStore
  var onBack: () -> Void = {}
  var onContinue: (SendMoneyDraft) -> Void = { _ in }
  @Environment(\.openURL) private var openURL

  init(
    eoaAddress: String,
    store: BeneficiaryStore,
    preferencesStore: PreferencesStore,
    currencyRateStore: CurrencyRateStore,
    onBack: @escaping () -> Void = {},
    onContinue: @escaping (SendMoneyDraft) -> Void = { _ in }
  ) {
    self.eoaAddress = eoaAddress
    self.store = store
    self.preferencesStore = preferencesStore
    self.currencyRateStore = currencyRateStore
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
  @State private var selectedAsset: MockAsset?
  @State private var finalizedAddressValue: String?

  @State private var isAddressInputFocused = false
  @State private var isChainInputFocused = false
  @State private var isAssetInputFocused = false
  @State private var addressDetectionTask: Task<Void, Never>?
  @State private var isShowingScanner = false
  @State private var step: SendMoneyStep = .recipient

  @State private var amountInput = ""
  @State private var isAmountDisplayInverted = false
  @State private var selectedSpendAsset: MockAsset?
  @State private var isShowingSpendAssetPicker = false
  @State private var spendAssetQuery = ""
  @State private var amountButtonState: AppButtonVisualState = .normal
  @State private var amountActionTask: Task<Void, Never>?

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
          .padding(.horizontal, 20)
      }
    }
    .safeAreaInset(edge: .top, spacing: 0) {
      AppHeader(
        title: headerTitle,
        titleFont: .custom("Inter-Regular_Bold", size: 22),
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
    .onDisappear {
      addressDetectionTask?.cancel()
      amountActionTask?.cancel()
    }
    .fullScreenCover(isPresented: $isShowingScanner) {
      SendMoneyScanView(
        onDismiss: {
          isShowingScanner = false
        },
        onCodeScanned: handleScannedCode
      )
    }
    .overlay(alignment: .bottom) {
      SlideModal(
        isPresented: isShowingSpendAssetPicker,
        kind: .fullHeight(topInset: 12),
        onDismiss: { isShowingSpendAssetPicker = false }
      ) {
        spendAssetModal
      }
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
            withAnimation(.easeInOut(duration: 0.18)) {
              isAmountDisplayInverted.toggle()
            }
          }
        )
        .padding(.top, 42)
        .padding(.bottom, 16)

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
        .padding(.bottom, 24)

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
          MetuSuccessCheckmark()
            .frame(width: 127, height: 123)

          VStack(spacing: 24) {
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

        HStack(spacing: 12) {
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
    .animation(.easeInOut(duration: 0.18), value: canContinue)
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
    .animation(.easeInOut(duration: 0.18), value: canAttemptAmountAction)
    .animation(.easeInOut(duration: 0.18), value: amountButtonState)
  }

  private var spendAssetModal: some View {
    VStack(alignment: .leading, spacing: 0) {
      SearchInput(text: $spendAssetQuery, placeholderKey: "search_placeholder", width: nil)
        .padding(.horizontal, 20)
        .padding(.top, 13)
        .padding(.bottom, 21)

      Rectangle()
        .fill(AppThemeColor.separatorOpaque)
        .frame(height: 4)

      ScrollView(showsIndicators: false) {
        AssetList(
          query: spendAssetQuery,
          state: .loaded(MockAssetData.portfolio),
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
      .padding(.horizontal, 20)
      .padding(.top, 24)
      .padding(.bottom, 24)
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
                selectedBeneficiary = beneficiary
                finalizedAddressValue = beneficiary.address
                addressQuery = ""
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
      selectedChain = chain
      chainQuery = ""
      focusFirstIncompleteField()
    }
  }

  private var assetDropdown: some View {
    ScrollView(showsIndicators: false) {
      AssetList(
        query: assetQuery,
        state: .loaded(MockAssetData.portfolio),
        displayCurrencyCode: preferencesStore.selectedCurrencyCode,
        displayLocale: preferencesStore.locale,
        usdToSelectedRate: selectedFiatRateFromUSD,
        showSectionLabels: true
      ) {
        asset in
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
    return DropdownBadgeValue(text: displayAddressOrENS(rawValue))
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
      iconAssetName: selectedAsset.iconAssetName,
      iconStyle: .network
    )
  }

  private var resolvedAddress: String? {
    if let selectedBeneficiary {
      return selectedBeneficiary.address.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    if let finalizedAddressValue {
      return finalizedAddressValue.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    let candidate = addressQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !candidate.isEmpty else { return nil }
    guard isAddressInputValid(candidate) else { return nil }
    return candidate
  }

  private var canContinue: Bool {
    guard let resolvedAddress, !resolvedAddress.isEmpty else { return false }
    guard selectedChain != nil else { return false }
    return selectedAsset != nil
  }

  private var currentSpendAsset: MockAsset? {
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
      return "Icons/x_close"
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
    guard let assetID = currentSpendAsset?.id else { return 1 }
    switch assetID {
    case "usdc", "usdt":
      return 1
    case "eth":
      return 3200
    case "bnb":
      return 600
    case "btc":
      return 64000
    default:
      return 1
    }
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
    guard let amountText = currentSpendAsset?.amountText else { return 0 }
    return decimal(from: amountText) ?? 0
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
      return currentSpendAsset?.symbol ?? "USDC"
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
    return currentSpendAsset?.symbol ?? "USDC"
  }

  private var spendAssetBalanceText: String {
    guard let spendAsset = currentSpendAsset else { return "0" }
    let assetBalance = decimal(from: spendAsset.amountText) ?? 0
    let balanceUSD = assetBalance * usdRate(for: spendAsset)
    return currencyRateStore.formatUSD(
      balanceUSD,
      currencyCode: selectedFiatCode,
      locale: preferencesStore.locale
    )
  }

  private var amountHelperMessage: (text: String, color: Color)? {
    if isInsufficientBalance {
      return (String(localized: "send_money_insufficient_balance"), AppThemeColor.accentRed)
    }

    guard enteredMainAmount > 0 else { return nil }
    guard
      let selectedAsset,
      let spendAsset = currentSpendAsset,
      selectedAsset.id != spendAsset.id
    else {
      return nil
    }

    let recipientRate = usdRate(for: selectedAsset)
    guard recipientRate > 0 else { return nil }
    let recipientAmount = usdAmount / recipientRate
    let amountText = format(recipientAmount, minFractionDigits: 1, maxFractionDigits: 2)
    let summary = "Will swap on LiFi. recipient gets \(amountText) \(selectedAsset.symbol)"
    return (summary, AppThemeColor.accentBrown)
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
    }

    addressDetectionTask?.cancel()

    guard !trimmed.isEmpty else { return }

    let snapshot = trimmed
    addressDetectionTask = Task(priority: .userInitiated) {
      let detection = await Task.detached(priority: .userInitiated) {
        AddressInputParser.detectCandidate(snapshot)
      }.value

      guard !Task.isCancelled else { return }

      await MainActor.run {
        applyAddressDetectionResult(detection, sourceInput: snapshot)
      }
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
      focusFirstIncompleteField()
    case .ensName(let ensName):
      finalizedAddressValue = ensName
      selectedBeneficiary = nil
      addressQuery = ""
      focusFirstIncompleteField()
    case .invalid:
      finalizedAddressValue = nil
    }
  }

  private func finalizeAddressIfNeeded() {
    if let selectedBeneficiary {
      finalizedAddressValue = selectedBeneficiary.address
      return
    }

    let candidate = addressQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !candidate.isEmpty else { return }

    finalizedAddressValue = isAddressInputValid(candidate) ? candidate : nil
  }

  private func isAddressInputValid(_ input: String) -> Bool {
    AddressInputParser.isLikelyEVMAddress(input) || AddressInputParser.isLikelyENSName(input)
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
      withAnimation(.easeInOut(duration: 0.18)) {
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
        chainID: selectedChain.id,
        chainName: selectedChain.name,
        assetID: selectedAsset.id,
        assetSymbol: selectedAsset.symbol
      )
    )

    selectedSpendAsset = selectedAsset
    amountInput = ""
    isAmountDisplayInverted = false
    amountButtonState = .normal
    withAnimation(.easeInOut(duration: 0.18)) {
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

    amountButtonState = .loading
    amountActionTask = Task { @MainActor in
      try? await Task.sleep(for: .milliseconds(1200))
      amountButtonState = .normal
      withAnimation(.easeInOut(duration: 0.20)) {
        step = .success
      }
    }
  }

  private func repeatTransfer() {
    withAnimation(.easeInOut(duration: 0.18)) {
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
    guard let chainId = selectedChain?.id else { return nil }
    switch chainId {
    case "ethereum":
      return 1
    case "sepolia":
      return 11_155_111
    case "base":
      return 8453
    case "base-sepolia":
      return 84532
    case "arbitrum":
      return 42161
    case "optimism":
      return 10
    case "polygon":
      return 137
    case "bnb-smart-chain":
      return 56
    default:
      return nil
    }
  }

  private func handleKeypadTap(_ key: SendMoneyKeypadKey) {
    guard amountButtonState == .normal else { return }
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
    let formatter = NumberFormatter()
    formatter.locale = Locale.current
    formatter.numberStyle = .decimal
    formatter.minimumFractionDigits = minFractionDigits
    formatter.maximumFractionDigits = maxFractionDigits
    return formatter.string(from: value as NSDecimalNumber) ?? "0.0"
  }

  private func usdRate(for asset: MockAsset) -> Decimal {
    switch asset.id {
    case "usdc", "usdt":
      return 1
    case "eth":
      return 3200
    case "bnb":
      return 600
    case "btc":
      return 64000
    default:
      return 1
    }
  }

  private func toast(message: String) -> some View {
    Text(message)
      .font(.custom("RobotoMono-Medium", size: 12))
      .foregroundStyle(AppThemeColor.labelPrimary)
      .padding(.horizontal, 14)
      .padding(.vertical, 10)
      .background(
        RoundedRectangle(cornerRadius: 12, style: .continuous)
          .fill(AppThemeColor.fillPrimary)
      )
  }
}

private struct MetuSuccessCheckmark: View {
  var body: some View {
    GeometryReader { proxy in
      Image("LogoMark")
        .renderingMode(.template)
        .resizable()
        .aspectRatio(127.0 / 123.0, contentMode: .fit)
        .foregroundStyle(AppThemeColor.accentGreen)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .mask(alignment: .bottomTrailing) {
          Rectangle()
            .frame(
              width: proxy.size.width * 0.76,
              height: proxy.size.height * 0.62
            )
            .offset(
              x: proxy.size.width * 0.04,
              y: proxy.size.height * 0.07
            )
        }
    }
  }
}

private struct SendMoneyScanView: View {
  let onDismiss: () -> Void
  let onCodeScanned: (String) -> Bool

  @StateObject private var scanner = QRScannerController()
  @State private var dragOffset: CGFloat = 0
  @Environment(\.openURL) private var openURL

  var body: some View {
    ZStack {
      QRCodeScannerPreview(session: scanner.session)
        .ignoresSafeArea()

      Color.black.opacity(0.22)
        .ignoresSafeArea()

      ScannerCrosshair()
        .frame(width: 244, height: 244)

      VStack {
        Spacer()
        flashlightButton
          .padding(.bottom, 116)
      }

      if let error = scanner.error {
        scannerErrorOverlay(error)
          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
          .padding(.horizontal, 20)
          .padding(.bottom, 170)
      }
    }
    .ignoresSafeArea()
    .offset(y: dragOffset)
    .gesture(dragToDismissGesture)
    .accessibilityElement(children: .contain)
    .onAppear {
      scanner.onCodeDetected = { payload in
        let accepted = onCodeScanned(payload)
        if accepted {
          onDismiss()
        }
        return accepted
      }
      scanner.start()
    }
    .onDisappear {
      scanner.stop()
    }
  }

  private var flashlightButton: some View {
    Button {
      scanner.toggleTorch()
    } label: {
      ZStack {
        Circle()
          .fill(AppThemeColor.grayBlack.opacity(0.42))
          .overlay(
            Circle()
              .stroke(AppThemeColor.grayWhite.opacity(0.24), lineWidth: 1)
          )
          .background(
            Circle()
              .fill(.ultraThinMaterial)
          )

        Image(systemName: scanner.isTorchEnabled ? "flashlight.on.fill" : "flashlight.off.fill")
          .font(.system(size: 19, weight: .semibold))
          .foregroundStyle(Color(hex: "#BFBFBF"))
      }
      .frame(width: 48, height: 48)
    }
    .buttonStyle(.plain)
    .accessibilityLabel(Text("send_money_scanner_toggle_flashlight"))
  }

  @ViewBuilder
  private func scannerErrorOverlay(_ error: QRScannerError) -> some View {
    VStack(spacing: 10) {
      Text(errorTitle(error))
        .font(.custom("Roboto-Bold", size: 14))
        .foregroundStyle(AppThemeColor.labelPrimary)

      Text(errorSubtitle(error))
        .font(.custom("Roboto-Regular", size: 12))
        .foregroundStyle(AppThemeColor.labelSecondary)
        .multilineTextAlignment(.center)

      if error == .permissionDenied {
        Button("send_money_open_settings") {
          guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
          openURL(url, prefersInApp: true)
        }
        .font(.custom("Roboto-Bold", size: 13))
        .foregroundStyle(AppThemeColor.labelPrimary)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
          RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(AppThemeColor.fillPrimary)
        )
      }
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 12)
    .background(
      RoundedRectangle(cornerRadius: 12, style: .continuous)
        .fill(AppThemeColor.grayBlack.opacity(0.62))
    )
  }

  private func errorTitle(_ error: QRScannerError) -> String {
    switch error {
    case .permissionDenied:
      return String(localized: "send_money_scanner_camera_access_needed")
    case .unavailable:
      return String(localized: "send_money_scanner_camera_unavailable")
    case .configurationFailed:
      return String(localized: "send_money_scanner_unavailable")
    }
  }

  private func errorSubtitle(_ error: QRScannerError) -> String {
    switch error {
    case .permissionDenied:
      return String(localized: "send_money_scanner_permission_subtitle")
    case .unavailable:
      return String(localized: "send_money_scanner_unavailable_subtitle")
    case .configurationFailed:
      return String(localized: "send_money_scanner_config_subtitle")
    }
  }

  private var dragToDismissGesture: some Gesture {
    DragGesture(minimumDistance: 6)
      .onChanged { value in
        dragOffset = max(0, value.translation.height)
      }
      .onEnded { value in
        let shouldDismiss = dragOffset > 110 || value.predictedEndTranslation.height > 180
        if shouldDismiss {
          withAnimation(.spring(response: 0.36, dampingFraction: 0.92)) {
            dragOffset = 0
            onDismiss()
          }
        } else {
          withAnimation(.spring(response: 0.30, dampingFraction: 0.90)) {
            dragOffset = 0
          }
        }
      }
  }
}

private struct ScannerCrosshair: View {
  var body: some View {
    ZStack {
      corner(x: -90, y: -90, rotation: .degrees(0))
      corner(x: 90, y: -90, rotation: .degrees(90))
      corner(x: 90, y: 90, rotation: .degrees(180))
      corner(x: -90, y: 90, rotation: .degrees(270))
    }
  }

  private func corner(x: CGFloat, y: CGFloat, rotation: Angle) -> some View {
    RoundedCornerArc()
      .stroke(style: StrokeStyle(lineWidth: 9, lineCap: .round, lineJoin: .round))
      .foregroundStyle(AppThemeColor.grayWhite)
      .frame(width: 58, height: 58)
      .rotationEffect(rotation)
      .offset(x: x, y: y)
  }
}

private struct RoundedCornerArc: Shape {
  func path(in rect: CGRect) -> Path {
    var path = Path()
    path.addArc(
      center: CGPoint(x: rect.maxX, y: rect.maxY),
      radius: rect.width,
      startAngle: .degrees(180),
      endAngle: .degrees(270),
      clockwise: false
    )
    return path
  }
}

#Preview {
  SendMoneyView(
    eoaAddress: "0xF5bB7F874D8e3f41821175c0Aa9910d30d10e193",
    store: BeneficiaryStore(),
    preferencesStore: PreferencesStore(),
    currencyRateStore: CurrencyRateStore()
  )
}
