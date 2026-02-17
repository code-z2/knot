import AA
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
  @State private var isWorking = false
  @State private var hasLocalWalletMaterial = false
  @State private var walletBackupMnemonic = ""
  @State private var preferencesStore = PreferencesStore()
  @State private var currencyRateStore = CurrencyRateStore()
  @State private var balanceStore = BalanceStore()
  @State private var transactionStore = TransactionStore(
    accumulatorConfig: AccumulatorConfig(
      factoryAddress: AAConstants.accumulatorFactoryAddress,
      spokePoolByChain: AAConstants.spokePoolByChain
    )
  )
  private let beneficiaryStore = BeneficiaryStore()
  private let accountService = AccountSetupService()
  @State private var ensService = ENSService(mode: ChainSupportRuntime.resolveMode())
  private let aaExecutionService = AAExecutionService()
  private let routeComposer = RouteComposer()
  private let sessionStore = SessionStore()
  private let faucetService = FaucetService()

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

  var body: some View {
    ZStack {
      switch route {
      case .splash:
        SplashView()
          .task {
            try? await Task.sleep(for: .seconds(1.2))
            guard let activeEOA = sessionStore.activeEOAAddress else {
              withAnimation(AppAnimation.standard) {
                route = .onboarding
              }
              return
            }

            if let restored = try? await accountService.restoreSession(eoaAddress: activeEOA) {
              hasLocalWalletMaterial = await accountService.hasLocalWalletMaterial(
                for: restored.eoaAddress)
              restoreCachedWalletState(walletAddress: restored.eoaAddress)
              withAnimation(AppAnimation.standard) {
                currentEOA = restored.eoaAddress
                selectedMainTab = .home
                route = .main
              }
              Task { await refreshWalletData(walletAddress: restored.eoaAddress) }
            } else {
              sessionStore.clearActiveSession()
              hasLocalWalletMaterial = false
              withAnimation(AppAnimation.standard) {
                route = .onboarding
              }
            }
          }
      case .onboarding:
        OnboardingView(
          onCreateWallet: { Task { await createAccountFromOnboarding() } },
          onLogin: { Task { await signInFromOnboarding() } }
        )
        .disabled(isWorking)
      case .main:
        mainTabView
      case .profile:
        ProfileView(
          eoaAddress: currentEOA ?? "0x0000000000000000000000000000000000000000",
          accountService: accountService,
          ensService: ensService,
          aaExecutionService: aaExecutionService,
          onBack: {
            selectedMainTab = .home
            route = .main
          }
        )
        .transition(AppAnimation.slideTransition)
      case .preferences:
        PreferencesView(
          preferencesStore: preferencesStore,
          onBack: {
            selectedMainTab = .home
            route = .main
          }
        )
        .transition(AppAnimation.slideTransition)
      case .addressBook:
        AddressBookView(
          eoaAddress: currentEOA ?? "0x0000000000000000000000000000000000000000",
          store: beneficiaryStore,
          ensService: ensService,
          onBack: {
            selectedMainTab = .home
            route = .main
          }
        )
        .transition(AppAnimation.slideTransition)
      case .receive:
        ReceiveView(
          address: currentEOA ?? "0x0000000000000000000000000000000000000000",
          onBack: {
            selectedMainTab = .home
            route = .main
          }
        )
      case .sendMoney:
        SendMoneyView(
          eoaAddress: currentEOA ?? "0x0000000000000000000000000000000000000000",
          store: beneficiaryStore,
          balanceStore: balanceStore,
          preferencesStore: preferencesStore,
          currencyRateStore: currencyRateStore,
          routeComposer: routeComposer,
          aaExecutionService: aaExecutionService,
          accountService: accountService,
          ensService: ensService,
          onBack: {
            selectedMainTab = .home
            route = .main
          }
        )
      case .walletBackup:
        WalletBackupView(
          mnemonic: walletBackupMnemonic,
          onBack: {
            selectedMainTab = .home
            route = .main
          }
        )
        .transition(AppAnimation.slideTransition)
      }
    }
    .animation(.spring(response: 0.32, dampingFraction: 0.86), value: route)
    .preferredColorScheme(preferredColorScheme)
    .environment(\.locale, preferencesStore.locale)
    .environment(\.layoutDirection, layoutDirection)
    .task {
      await currencyRateStore.refreshIfNeeded()
      await currencyRateStore.ensureRate(for: preferencesStore.selectedCurrencyCode)
      if let eoa = currentEOA {
        Task { await refreshWalletData(walletAddress: eoa) }
      }
    }
    .onChange(of: scenePhase) { _, newPhase in
      guard newPhase == .active else { return }
      Task {
        await currencyRateStore.refreshIfNeeded()
        if let eoa = currentEOA {
          await refreshWalletData(walletAddress: eoa)
        }
      }
    }
    .onChange(of: preferencesStore.selectedCurrencyCode) { _, newCode in
      Task {
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
      Task {
        await refreshWalletData(walletAddress: eoa)
        await triggerFaucetIfNeeded(walletAddress: eoa, mode: newMode)
      }
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

  private var mainTabs: some View {
    TabView(selection: $selectedMainTab) {
      Tab(value: MainTab.home) {
        HomeView(
          balanceStore: balanceStore,
          preferencesStore: preferencesStore,
          currencyRateStore: currencyRateStore,
          onSignOut: {
            sessionStore.clearActiveSession()
            currentEOA = nil
            hasLocalWalletMaterial = false
            selectedMainTab = .home
            route = .onboarding
          },
          onAddMoney: {
            selectedMainTab = .home
            route = .receive
          },
          onSendMoney: {
            selectedMainTab = .home
            route = .sendMoney
          },
          onProfileTap: {
            selectedMainTab = .home
            route = .profile
          },
          onPreferencesTap: {
            selectedMainTab = .home
            route = .preferences
          },
          onWalletBackupTap: { Task { await openWalletBackupIfAvailable() } },
          onAddressBookTap: {
            selectedMainTab = .home
            route = .addressBook
          },
          showWalletBackup: hasLocalWalletMaterial
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
          currencyRateStore: currencyRateStore
        )
      } label: {
        Label {
          Text("bottom_nav_transactions")
        } icon: {
          Image("Icons/receipt")
            .renderingMode(.template)
        }
      }

      Tab(value: MainTab.sessionKey) {
        SessionKeyView()
      } label: {
        Label {
          Text("bottom_nav_session_key")
        } icon: {
          Image("Icons/key_01")
            .renderingMode(.template)
        }
      }
    }
    .tint(AppThemeColor.accentBrown)
    .sensoryFeedback(AppHaptic.selection.sensoryFeedback, trigger: tabChangeTrigger) { _, _ in
      preferencesStore.hapticsEnabled
    }
  }

  @MainActor
  private func createAccountFromOnboarding() async {
    guard !isWorking else { return }
    isWorking = true
    defer { isWorking = false }

    if let restored = try? await accountService.createWallet() {
      currentEOA = restored.eoaAddress
      sessionStore.setActiveSession(eoaAddress: restored.eoaAddress)
      hasLocalWalletMaterial = await accountService.hasLocalWalletMaterial(for: restored.eoaAddress)
      selectedMainTab = .home
      route = .main

      // Fire-and-forget: fund new account with testnet USDC + ETH.
      await triggerFaucetIfNeeded(
        walletAddress: restored.eoaAddress, mode: preferencesStore.chainSupportMode)

      restoreCachedWalletState(walletAddress: restored.eoaAddress)
      Task { await refreshWalletData(walletAddress: restored.eoaAddress) }
    }
  }

  @MainActor
  private func signInFromOnboarding() async {
    guard !isWorking else { return }
    isWorking = true
    defer { isWorking = false }

    if let restored = try? await accountService.signIn() {
      currentEOA = restored.eoaAddress
      sessionStore.setActiveSession(eoaAddress: restored.eoaAddress)
      hasLocalWalletMaterial = await accountService.hasLocalWalletMaterial(for: restored.eoaAddress)
      restoreCachedWalletState(walletAddress: restored.eoaAddress)
      selectedMainTab = .home
      route = .main
      await triggerFaucetIfNeeded(
        walletAddress: restored.eoaAddress, mode: preferencesStore.chainSupportMode)
      Task { await refreshWalletData(walletAddress: restored.eoaAddress) }
    }
  }

  @MainActor
  private func openWalletBackupIfAvailable() async {
    guard let eoa = currentEOA else { return }
    guard hasLocalWalletMaterial else { return }
    guard let mnemonic = try? await accountService.localMnemonic(for: eoa) else { return }
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
      return .dark
    default:
      switch preferencesStore.appearance {
      case .dark:
        return .dark
      case .light:
        return .light
      case .system:
        return nil
      }
    }
  }

  private func refreshWalletData(walletAddress: String) async {
    await balanceStore.refresh(walletAddress: walletAddress)
    await transactionStore.refresh(walletAddress: walletAddress)
    persistCachedWalletState(walletAddress: walletAddress)
  }

  private func restoreCachedWalletState(walletAddress: String) {
    let cacheID = cacheKey(walletAddress: walletAddress)
    let descriptor = FetchDescriptor<WalletActivityCache>(
      predicate: #Predicate { $0.id == cacheID }
    )

    guard let cacheEntry = try? modelContext.fetch(descriptor).first else {
      return
    }

    let decoder = JSONDecoder()

    if let balanceSnapshot = cacheEntry.balanceSnapshot,
      let decodedBalance = try? decoder.decode(BalanceStoreSnapshot.self, from: balanceSnapshot)
    {
      balanceStore.restore(from: decodedBalance)
    }

    if let transactionSnapshot = cacheEntry.transactionSnapshot,
      let decodedTransactions = try? decoder.decode(
        TransactionStoreSnapshot.self,
        from: transactionSnapshot
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
      predicate: #Predicate { $0.id == cacheID }
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
        updatedAt: Date()
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

  private func triggerFaucetIfNeeded(walletAddress: String, mode: ChainSupportMode) async {
    guard mode == .limitedTestnet else { return }
    await faucetService.fundAccount(eoaAddress: walletAddress, mode: mode)
  }
}

#Preview {
  AppRootView()
    .preferredColorScheme(.dark)
    .modelContainer(for: [WalletActivityCache.self], inMemory: true)
}
