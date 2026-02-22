import Foundation
import RPC
import Transactions

struct ExecuteXRelayEnvelopeBuilder {
    func buildPlan(
        request: ExecuteXPlanRequest,
        salt: Data,
        resolvedLeaves: [ExecuteXResolvedLeaf],
        signedMerkle: ExecuteXSignedMerkleBundle,
    ) throws -> ExecuteXPlan {
        var leafPlans: [ExecuteXLeafPlan] = []
        leafPlans.reserveCapacity(resolvedLeaves.count)

        var relayBuckets = RelayEnvelopeBuckets()
        var accumulatorExecutions: [PlannedAccumulatorExecution] = []

        for (index, resolvedLeaf) in resolvedLeaves.enumerated() {
            let proof = signedMerkle.proofs[index]

            if let executeLeaf = resolvedLeaf.execute {
                let calldata = try SmartAccount.ExecuteX.encodeCall(
                    calls: executeLeaf.calls,
                    salt: salt,
                    merkleProof: proof,
                    signature: signedMerkle.signature,
                )
                let relayTx = makeExecuteRelayEnvelope(
                    account: request.account,
                    chainId: executeLeaf.chainId,
                    calldata: calldata,
                    authorization: executeLeaf.authorization,
                )

                let plan = PlannedExecuteXCall(
                    chainId: executeLeaf.chainId,
                    mode: executeLeaf.mode,
                    calls: executeLeaf.calls,
                    didAppendInitializeCall: executeLeaf.didAppendInitializeCall,
                    authorizationRequired: executeLeaf.authorizationRequired,
                    structHash: executeLeaf.structHash,
                    leafHash: executeLeaf.leafHash,
                    merkleProof: proof,
                    executeXCalldata: calldata,
                    relayTx: relayTx,
                )

                leafPlans.append(
                    ExecuteXLeafPlan(
                        chainId: executeLeaf.chainId,
                        mode: executeLeaf.mode,
                        payload: .execute(plan),
                    ),
                )
                relayBuckets.append(relayTx, mode: executeLeaf.mode)
                continue
            }

            guard let accumulatorLeaf = resolvedLeaf.accumulator else {
                preconditionFailure("Resolved leaf must have either execute or accumulator payload.")
            }

            let executeIntentCall = try SmartAccount.Accumulator.asCall(
                accumulator: accumulatorLeaf.intent.accumulator,
                params: accumulatorLeaf.intent.params,
                merkleProof: proof,
                signature: signedMerkle.signature,
            )
            let relayTx = makeAccumulatorRelayEnvelope(
                account: request.account,
                chainId: accumulatorLeaf.chainId,
                accumulator: accumulatorLeaf.intent.accumulator,
                executeIntentCall: executeIntentCall,
            )

            let plannedAccumulatorExecution = PlannedAccumulatorExecution(
                chainId: accumulatorLeaf.chainId,
                mode: accumulatorLeaf.mode,
                intent: accumulatorLeaf.intent,
                structHash: accumulatorLeaf.structHash,
                leafHash: accumulatorLeaf.leafHash,
                merkleProof: proof,
                executeIntentCall: executeIntentCall,
                relayTx: relayTx,
            )
            accumulatorExecutions.append(plannedAccumulatorExecution)

            leafPlans.append(
                ExecuteXLeafPlan(
                    chainId: accumulatorLeaf.chainId,
                    mode: accumulatorLeaf.mode,
                    payload: .accumulator(plannedAccumulatorExecution),
                ),
            )
            relayBuckets.append(relayTx, mode: accumulatorLeaf.mode)
        }

        return ExecuteXPlan(
            account: request.account,
            salt: salt,
            merkleRoot: signedMerkle.root,
            signingDigest: signedMerkle.digest,
            signature: signedMerkle.signature,
            leaves: leafPlans,
            immediateRelayTxs: relayBuckets.immediateRelayTxs,
            backgroundRelayTxs: relayBuckets.backgroundRelayTxs,
            deferredRelayTxs: relayBuckets.deferredRelayTxs,
            accumulatorExecutions: accumulatorExecutions,
        )
    }

    private func makeExecuteRelayEnvelope(
        account: String,
        chainId: UInt64,
        calldata: Data,
        authorization: RelayAuthorizationModel?,
    ) -> RelayTransactionEnvelopeModel {
        let requestPayload = RelayTransactionRequestModel(
            from: account,
            to: account,
            data: "0x" + calldata.toHexString(),
            value: "0x0",
            isSponsored: true,
            authorizationList: authorization.map { [$0] } ?? [],
        )
        print(
            "   [DEBUG-ExecuteX] 🛠 Built Execute Relay Envelope (chain: \(chainId)) - isSponsored: \(requestPayload.isSponsored), authList count: \(requestPayload.authorizationList.count)",
        )
        return RelayTransactionEnvelopeModel(chainId: chainId, request: requestPayload)
    }

    private func makeAccumulatorRelayEnvelope(
        account: String,
        chainId: UInt64,
        accumulator: String,
        executeIntentCall: Call,
    ) -> RelayTransactionEnvelopeModel {
        let requestPayload = RelayTransactionRequestModel(
            from: account,
            to: accumulator,
            data: executeIntentCall.dataHex,
            value: "0x0",
            isSponsored: true,
            authorizationList: [],
        )
        return RelayTransactionEnvelopeModel(chainId: chainId, request: requestPayload)
    }
}

private struct RelayEnvelopeBuckets {
    var immediateRelayTxs: [RelayTransactionEnvelopeModel] = []
    var backgroundRelayTxs: [RelayTransactionEnvelopeModel] = []
    var deferredRelayTxs: [RelayTransactionEnvelopeModel] = []

    mutating func append(_ relayTx: RelayTransactionEnvelopeModel, mode: ExecuteXSubmissionMode) {
        switch mode {
        case .immediate:
            immediateRelayTxs.append(relayTx)
        case .background:
            backgroundRelayTxs.append(relayTx)
        case .deferred:
            deferredRelayTxs.append(relayTx)
        }
    }
}
