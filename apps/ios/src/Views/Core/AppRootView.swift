import AccountSetup
import Balance
import RPC
import SwiftUI
import Transactions

@MainActor
struct AppRootView: View {
  @Environment(\.scenePhase) private var scenePhase
  @State private var route: Route = .splash
  @State private var currentEOA: String?
  @State private var isWorking = false
  @State private var hasLocalWalletMaterial = false
  @State private var walletBackupMnemonic = ""
  @State private var preferencesStore = PreferencesStore()
  @State private var currencyRateStore = CurrencyRateStore()
  @State private var balanceStore = BalanceStore()
  @State private var transactionStore = TransactionStore()
  private let beneficiaryStore = BeneficiaryStore()
  private let accountService = AccountSetupService()
  private let ensService = ENSService()
  private let aaExecutionService = AAExecutionService()
  private let sessionStore = SessionStore()
  private let faucetService = FaucetService()

  enum Route {
    case splash
    case onboarding
    case home
    case transactions
    case profile
    case preferences
    case addressBook
    case receive
    case sendMoney
    case sessionKey
    case walletBackup
  }

  var body: some View {
    ZStack {
      switch route {
      case .splash:
        SplashView()
          .task {
            try? await Task.sleep(for: .seconds(1.2))
            guard let activeEOA = sessionStore.activeEOAAddress else {
              withAnimation(.easeInOut(duration: 0.18)) {
                route = .onboarding
              }
              return
            }

            if let restored = try? await accountService.restoreSession(eoaAddress: activeEOA) {
              hasLocalWalletMaterial = await accountService.hasLocalWalletMaterial(for: restored.eoaAddress)
              withAnimation(.easeInOut(duration: 0.18)) {
                currentEOA = restored.eoaAddress
                route = .home
              }
              async let _ = balanceStore.refresh(walletAddress: restored.eoaAddress)
              async let _ = transactionStore.refresh(walletAddress: restored.eoaAddress)
            } else {
              sessionStore.clearActiveSession()
              hasLocalWalletMaterial = false
              withAnimation(.easeInOut(duration: 0.18)) {
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
      case .home:
        HomeView(
          balanceStore: balanceStore,
          preferencesStore: preferencesStore,
          currencyRateStore: currencyRateStore,
          onSignOut: {
            sessionStore.clearActiveSession()
            currentEOA = nil
            hasLocalWalletMaterial = false
            route = .onboarding
          },
          onAddMoney: { route = .receive },
          onSendMoney: { route = .sendMoney },
          onHomeTap: { route = .home },
          onTransactionsTap: { route = .transactions },
          onSessionKeyTap: { route = .sessionKey },
          onProfileTap: { route = .profile },
          onPreferencesTap: { route = .preferences },
          onWalletBackupTap: { Task { await openWalletBackupIfAvailable() } },
          onAddressBookTap: { route = .addressBook },
          showWalletBackup: hasLocalWalletMaterial
        )
      case .transactions:
        TransactionsView(
          balanceStore: balanceStore,
          transactionStore: transactionStore,
          preferencesStore: preferencesStore,
          currencyRateStore: currencyRateStore,
          onHomeTap: { route = .home },
          onTransactionsTap: { route = .transactions },
          onSessionKeyTap: { route = .sessionKey }
        )
      case .profile:
        ProfileView(
          eoaAddress: currentEOA ?? "0x0000000000000000000000000000000000000000",
          accountService: accountService,
          ensService: ensService,
          aaExecutionService: aaExecutionService,
          onBack: { route = .home }
        )
      case .preferences:
        PreferencesView(
          preferencesStore: preferencesStore,
          onBack: { route = .home }
        )
      case .addressBook:
        AddressBookView(
          eoaAddress: currentEOA ?? "0x0000000000000000000000000000000000000000",
          store: beneficiaryStore,
          onBack: { route = .home }
        )
      case .receive:
        ReceiveView(
          address: currentEOA ?? "0x0000000000000000000000000000000000000000",
          onBack: { route = .home }
        )
      case .sendMoney:
        SendMoneyView(
          eoaAddress: currentEOA ?? "0x0000000000000000000000000000000000000000",
          store: beneficiaryStore,
          balanceStore: balanceStore,
          preferencesStore: preferencesStore,
          currencyRateStore: currencyRateStore,
          onBack: { route = .home }
        )
      case .sessionKey:
        SessionKeyView(
          onHomeTap: { route = .home },
          onTransactionsTap: { route = .transactions },
          onSessionKeyTap: { route = .sessionKey }
        )
      case .walletBackup:
        WalletBackupView(
          mnemonic: walletBackupMnemonic,
          onBack: { route = .home }
        )
      }
    }
    .transition(shouldAnimateRoute ? .opacity.combined(with: .scale(scale: 0.98)) : .identity)
    .animation(shouldAnimateRoute ? .easeInOut(duration: 0.18) : nil, value: route)
    .preferredColorScheme(preferredColorScheme)
    .environment(\.locale, preferencesStore.locale)
    .environment(\.layoutDirection, layoutDirection)
    .task {
      await currencyRateStore.refreshIfNeeded()
      await currencyRateStore.ensureRate(for: preferencesStore.selectedCurrencyCode)
      if let eoa = currentEOA {
        async let _ = balanceStore.refresh(walletAddress: eoa)
        async let _ = transactionStore.refresh(walletAddress: eoa)
      }
    }
    .onChange(of: scenePhase) { _, newPhase in
      guard newPhase == .active else { return }
      Task {
        await currencyRateStore.refreshIfNeeded()
        if let eoa = currentEOA {
          async let _ = balanceStore.refresh(walletAddress: eoa)
          async let _ = transactionStore.refresh(walletAddress: eoa)
        }
      }
    }
    .onChange(of: preferencesStore.selectedCurrencyCode) { _, newCode in
      Task {
        await currencyRateStore.ensureRate(for: newCode)
      }
    }
  }

  private var shouldAnimateRoute: Bool {
    switch route {
    case .profile, .preferences, .addressBook, .receive, .sendMoney, .walletBackup:
      return true
    case .splash, .onboarding, .home, .transactions, .sessionKey:
      return false
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
      route = .home

      // Fire-and-forget: fund new account with testnet USDC + ETH.
      if ChainSupportRuntime.resolveMode() == .limitedTestnet {
        let address = restored.eoaAddress
        let faucet = faucetService
        Task.detached(priority: .utility) {
          await faucet.fundAccount(eoaAddress: address)
        }
      }

      async let _ = balanceStore.refresh(walletAddress: restored.eoaAddress)
      async let _ = transactionStore.refresh(walletAddress: restored.eoaAddress)
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
      route = .home
      async let _ = balanceStore.refresh(walletAddress: restored.eoaAddress)
      async let _ = transactionStore.refresh(walletAddress: restored.eoaAddress)
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
}

#Preview {
  AppRootView()
    .preferredColorScheme(.dark)
}
