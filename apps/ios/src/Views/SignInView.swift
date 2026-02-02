import SwiftUI

struct SignInView: View {
    @State private var isWorking = false
    @State private var errorMessage: String?

    let accountService: AccountSetupService
    let onComplete: (SignedInWallet) -> Void

    var body: some View {
        ZStack {
            AppThemeColor.fixedDarkSurface.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 20) {
                Text("Sign In")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundStyle(AppThemeColor.labelPrimary)

                Text("Verifies passkey presence and recovers EOA from stored signed authorization.")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(AppThemeColor.labelSecondary)

                if let errorMessage {
                    Text(errorMessage)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(AppThemeColor.accentRed)
                }

                PrimaryButton(title: isWorking ? "Signing In..." : "Continue with Passkey") {
                    Task { await signIn() }
                }
                .disabled(isWorking)

                Spacer(minLength: 0)
            }
            .padding(24)
        }
    }

    private func signIn() async {
        isWorking = true
        errorMessage = nil

        do {
            let signedIn = try await accountService.signIn()
            onComplete(signedIn)
        } catch {
            errorMessage = renderError(error)
        }

        isWorking = false
    }

    private func renderError(_ error: Error) -> String {
        let nsError = error as NSError
        return "\(error.localizedDescription)\n[\(nsError.domain):\(nsError.code)]"
    }
}

#Preview {
    SignInView(accountService: AccountSetupService(), onComplete: { _ in })
        .preferredColorScheme(.dark)
}
