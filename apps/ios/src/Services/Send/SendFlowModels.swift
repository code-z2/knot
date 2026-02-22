import Compose
import Foundation

enum SendFlowServiceError: LocalizedError {
    case routeResolutionFailed(RouteError)
    case submissionFailed(AAExecutionServiceError)
    case invalidRoute(reason: String)
    case unknown(Error)

    var errorDescription: String? {
        switch self {
        case let .routeResolutionFailed(error):
            switch error {
            case .insufficientBalance:
                String(localized: "send_money_insufficient_balance")
            case let .noRouteFound(reason):
                reason
            case let .quoteUnavailable(provider, reason):
                "\(provider): \(reason)"
            case let .unsupportedChain(chainID):
                "Unsupported chain \(chainID)"
            case let .unsupportedAsset(symbol):
                "Unsupported asset \(symbol)"
            }
        case let .submissionFailed(error):
            error.localizedDescription
        case let .invalidRoute(reason):
            reason
        case let .unknown(error):
            error.localizedDescription
        }
    }
}

struct SendExecutionResultModel: Sendable {
    let destinationRelayTaskID: String
    let immediateRelayTaskIDs: [String]
    let backgroundRelayTaskIDs: [String]
    let deferredRelayTaskIDs: [String]

    var hasDeferredRelayTasks: Bool {
        !deferredRelayTaskIDs.isEmpty
    }
}
