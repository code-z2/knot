import Foundation

enum AddressDetectionResult: Sendable {
    case evmAddress(String)
    case ensName(String)
    case invalid
}

enum AddressInputParser {
    nonisolated static func detectCandidate(
        _ input: String,
        mode: DropdownInputValidationMode = .strictAddressOrENS,
    ) -> AddressDetectionResult {
        let normalized = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return .invalid }

        switch mode {
        case .strictAddressOrENS:
            if isLikelyEVMAddress(normalized) {
                return .evmAddress(normalized)
            }
            if isLikelyENSName(normalized) {
                return .ensName(normalized.lowercased())
            }
            return .invalid
        case .flexible:
            return .ensName(normalized)
        }
    }

    nonisolated static func isLikelyEVMAddress(_ input: String) -> Bool {
        let normalized = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let pattern = #"^0x[a-fA-F0-9]{40}$"#
        return normalized.range(of: pattern, options: .regularExpression) != nil
    }

    nonisolated static func isLikelyENSName(_ input: String) -> Bool {
        let normalized = input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let pattern =
            #"^(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)*([a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?)\.eth$"#
        return normalized.range(of: pattern, options: .regularExpression) != nil
    }

    nonisolated static func extractCandidate(from rawCode: String) -> String? {
        let normalized = rawCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return nil }

        if isLikelyEVMAddress(normalized) {
            return normalized
        }
        if isLikelyENSName(normalized) {
            return normalized.lowercased()
        }

        let separators = CharacterSet(charactersIn: " \n\t\r/?&=:#@")
        let tokens = normalized.components(separatedBy: separators).filter { !$0.isEmpty }
        for token in tokens {
            if isLikelyEVMAddress(token) {
                return token
            }
            if isLikelyENSName(token) {
                return token.lowercased()
            }
        }

        return nil
    }
}
