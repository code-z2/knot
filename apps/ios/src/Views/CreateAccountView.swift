import SwiftUI

struct CreateAccountView: View {
    @State private var isWorking = false
    @State private var result: CreatedWallet?
    @State private var errorMessage: String?

    let accountService: AccountSetupService
    let onComplete: (CreatedWallet) -> Void

    var body: some View {
        ZStack {
            AppThemeColor.fixedDarkSurface.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 20) {
                Text("Create Wallet")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundStyle(AppThemeColor.labelPrimary)

                Text("Creates a new EOA, registers passkey, and stores signed 7702 authorization.")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(AppThemeColor.labelSecondary)

                if let result {
                    Group {
                        labeledValue("EOA", result.eoaAddress)
                        labeledValue("Passkey", result.passkeyCredentialID)
                    }
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(AppThemeColor.accentRed)
                }

                PrimaryButton(title: isWorking ? "Creating..." : "Create Wallet") {
                    Task { await createWallet() }
                }
                .disabled(isWorking)

                Spacer(minLength: 0)
            }
            .padding(24)
        }
    }

    private func labeledValue(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AppThemeColor.labelVibrantSecondary)
            Text(value)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(AppThemeColor.labelPrimary)
                .textSelection(.enabled)
        }
    }

    private func createWallet() async {
        isWorking = true
        errorMessage = nil

        do {
            let created = try await accountService.createWallet()
            result = created
            onComplete(created)
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
    CreateAccountView(accountService: AccountSetupService(), onComplete: { _ in })
        .preferredColorScheme(.dark)
}
