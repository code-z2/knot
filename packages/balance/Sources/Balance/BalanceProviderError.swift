import Foundation

public enum BalanceProviderError: LocalizedError {
    case invalidURL(String)

    case httpError(statusCode: Int)

    case apiError(message: String)

    case decodingFailed

    public var errorDescription: String? {
        switch self {
        case let .invalidURL(url):
            "Invalid balances API URL: \(url)"

        case let .httpError(statusCode):
            "Balance API returned HTTP \(statusCode)."

        case let .apiError(message):
            "Balance API error: \(message)"

        case .decodingFailed:
            "Failed to decode balance response."
        }
    }
}
