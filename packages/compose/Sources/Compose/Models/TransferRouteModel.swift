import Foundation

/// A resolved transfer route with ready-to-sign calldata.
public struct TransferRouteModel: Sendable {
    /// Human-readable steps for UI visualization.
    public let steps: [RouteStepModel]
    /// Per-chain execution actions for AAExecutionService.
    public let chainActions: [ChainActionModel]
    /// Optional route identifier for multi-chain (accumulate) UI tracking.
    public let jobId: Data?
    /// The destination chain where funds ultimately arrive.
    public let destinationChainId: UInt64
    /// Estimated amount the recipient receives.
    public let estimatedAmountOut: Decimal
    /// Symbol of the output token.
    public let estimatedAmountOutSymbol: String

    public init(
        steps: [RouteStepModel],
        chainActions: [ChainActionModel],
        jobId: Data?,
        destinationChainId: UInt64,
        estimatedAmountOut: Decimal,
        estimatedAmountOutSymbol: String,
    ) {
        self.steps = steps
        self.chainActions = chainActions
        self.jobId = jobId
        self.destinationChainId = destinationChainId
        self.estimatedAmountOut = estimatedAmountOut
        self.estimatedAmountOutSymbol = estimatedAmountOutSymbol
    }
}

/// A single step in a transfer route, for UI display.
public struct RouteStepModel: Sendable, Identifiable {
    public let id: UUID
    public let chainId: UInt64
    public let chainName: String
    public let action: RouteAction
    public let inputAmount: Decimal
    public let inputSymbol: String
    public let outputAmount: Decimal
    public let outputSymbol: String

    public init(
        id: UUID = UUID(),
        chainId: UInt64,
        chainName: String,
        action: RouteAction,
        inputAmount: Decimal,
        inputSymbol: String,
        outputAmount: Decimal,
        outputSymbol: String,
    ) {
        self.id = id
        self.chainId = chainId
        self.chainName = chainName
        self.action = action
        self.inputAmount = inputAmount
        self.inputSymbol = inputSymbol
        self.outputAmount = outputAmount
        self.outputSymbol = outputSymbol
    }
}
