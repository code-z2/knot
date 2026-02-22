import Foundation

public enum TransactionProviderError: LocalizedError {
    case invalidURL(String)

    case httpError(statusCode: Int)

    case apiError(message: String)

    case decodingFailed

    public var errorDescription: String? {
        switch self {
        case let .invalidURL(url):
            "Invalid transactions API URL: \(url)"

        case let .httpError(statusCode):
            "Transactions API returned HTTP \(statusCode)."

        case let .apiError(message):
            "Transactions API error: \(message)"

        case .decodingFailed:
            "Failed to decode transactions response."
        }
    }
}
