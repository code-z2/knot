import SwiftUI

struct AppRootView: View {
    @State private var route: Route = .splash
    @State private var currentEOA: String?
    @State private var isWorking = false
    private let accountService = AccountSetupService()

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
                        if let restored = try? await accountService.restoreSession() {
                            withAnimation(.easeInOut(duration: 0.25)) {
                                currentEOA = restored.eoaAddress
                                route = .home
                            }
                        } else {
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
                homeView
            }
        }
    }

    private var homeView: some View {
        ZStack {
            AppThemeColor.fixedDarkSurface.ignoresSafeArea()
            VStack(spacing: 16) {
                Text("Signed In")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundStyle(AppThemeColor.labelPrimary)

                if let currentEOA {
                    Text(currentEOA)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(AppThemeColor.labelSecondary)
                        .textSelection(.enabled)
                }

                Button("Sign Out") {
                    currentEOA = nil
                    route = .onboarding
                }
                .font(.custom("Roboto", size: 12).weight(.bold))
                .foregroundStyle(AppThemeColor.fixedDarkText)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(AppThemeColor.fillSecondary)
                )
                .buttonStyle(.plain)
            }
            .padding(24)
        }
    }

    @MainActor
    private func createAccountFromOnboarding() async {
        guard !isWorking else { return }
        isWorking = true
        defer { isWorking = false }

        if let restored = try? await accountService.createWallet() {
            currentEOA = restored.eoaAddress
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
            route = .home
        }
    }
}

#Preview {
    AppRootView()
        .preferredColorScheme(.dark)
}
