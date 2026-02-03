import SwiftUI

struct AppRootView: View {
  @State private var route: Route = .splash
  @State private var currentEOA: String?
  @State private var isWorking = false
  private let accountService = AccountSetupService()
  private let sessionStore = SessionStore()

  enum Route {
    case splash
    case onboarding
    case home
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
              withAnimation(.easeInOut(duration: 0.25)) {
                currentEOA = restored.eoaAddress
                route = .home
              }
            } else {
              sessionStore.clearActiveSession()
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
            route = .onboarding
          }
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
      route = .home
    }
  }
}

#Preview {
  AppRootView()
    .preferredColorScheme(.dark)
}
