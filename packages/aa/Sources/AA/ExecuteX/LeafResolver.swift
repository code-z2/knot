import Foundation
import Passkey
import RPC
import Transactions

struct ExecuteXLeafResolver {
    private let smartAccountClient: SmartAccountClient
    private let initializationPolicy: ExecuteXInitializationPolicy

    init(
        smartAccountClient: SmartAccountClient,
        initializationPolicy: ExecuteXInitializationPolicy = ExecuteXInitializationPolicy(),
    ) {
        self.smartAccountClient = smartAccountClient
        self.initializationPolicy = initializationPolicy
    }

    func resolveLeaves(
        request: ExecuteXPlanRequest,
        salt: Data,
        signInitialize: (@Sendable (Data) async throws -> Data)? = nil,
    ) async throws -> [ExecuteXResolvedLeaf] {
        var seenExecuteLeafChains = Set<UInt64>()
        let accumulatorOnlyChainOrder = initializationPolicy.accumulatorOnlyChainsInOrder(
            leaves: request.leaves,
        )

        var resolvedLeaves: [ExecuteXResolvedLeaf] = []
        resolvedLeaves.reserveCapacity(request.leaves.count + accumulatorOnlyChainOrder.count)

        for leaf in request.leaves {
            switch leaf.payload {
            case let .executeCalls(rawCalls):
                if seenExecuteLeafChains.contains(leaf.chainId) {
                    throw ExecuteXPlannerError.duplicateExecuteLeafChain(leaf.chainId)
                }
                seenExecuteLeafChains.insert(leaf.chainId)

                let resolvedExecuteLeaf = try await resolveExecuteLeaf(
                    account: request.account,
                    passkeyPublicKey: request.passkeyPublicKey,
                    chainId: leaf.chainId,
                    mode: leaf.mode,
                    rawCalls: rawCalls,
                    salt: salt,
                    authorizationsByChainId: request.authorizationsByChainId,
                    signInitialize: signInitialize,
                )
                resolvedLeaves.append(ExecuteXResolvedLeaf(execute: resolvedExecuteLeaf))

            case let .accumulatorIntent(intent):
                let structHash = try SmartAccount.Accumulator.hashExecutionParamsStruct(intent.params)
                let leafHash = try SmartAccount.ExecuteX.leafHash(
                    account: request.account,
                    chainId: leaf.chainId,
                    structHash: structHash,
                )
                resolvedLeaves.append(
                    ExecuteXResolvedLeaf(
                        accumulator: ExecuteXResolvedAccumulatorLeaf(
                            chainId: leaf.chainId,
                            mode: leaf.mode,
                            intent: intent,
                            structHash: structHash,
                            leafHash: leafHash,
                        ),
                    ),
                )
            }
        }

        for chainId in accumulatorOnlyChainOrder {
            let isDeployed = try await smartAccountClient.isDeployed(
                account: request.account,
                chainId: chainId,
            )
            guard !isDeployed else { continue }

            let initializeLeaf = try await buildInitializeOnlyExecuteLeaf(
                account: request.account,
                passkeyPublicKey: request.passkeyPublicKey,
                chainId: chainId,
                salt: salt,
                authorizationsByChainId: request.authorizationsByChainId,
                signInitialize: signInitialize,
            )
            resolvedLeaves.append(ExecuteXResolvedLeaf(execute: initializeLeaf))
        }

        return resolvedLeaves
    }

    private func resolveExecuteLeaf(
        account: String,
        passkeyPublicKey: PasskeyPublicKeyModel,
        chainId: UInt64,
        mode: ExecuteXSubmissionMode,
        rawCalls: [Call],
        salt: Data,
        authorizationsByChainId: [UInt64: RelayAuthorizationModel],
        signInitialize: (@Sendable (Data) async throws -> Data)? = nil,
    ) async throws -> ExecuteXResolvedExecuteLeaf {
        let isDeployed = try await smartAccountClient.isDeployed(account: account, chainId: chainId)
        var calls = rawCalls
        var didAppendInitializeCall = false
        var authorization: RelayAuthorizationModel? = nil
        var initSignature: Data? = nil

        if !isDeployed {
            let initializeCall = try makeInitializeCall(
                account: account,
                passkeyPublicKey: passkeyPublicKey,
                chainId: chainId,
            )
            calls.insert(initializeCall, at: 0)
            didAppendInitializeCall = true

            guard let chainAuthorization = authorizationsByChainId[chainId] else {
                throw ExecuteXPlannerError.missingAuthorization(chainId: chainId)
            }
            authorization = chainAuthorization

            // Sign calls[0].data with EOA key for the init overload.
            if let signInitialize {
                let callData = try AAUtils.hexToData(initializeCall.dataHex)
                let callDataHash = Data(callData.sha3(.keccak256))
                initSignature = try await signInitialize(callDataHash)
            }
        }

        let structHash = try SmartAccount.ExecuteX.structHash(calls: calls, salt: salt)
        let leafHash = try SmartAccount.ExecuteX.leafHash(
            account: account,
            chainId: chainId,
            structHash: structHash,
        )

        return ExecuteXResolvedExecuteLeaf(
            chainId: chainId,
            mode: mode,
            calls: calls,
            didAppendInitializeCall: didAppendInitializeCall,
            authorizationRequired: !isDeployed,
            authorization: authorization,
            initSignature: initSignature,
            structHash: structHash,
            leafHash: leafHash,
        )
    }

    private func buildInitializeOnlyExecuteLeaf(
        account: String,
        passkeyPublicKey: PasskeyPublicKeyModel,
        chainId: UInt64,
        salt: Data,
        authorizationsByChainId: [UInt64: RelayAuthorizationModel],
        signInitialize: (@Sendable (Data) async throws -> Data)? = nil,
    ) async throws -> ExecuteXResolvedExecuteLeaf {
        let initializeCall = try makeInitializeCall(
            account: account,
            passkeyPublicKey: passkeyPublicKey,
            chainId: chainId,
        )

        guard let authorization = authorizationsByChainId[chainId] else {
            throw ExecuteXPlannerError.missingAuthorization(chainId: chainId)
        }

        var initSignature: Data? = nil
        if let signInitialize {
            let callData = try AAUtils.hexToData(initializeCall.dataHex)
            let callDataHash = Data(callData.sha3(.keccak256))
            initSignature = try await signInitialize(callDataHash)
        }

        let calls = [initializeCall]
        let structHash = try SmartAccount.ExecuteX.structHash(calls: calls, salt: salt)
        let leafHash = try SmartAccount.ExecuteX.leafHash(
            account: account,
            chainId: chainId,
            structHash: structHash,
        )

        return ExecuteXResolvedExecuteLeaf(
            chainId: chainId,
            mode: .immediate,
            calls: calls,
            didAppendInitializeCall: true,
            authorizationRequired: true,
            authorization: authorization,
            initSignature: initSignature,
            structHash: structHash,
            leafHash: leafHash,
        )
    }

    private func makeInitializeCall(
        account: String,
        passkeyPublicKey: PasskeyPublicKeyModel,
        chainId: UInt64,
    ) throws -> Call {
        let initConfig = try InitializationConfig(
            accumulatorFactory: AAConstants.accumulatorFactoryAddress,
            spokePool: AAConstants.spokePoolAddress(chainId: chainId),
        )
        return try SmartAccount.Initialize.asCall(
            account: account,
            passkeyPublicKey: passkeyPublicKey,
            config: initConfig,
        )
    }
}
