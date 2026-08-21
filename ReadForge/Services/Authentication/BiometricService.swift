import LocalAuthentication

final class BiometricService {
    func isBiometricAvailable() -> Bool {
        let context = LAContext()
        var error: NSError?
        return context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
    }

    func getBiometricType() -> LABiometryType {
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        return context.biometryType
    }

    func getBiometricDisplayName() -> String {
        switch getBiometricType() {
        case .faceID: return "Face ID"
        case .touchID: return "Touch ID"
        case .opticID: return "Optic ID"
        default: return "Biometrics"
        }
    }

    func shouldOfferBiometricAuthentication() -> Bool {
        isBiometricAvailable()
    }

    /// Actually prompts Face ID / Touch ID and returns whether the user passed the challenge.
    /// `isBiometricAvailable()` only checks whether biometrics *could* be used — it never
    /// performs the challenge itself, so callers must call this before treating the user as
    /// authenticated.
    func evaluate(reason: String = "Sign in to ReadForge") async -> Bool {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            return false
        }
        return await withCheckedContinuation { continuation in
            context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason) { success, _ in
                continuation.resume(returning: success)
            }
        }
    }
}
