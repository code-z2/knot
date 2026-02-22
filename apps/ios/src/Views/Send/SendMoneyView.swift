import Balance
import Compose
import ENS
import RPC
import SwiftUI
import Transactions

struct SendMoneyView: View {
    enum StepNavigationDirection {
        case forward
        case backward
    }

    let eoaAddress: String
    let accumulatorAddress: String
    let store: BeneficiaryStore
    let balanceStore: BalanceStore
    let preferencesStore: PreferencesStore
    let currencyRateStore: CurrencyRateStore
    let sendFlowService: SendFlowService
    let ensService: ENSService
    var onBack: () -> Void = {}
    var onContinue: (SendMoneyDraft) -> Void = { _ in }
    @Environment(\.openURL) var openURL

    init(
        eoaAddress: String,
        accumulatorAddress: String,
        store: BeneficiaryStore,
        balanceStore: BalanceStore,
        preferencesStore: PreferencesStore,
        currencyRateStore: CurrencyRateStore,
        sendFlowService: SendFlowService,
        ensService: ENSService,
        onBack: @escaping () -> Void = {},
        onContinue: @escaping (SendMoneyDraft) -> Void = { _ in },
    ) {
        self.eoaAddress = eoaAddress
        self.accumulatorAddress = accumulatorAddress
        self.store = store
        self.balanceStore = balanceStore
        self.preferencesStore = preferencesStore
        self.currencyRateStore = currencyRateStore
        self.sendFlowService = sendFlowService
        self.ensService = ensService
        self.onBack = onBack
        self.onContinue = onContinue
    }

    @State var beneficiaries: [Beneficiary] = []
    @State var errorMessage: String?

    @State var activeField: SendMoneyField?
    @State var addressQuery = ""
    @State var chainQuery = ""
    @State var assetQuery = ""

    @State var selectedBeneficiary: Beneficiary?
    @State var selectedChain: ChainOption?
    @State var selectedAsset: TokenBalanceModel?
    @State var finalizedAddressValue: String?

    @State var isAddressInputFocused = false
    @State var isChainInputFocused = false
    @State var isAssetInputFocused = false
    @State var addressDetectionTask: Task<Void, Never>?
    @State var addressValidationState: AddressValidationState = .idle
    @State var ensResolvedAddress: String?
    @State var addressValidationTask: Task<Void, Never>?
    @State var isShowingScanner = false
    @State var step: SendMoneyStep = .recipient
    @State var stepNavigationDirection: StepNavigationDirection = .forward

    @State var amountInput = ""
    @State var isAmountDisplayInverted = false
    @State var selectedSpendAsset: TokenBalanceModel?
    @State var isShowingSpendAssetPicker = false
    @State var spendAssetQuery = ""
    @State var amountButtonState: AppButtonVisualState = .normal
    @State var amountActionTask: Task<Void, Never>?

    // Route resolution state
    @State var currentRoute: TransferRouteModel?
    @State var routeError: RouteError?
    @State var isRoutingInProgress = false
    @State var routeDebounceTask: Task<Void, Never>?
    @State var errorResetTask: Task<Void, Never>?
    @State var txHash: String?
    @State var executionResult: SendExecutionResultModel?

    // Haptic triggers
    @State var keypadHapticTrigger = 0
    @State var successHapticTrigger = 0
    @State var errorHapticTrigger = 0
    @State var selectionHapticTrigger = 0

    var body: some View {
        contentWithInteractions
    }

    var baseContent: some View {
        ZStack {
            AppThemeColor.backgroundPrimary.ignoresSafeArea()

            activeStepContent

            if let errorMessage {
                toast(message: errorMessage)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, 28)
                    .padding(.horizontal, AppSpacing.lg)
            }
        }
        .animation(AppAnimation.standard, value: step)
        .animation(AppAnimation.spring, value: errorMessage)
        .safeAreaInset(edge: .top, spacing: 0) {
            AppHeader(
                title: headerTitle,
                titleFont: .custom("Roboto-Bold", size: 22),
                titleColor: AppThemeColor.labelSecondary,
                onBack: handleHeaderBack,
            )
        }
    }

    var contentWithInteractions: some View {
        contentWithHaptics
    }

    var contentWithTask: some View {
        baseContent
            .task {
                await reload()
                selectedSpendAsset = selectedAsset
                if step == .recipient {
                    focusFirstIncompleteField()
                }
            }
    }

    var contentWithRecipientObservers: some View {
        contentWithTask
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
    }

    var contentWithAmountObservers: some View {
        contentWithRecipientObservers
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
    }

    var contentWithLifecycle: some View {
        contentWithAmountObservers
            .onDisappear {
                addressDetectionTask?.cancel()
                addressValidationTask?.cancel()
                amountActionTask?.cancel()
                routeDebounceTask?.cancel()
                errorResetTask?.cancel()
                addressDetectionTask = nil
                addressValidationTask = nil
                amountActionTask = nil
                routeDebounceTask = nil
                errorResetTask = nil
            }
    }

    var contentWithPresentation: some View {
        contentWithLifecycle
            .fullScreenCover(isPresented: $isShowingScanner) {
                SendMoneyScanView(
                    onDismiss: {
                        isShowingScanner = false
                    },
                    onCodeScanned: handleScannedCode,
                )
            }
            .sheet(isPresented: $isShowingSpendAssetPicker) {
                AppSheet(kind: .full) {
                    spendAssetModal
                }
            }
    }

    var contentWithHaptics: some View {
        contentWithPresentation
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

    @ViewBuilder
    var activeStepContent: some View {
        if step == .recipient {
            recipientStepContent
                .transition(stepTransition)
        } else if step == .amount {
            amountStepContent
                .transition(stepTransition)
        } else {
            successStepContent
                .transition(stepTransition)
        }
    }
}

#Preview {
    SendMoneyView(
        eoaAddress: "0xF5bB7F874D8e3f41821175c0Aa9910d30d10e193",
        accumulatorAddress: "0x0abf3f4d31f17df16e654f8f0e8a0c9f1b2e3d4c",
        store: BeneficiaryStore(),
        balanceStore: BalanceStore(),
        preferencesStore: PreferencesStore(),
        currencyRateStore: CurrencyRateStore(),
        sendFlowService: SendFlowService(),
        ensService: ENSService(),
    )
}
