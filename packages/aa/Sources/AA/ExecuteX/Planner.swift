import Foundation
import Passkey
import RPC
import Security
import Transactions

public struct ExecuteXLeafRequest: Sendable, Equatable {
    public let chainId: UInt64
    public let mode: ExecuteXSubmissionMode
    public let payload: ExecuteXLeafRequestPayload

    public init(
        chainId: UInt64,
        mode: ExecuteXSubmissionMode = .immediate,
        payload: ExecuteXLeafRequestPayload,
    ) {
        self.chainId = chainId
        self.mode = mode
        self.payload = payload
    }
}

public struct ExecuteXChainAction: Sendable, Equatable {
    public let chainId: UInt64
    public let calls: [Call]

    public init(chainId: UInt64, calls: [Call]) {
        self.chainId = chainId
        self.calls = calls
    }
}

public struct ExecuteXFlowPlanRequest: Sendable {
    public let account: String
    public let passkeyPublicKey: PasskeyPublicKeyModel
    public let destinationChainId: UInt64
    public let chainActions: [ExecuteXChainAction]
    public let destinationAccumulatorIntent: AccumulatorExecutionIntent?
    public let destinationAccumulatorMode: ExecuteXSubmissionMode
    public let authorizationsByChainId: [UInt64: RelayAuthorizationModel]

    public init(
        account: String,
        passkeyPublicKey: PasskeyPublicKeyModel,
        destinationChainId: UInt64,
        chainActions: [ExecuteXChainAction],
        destinationAccumulatorIntent: AccumulatorExecutionIntent? = nil,
        destinationAccumulatorMode: ExecuteXSubmissionMode = .deferred,
        authorizationsByChainId: [UInt64: RelayAuthorizationModel] = [:],
    ) {
        self.account = account
        self.passkeyPublicKey = passkeyPublicKey
        self.destinationChainId = destinationChainId
        self.chainActions = chainActions
        self.destinationAccumulatorIntent = destinationAccumulatorIntent
        self.destinationAccumulatorMode = destinationAccumulatorMode
        self.authorizationsByChainId = authorizationsByChainId
    }
}

public struct ExecuteXPlanRequest: Sendable {
    public let account: String
    public let passkeyPublicKey: PasskeyPublicKeyModel
    public let leaves: [ExecuteXLeafRequest]
    public let authorizationsByChainId: [UInt64: RelayAuthorizationModel]

    public init(
        account: String,
        passkeyPublicKey: PasskeyPublicKeyModel,
        leaves: [ExecuteXLeafRequest],
        authorizationsByChainId: [UInt64: RelayAuthorizationModel] = [:],
    ) {
        self.account = account
        self.passkeyPublicKey = passkeyPublicKey
        self.leaves = leaves
        self.authorizationsByChainId = authorizationsByChainId
    }
}

public struct PlannedExecuteXCall: Sendable, Equatable {
    public let chainId: UInt64
    public let mode: ExecuteXSubmissionMode
    public let calls: [Call]
    public let didAppendInitializeCall: Bool
    public let authorizationRequired: Bool
    public let structHash: Data
    public let leafHash: Data
    public let merkleProof: [Data]
    public let executeXCalldata: Data
    public let relayTx: RelayTransactionEnvelopeModel

    public init(
        chainId: UInt64,
        mode: ExecuteXSubmissionMode,
        calls: [Call],
        didAppendInitializeCall: Bool,
        authorizationRequired: Bool,
        structHash: Data,
        leafHash: Data,
        merkleProof: [Data],
        executeXCalldata: Data,
        relayTx: RelayTransactionEnvelopeModel,
    ) {
        self.chainId = chainId
        self.mode = mode
        self.calls = calls
        self.didAppendInitializeCall = didAppendInitializeCall
        self.authorizationRequired = authorizationRequired
        self.structHash = structHash
        self.leafHash = leafHash
        self.merkleProof = merkleProof
        self.executeXCalldata = executeXCalldata
        self.relayTx = relayTx
    }
}

public struct PlannedAccumulatorExecution: Sendable, Equatable {
    public let chainId: UInt64
    public let mode: ExecuteXSubmissionMode
    public let intent: AccumulatorExecutionIntent
    public let structHash: Data
    public let leafHash: Data
    public let merkleProof: [Data]
    public let executeIntentCall: Call
    public let relayTx: RelayTransactionEnvelopeModel

