import SwiftUI

struct AppRootView: View {
  @State private var route: Route = .splash
  @State private var currentEOA: String?
  @State private var isWorking = false
  @State private var hasLocalWalletMaterial = false
  @State private var walletBackupMnemonic = ""
  @State private var preferencesStore = PreferencesStore()
  private let beneficiaryStore = BeneficiaryStore()
  private let accountService = AccountSetupService()
  private let sessionStore = SessionStore()

  enum Route {
    case splash
    case onboarding
    case home
    case preferences
    case addressBook
    case receive
    case sessionKey
    case walletBackup
  }

  var body: some View {
    Group {
      switch route {
      case .splash:
        SplashView()
          .task {
            try? await Task.sleep(for: .seconds(1.2))
            guard let activeEOA = sessionStore.activeEOAAddress else {
              withAnimation(.easeInOut(duration: 0.25)) {
                route = .onboarding
              }
              return
            }

            if let restored = try? await accountService.restoreSession(eoaAddress: activeEOA) {
              hasLocalWalletMaterial = await accountService.hasLocalWalletMaterial(for: restored.eoaAddress)
              withAnimation(.easeInOut(duration: 0.25)) {
                currentEOA = restored.eoaAddress
                route = .home
              }
            } else {
              sessionStore.clearActiveSession()
              hasLocalWalletMaterial = false
              withAnimation(.easeInOut(duration: 0.25)) {
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
          onSignOut: {
            sessionStore.clearActiveSession()
            currentEOA = nil
            hasLocalWalletMaterial = false
            route = .onboarding
          },
          onAddMoney: { route = .receive },
          onHomeTap: { route = .home },
          onSessionKeyTap: { route = .sessionKey },
          onPreferencesTap: { route = .preferences },
          onWalletBackupTap: { Task { await openWalletBackupIfAvailable() } },
          onAddressBookTap: { route = .addressBook },
          showWalletBackup: hasLocalWalletMaterial
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
      case .sessionKey:
        SessionKeyView(
          onHomeTap: { route = .home },
          onSessionKeyTap: { route = .sessionKey }
        )
      case .walletBackup:
        WalletBackupView(
          mnemonic: walletBackupMnemonic,
          onBack: { route = .home }
        )
      }
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
}

#Preview {
  AppRootView()
    .preferredColorScheme(.dark)
}
