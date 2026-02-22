import LocalAuthentication

enum BiometricAuthError: Error {
    case unavailable
    case denied
    case failed(Error)
}

extension BiometricAuthError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .unavailable:
            "Biometric authentication is not available on this device."
        case .denied:
            "Biometric authentication was denied."
        case let .failed(error):
            "Biometric authentication failed: \(error.localizedDescription)"
        }
    }
}

@MainActor
final class BiometricAuthService {
    private var context: LAContext?
    private var lastAuthTime: Date?
    private let reuseDuration: TimeInterval

    init(reuseDuration: TimeInterval = 60) {
        self.reuseDuration = reuseDuration
    }

    func authenticate(reason: String) async throws {
        if let lastAuthTime, Date().timeIntervalSince(lastAuthTime) < reuseDuration {
            return
        }

        let context = LAContext()
        context.touchIDAuthenticationAllowableReuseDuration = reuseDuration

        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            throw BiometricAuthError.unavailable
        }

        do {
            let success = try await context.evaluatePolicy(
                .deviceOwnerAuthenticationWithBiometrics,
                localizedReason: reason,
            )
            guard success else { throw BiometricAuthError.denied }
            self.context = context
            lastAuthTime = Date()
        } catch let laError as LAError where laError.code == .userCancel || laError.code == .userFallback {
            throw BiometricAuthError.denied
        } catch {
            throw BiometricAuthError.failed(error)
        }
    }

    func invalidate() {
        context?.invalidate()
        context = nil
        lastAuthTime = nil
    }
}
