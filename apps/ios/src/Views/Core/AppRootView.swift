import AccountSetup
import Balance
import Compose
import RPC
import SwiftData
import SwiftUI
import Transactions

@MainActor
struct AppRootView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @State private var route: Route = .splash
    @State private var selectedMainTab: MainTab = .home
    @State private var tabChangeTrigger = 0
    @State private var currentEOA: String?
    @State private var currentAccumulatorAddress: String?
    @State private var onboardingAction: OnboardingAction?
    @State private var onboardingFailed = false
    @State private var hasLocalWalletMaterial = false
    @State private var walletBackupMnemonic = ""
    @State private var walletRefreshTask: Task<Void, Never>?
    @State private var currencyRateTask: Task<Void, Never>?
    @State private var preferencesStore = PreferencesStore()
    @State private var currencyRateStore = CurrencyRateStore()
    @State private var balanceStore = BalanceStore()
    @State private var transactionStore = TransactionStore()
    private let beneficiaryStore = BeneficiaryStore()
    private let appSessionFlowService: AppSessionFlowService
    private let walletDataFlowService: WalletDataFlowService
    @State private var ensService = ENSService(mode: ChainSupportRuntime.resolveMode())
    private let aaExecutionService: AAExecutionService
    private let sendFlowService: SendFlowService

    enum Route {
        case splash
        case onboarding
        case main
        case profile
        case preferences
        case addressBook
        case receive
        case sendMoney
        case walletBackup
    }

    enum MainTab: Hashable {
        case home
        case transactions
        case sessionKey
    }

    init() {
        let biometricAuth = BiometricAuthService()
        let sessionFlowService = AppSessionFlowService(biometricAuth: biometricAuth)
        let executionService = AAExecutionService(biometricAuth: biometricAuth)
        appSessionFlowService = sessionFlowService
        walletDataFlowService = WalletDataFlowService()
        aaExecutionService = executionService
        sendFlowService = SendFlowService(
            aaExecutionService: executionService,
            accountService: sessionFlowService.accountService,
        )
    }

    var body: some View {
        ZStack {
            routeContent
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.86), value: route)
        .preferredColorScheme(preferredColorScheme)
        .environment(\.locale, preferencesStore.locale)
        .environment(\.layoutDirection, layoutDirection)
        .task {
            await currencyRateStore.refreshIfNeeded()
            await currencyRateStore.ensureRate(for: preferencesStore.selectedCurrencyCode)
            scheduleWalletRefresh(useSilentRefresh: false)
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            currencyRateTask?.cancel()
            currencyRateTask = Task {
                await currencyRateStore.refreshIfNeeded()
                scheduleWalletRefresh(useSilentRefresh: false)
            }
        }
        .onChange(of: preferencesStore.selectedCurrencyCode) { _, newCode in
            currencyRateTask?.cancel()
            currencyRateTask = Task {
                await currencyRateStore.ensureRate(for: newCode)
            }
        }
        .onChange(of: selectedMainTab) { _, _ in tabChangeTrigger += 1 }
        .onChange(of: preferencesStore.chainSupportMode) { _, newMode in
            withAnimation(AppAnimation.gentle) {
                selectedMainTab = .home
            }
            ensService = ENSService(mode: newMode)
            guard let eoa = currentEOA else { return }
            restoreCachedWalletState(walletAddress: eoa)
            walletRefreshTask?.cancel()
            walletRefreshTask = Task {
                await refreshCurrentWalletData(useSilentRefresh: false)
                await appSessionFlowService.triggerFaucetIfNeeded(walletAddress: eoa, mode: newMode)
            }
        }
        .onDisappear {
            walletRefreshTask?.cancel()
            currencyRateTask?.cancel()
            walletRefreshTask = nil
            currencyRateTask = nil
        }
    }

    @ViewBuilder
    private var mainTabView: some View {
        if #available(iOS 26.0, *) {
            mainTabs
                .tabBarMinimizeBehavior(.onScrollDown)
        } else {
            mainTabs
        }
    }

    @ViewBuilder
    private var routeContent: some View {
        switch route {
        case .splash:
            SplashView()
                .task {
                    await handleSplash()
                }
        case .onboarding:
            OnboardingView(
                activeAction: onboardingAction,
                failed: onboardingFailed,
                onCreateWallet: { Task { await createAccountFromOnboarding() } },
                onLogin: { Task { await signInFromOnboarding() } },
            )
        case .main:
            mainTabView
        case .profile:
            ProfileView(
                eoaAddress: currentEOA ?? "0x0000000000000000000000000000000000000000",
                accountService: appSessionFlowService.accountService,
                ensService: ensService,
                aaExecutionService: aaExecutionService,
                onBack: { returnToMain() },
            )
            .transition(AppAnimation.slideTransition)
        case .preferences:
            PreferencesView(
                preferencesStore: preferencesStore,
                onBack: { returnToMain() },
            )
            .transition(AppAnimation.slideTransition)
        case .addressBook:
            AddressBookView(
                eoaAddress: currentEOA ?? "0x0000000000000000000000000000000000000000",
                store: beneficiaryStore,
                ensService: ensService,
                onBack: { returnToMain() },
            )
            .transition(AppAnimation.slideTransition)
        case .receive:
            ReceiveView(
                address: currentEOA ?? "0x0000000000000000000000000000000000000000",
                onBack: { returnToMain() },
            )
        case .sendMoney:
            if let accumulatorAddress = currentAccumulatorAddress {
                SendMoneyView(
                    eoaAddress: currentEOA ?? "0x0000000000000000000000000000000000000000",
                    accumulatorAddress: accumulatorAddress,
                    store: beneficiaryStore,
                    balanceStore: balanceStore,
                    preferencesStore: preferencesStore,
                    currencyRateStore: currencyRateStore,
                    sendFlowService: sendFlowService,
                    ensService: ensService,
                    onBack: { returnToMain() },
                )
            } else {
                Color.clear
                    .task {
                        let accumulatorAddress = await appSessionFlowService.resolveAccumulatorAddress(
                            eoaAddress: currentEOA,
                            fallbackAccumulatorAddress: currentAccumulatorAddress,
                        )

                        if let accumulatorAddress {
                            currentAccumulatorAddress = accumulatorAddress
                        } else {
                            returnToMain()
                        }
                    }
            }
        case .walletBackup:
            WalletBackupView(
                mnemonic: walletBackupMnemonic,
                onBack: { returnToMain() },
            )
            .transition(AppAnimation.slideTransition)
        }
    }

    private var mainTabs: some View {
        TabView(selection: $selectedMainTab) {
            Tab(value: MainTab.home) {
                HomeView(
                    balanceStore: balanceStore,
                    preferencesStore: preferencesStore,
                    currencyRateStore: currencyRateStore,
                    onSignOut: {
                        signOutAndNavigateToOnboarding()
                    },
                    onAddMoney: {
                        openReceive()
                    },
                    onSendMoney: {
                        openSendMoneyIfReady()
                    },
                    onProfileTap: {
                        openProfile()
                    },
                    onPreferencesTap: {
                        openPreferences()
                    },
                    onWalletBackupTap: { Task { await openWalletBackupIfAvailable() } },
                    onAddressBookTap: {
                        openAddressBook()
                    },
                    onRefreshWallet: {
                        await requestWalletRefresh(useSilentRefresh: true)
                    },
                    showWalletBackup: hasLocalWalletMaterial,
                )
            } label: {
                Label {
                    Text("bottom_nav_home")
                } icon: {
                    Image("Icons/home_02")
                        .renderingMode(.template)
                }
            }

            Tab(value: MainTab.transactions) {
                TransactionsView(
                    balanceStore: balanceStore,
                    transactionStore: transactionStore,
                    preferencesStore: preferencesStore,
                    currencyRateStore: currencyRateStore,
                )
            } label: {
                Label {
                    Text("bottom_nav_transactions")
                } icon: {
                    Image("Icons/receipt")
                        .renderingMode(.template)
                }
            }

//            Tab(value: MainTab.sessionKey) {
//                SessionKeyView()
//            } label: {
//                Label {
//                    Text("bottom_nav_session_key")
//                } icon: {
//                    Image("Icons/key_01")
//                        .renderingMode(.template)
//                }
//            }
        }
        .tint(AppThemeColor.accentBrown)
        .sensoryFeedback(AppHaptic.selection.sensoryFeedback, trigger: tabChangeTrigger) { _, _ in
            preferencesStore.hapticsEnabled
        }
    }

    @MainActor
    private func createAccountFromOnboarding() async {
        guard onboardingAction == nil else { return }
        onboardingAction = .createWallet
        onboardingFailed = false

        guard let sessionState = await appSessionFlowService.createWallet() else {
            await showOnboardingError()
            return
        }

        onboardingAction = nil
        applySessionState(sessionState)
        restoreCachedWalletState(walletAddress: sessionState.eoaAddress)
        selectedMainTab = .home
        route = .main

        await appSessionFlowService.triggerFaucetIfNeeded(
            walletAddress: sessionState.eoaAddress,
            mode: preferencesStore.chainSupportMode,
        )
        scheduleWalletRefresh(useSilentRefresh: false)
    }

    @MainActor
    private func signInFromOnboarding() async {
        guard onboardingAction == nil else { return }
        onboardingAction = .signIn
        onboardingFailed = false

        guard let sessionState = await appSessionFlowService.signIn() else {
            await showOnboardingError()
            return
        }

        onboardingAction = nil
        applySessionState(sessionState)
        restoreCachedWalletState(walletAddress: sessionState.eoaAddress)
        selectedMainTab = .home
        route = .main

        await appSessionFlowService.triggerFaucetIfNeeded(
            walletAddress: sessionState.eoaAddress,
            mode: preferencesStore.chainSupportMode,
        )
        scheduleWalletRefresh(useSilentRefresh: false)
    }

    @MainActor
    private func showOnboardingError() async {
        onboardingFailed = true
        try? await Task.sleep(for: .seconds(1.5))
        onboardingAction = nil
        onboardingFailed = false
    }

    @MainActor
    private func openWalletBackupIfAvailable() async {
        guard let mnemonic = await appSessionFlowService.backupMnemonicIfAvailable(
            eoaAddress: currentEOA,
            hasLocalWalletMaterial: hasLocalWalletMaterial,
        ) else {
            return
        }
        walletBackupMnemonic = mnemonic
        route = .walletBackup
    }

    private var layoutDirection: LayoutDirection {
        Locale.Language(identifier: preferencesStore.languageCode).characterDirection == .rightToLeft
            ? .rightToLeft
            : .leftToRight
    }

    private var preferredColorScheme: ColorScheme? {
        switch route {
        case .splash, .onboarding:
            .dark
        default:
            switch preferencesStore.appearance {
            case .dark:
                .dark
            case .light:
                .light
            case .system:
                nil
            }
        }
    }

    private func refreshCurrentWalletData(useSilentRefresh: Bool) async {
        guard let walletAddress = currentEOA else { return }

        guard let accumulatorAddress = await walletDataFlowService.refresh(
            walletAddress: walletAddress,
            fallbackAccumulatorAddress: currentAccumulatorAddress,
            appSessionFlowService: appSessionFlowService,
            balanceStore: balanceStore,
            transactionStore: transactionStore,
            useSilentRefresh: useSilentRefresh,
        ) else {
            return
        }

        currentAccumulatorAddress = accumulatorAddress
        persistCachedWalletState(walletAddress: walletAddress)
    }

    private func scheduleWalletRefresh(useSilentRefresh: Bool) {
        walletRefreshTask?.cancel()
        walletRefreshTask = Task {
            await refreshCurrentWalletData(useSilentRefresh: useSilentRefresh)
        }
    }

    private func requestWalletRefresh(useSilentRefresh: Bool) async {
        walletRefreshTask?.cancel()
        let task = Task {
            await refreshCurrentWalletData(useSilentRefresh: useSilentRefresh)
        }
        walletRefreshTask = task
        await task.value
    }

    private func handleSplash() async {
        do {
            try await Task.sleep(for: .seconds(1.2))
        } catch {
            return
        }

        switch await appSessionFlowService.bootstrap() {
        case .onboarding:
            currentEOA = nil
            currentAccumulatorAddress = nil
            hasLocalWalletMaterial = false
            withAnimation(AppAnimation.standard) {
                route = .onboarding
            }
        case let .activeSession(sessionState):
            applySessionState(sessionState)
            restoreCachedWalletState(walletAddress: sessionState.eoaAddress)
            withAnimation(AppAnimation.standard) {
                selectedMainTab = .home
                route = .main
            }
            scheduleWalletRefresh(useSilentRefresh: false)
        }
    }

    private func applySessionState(_ sessionState: AppSessionStateModel) {
        currentEOA = sessionState.eoaAddress
        currentAccumulatorAddress = sessionState.accumulatorAddress
        hasLocalWalletMaterial = sessionState.hasLocalWalletMaterial
    }

    private func returnToMain() {
        withAnimation(AppAnimation.standard) {
            selectedMainTab = .home
            route = .main
        }
    }

    private func signOutAndNavigateToOnboarding() {
        appSessionFlowService.signOut()
        currentEOA = nil
        currentAccumulatorAddress = nil
        hasLocalWalletMaterial = false
        withAnimation(AppAnimation.standard) {
            selectedMainTab = .home
            route = .onboarding
        }
    }

    private func restoreCachedWalletState(walletAddress: String) {
        let cacheID = cacheKey(walletAddress: walletAddress)
        let descriptor = FetchDescriptor<WalletActivityCache>(
            predicate: #Predicate { $0.id == cacheID },
        )

        guard let cacheEntry = try? modelContext.fetch(descriptor).first else {
            return
        }

        let decoder = JSONDecoder()

        if let balanceSnapshot = cacheEntry.balanceSnapshot,
           let decodedBalance = try? decoder.decode(BalanceStoreSnapshotModel.self, from: balanceSnapshot)
        {
            balanceStore.restore(from: decodedBalance)
        }

        if let transactionSnapshot = cacheEntry.transactionSnapshot,
           let decodedTransactions = try? decoder.decode(
               TransactionStoreSnapshotModel.self,
               from: transactionSnapshot,
           )
        {
            transactionStore.restore(from: decodedTransactions)
        }
    }

    private func persistCachedWalletState(walletAddress: String) {
        let encoder = JSONEncoder()
        let balanceData = try? encoder.encode(balanceStore.snapshot())
        let transactionData = try? encoder.encode(transactionStore.snapshot())

        let cacheID = cacheKey(walletAddress: walletAddress)
        let supportMode = ChainSupportRuntime.resolveMode().rawValue
        let descriptor = FetchDescriptor<WalletActivityCache>(
            predicate: #Predicate { $0.id == cacheID },
        )

        let entry: WalletActivityCache
        if let existing = try? modelContext.fetch(descriptor).first {
            entry = existing
        } else {
            entry = WalletActivityCache(
                id: cacheID,
                walletAddress: walletAddress.lowercased(),
                supportMode: supportMode,
                balanceSnapshot: nil,
                transactionSnapshot: nil,
                updatedAt: Date(),
            )
            modelContext.insert(entry)
        }

        entry.balanceSnapshot = balanceData
        entry.transactionSnapshot = transactionData
        entry.updatedAt = Date()
        entry.supportMode = supportMode

        try? modelContext.save()
    }

    private func cacheKey(walletAddress: String) -> String {
        let mode = ChainSupportRuntime.resolveMode().rawValue.lowercased()
        return "\(mode):\(walletAddress.lowercased())"
    }

    private func openReceive() {
        selectedMainTab = .home
        route = .receive
    }

    private func openSendMoneyIfReady() {
        guard currentAccumulatorAddress != nil else { return }
        selectedMainTab = .home
        route = .sendMoney
    }

    private func openProfile() {
        selectedMainTab = .home
        route = .profile
    }

    private func openPreferences() {
        selectedMainTab = .home
        route = .preferences
    }

    private func openAddressBook() {
        selectedMainTab = .home
        route = .addressBook
    }
}

#Preview {
    AppRootView()
        .preferredColorScheme(.dark)
        .modelContainer(for: [WalletActivityCache.self], inMemory: true)
}