    public init(
        chainId: UInt64,
        mode: ExecuteXSubmissionMode,
        intent: AccumulatorExecutionIntent,
        structHash: Data,
        leafHash: Data,
        merkleProof: [Data],
        executeIntentCall: Call,
        relayTx: RelayTransactionEnvelopeModel,
    ) {
        self.chainId = chainId
        self.mode = mode
        self.intent = intent
        self.structHash = structHash
        self.leafHash = leafHash
        self.merkleProof = merkleProof
        self.executeIntentCall = executeIntentCall
        self.relayTx = relayTx
    }
}

public struct ExecuteXLeafPlan: Sendable, Equatable {
    public let chainId: UInt64
    public let mode: ExecuteXSubmissionMode
    public let payload: ExecuteXLeafPlanContent

    public init(chainId: UInt64, mode: ExecuteXSubmissionMode, payload: ExecuteXLeafPlanContent) {
        self.chainId = chainId
        self.mode = mode
        self.payload = payload
    }
}

public struct ExecuteXPlan: Sendable, Equatable {
    public let account: String
    public let salt: Data
    public let merkleRoot: Data
    public let signingDigest: Data
    public let signature: Data
    public let leaves: [ExecuteXLeafPlan]
    public let immediateRelayTxs: [RelayTransactionEnvelopeModel]
    public let backgroundRelayTxs: [RelayTransactionEnvelopeModel]
    public let deferredRelayTxs: [RelayTransactionEnvelopeModel]
    public let accumulatorExecutions: [PlannedAccumulatorExecution]

    public init(
        account: String,
        salt: Data,
        merkleRoot: Data,
        signingDigest: Data,
        signature: Data,
        leaves: [ExecuteXLeafPlan],
        immediateRelayTxs: [RelayTransactionEnvelopeModel],
        backgroundRelayTxs: [RelayTransactionEnvelopeModel],
        deferredRelayTxs: [RelayTransactionEnvelopeModel],
        accumulatorExecutions: [PlannedAccumulatorExecution],
    ) {
        self.account = account
        self.salt = salt
        self.merkleRoot = merkleRoot
        self.signingDigest = signingDigest
        self.signature = signature
        self.leaves = leaves
        self.immediateRelayTxs = immediateRelayTxs
        self.backgroundRelayTxs = backgroundRelayTxs
        self.deferredRelayTxs = deferredRelayTxs
        self.accumulatorExecutions = accumulatorExecutions
    }
}

public actor ExecuteXPlanner {
    private let smartAccountClient: SmartAccountClient
    private let flowLeafBuilder = ExecuteXFlowLeafBuilder()
    private let initializationPolicy = ExecuteXInitializationPolicy()
    private let merkleSigner = ExecuteXMerkleSigner()
    private let relayEnvelopeBuilder = ExecuteXRelayEnvelopeBuilder()

    public init(smartAccountClient: SmartAccountClient = SmartAccountClient()) {
        self.smartAccountClient = smartAccountClient
    }

    public func buildPlan(
        request: ExecuteXPlanRequest,
        signRoot: @Sendable (Data) async throws -> Data,
    ) async throws -> ExecuteXPlan {
        guard !request.leaves.isEmpty else {
            throw ExecuteXPlannerError.emptyLeaves
        }

        let salt = randomBytes32()
        let leafResolver = ExecuteXLeafResolver(
            smartAccountClient: smartAccountClient,
            initializationPolicy: initializationPolicy,
        )
        let resolvedLeaves = try await leafResolver.resolveLeaves(
            request: request,
            salt: salt,
        )
        let signedMerkle = try await merkleSigner.signLeaves(
            resolvedLeaves,
            signRoot: signRoot,
        )
        return try relayEnvelopeBuilder.buildPlan(
            request: request,
            salt: salt,
            resolvedLeaves: resolvedLeaves,
            signedMerkle: signedMerkle,
        )
    }

    public func buildFlowPlan(
        request: ExecuteXFlowPlanRequest,
        signRoot: @Sendable (Data) async throws -> Data,
    ) async throws -> ExecuteXPlan {
        let leaves = flowLeafBuilder.buildLeafRequests(from: request)

        return try await buildPlan(
            request: ExecuteXPlanRequest(
                account: request.account,
                passkeyPublicKey: request.passkeyPublicKey,
                leaves: leaves,
                authorizationsByChainId: request.authorizationsByChainId,
            ),
            signRoot: signRoot,
        )
    }

    private func randomBytes32() -> Data {
        var bytes = Data(count: 32)
        _ = bytes.withUnsafeMutableBytes { buffer in
            SecRandomCopyBytes(kSecRandomDefault, 32, buffer.baseAddress!)
        }
        return bytes
    }
}
