import SwiftUI

extension ProfileView {
    func infoText(_ value: String, tone: NameInfoTone) -> some View {
        Text(value)
            .font(.custom("Roboto-Regular", size: 12))
            .foregroundStyle(color(for: tone))
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
    }

    func color(for tone: NameInfoTone) -> Color {
        switch tone {
        case .info:
            AppThemeColor.labelSecondary
        case .success:
            AppThemeColor.accentGreen
        case .error:
            AppThemeColor.accentRed
        }
    }

    @MainActor
    func showError(_ error: Error) {
        successMessage = nil
        successMessageResetTask?.cancel()
        successMessageResetTask = nil
        errorMessage = error.localizedDescription
        errorMessageResetTask?.cancel()
        errorMessageResetTask = Task { @MainActor in
            do {
                try await Task.sleep(for: .seconds(2.8))
            } catch {
                return
            }
            if errorMessage == error.localizedDescription { errorMessage = nil }
        }
    }

    @MainActor
    func showSuccess(_ message: String) {
        errorMessage = nil
        errorMessageResetTask?.cancel()
        errorMessageResetTask = nil
        successMessage = message
        successMessageResetTask?.cancel()
        successMessageResetTask = Task { @MainActor in
            do {
                try await Task.sleep(for: .seconds(2.0))
            } catch {
                return
            }
            if successMessage == message { successMessage = nil }
        }
    }

    func toast(message: String, isError: Bool) -> some View {
        ToastView(message: message, isError: isError)
    }
}
