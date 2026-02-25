import AA
import AccountSetup
import BigInt
import Compose
import Foundation
import Passkey
import RPC
internal import SignHandler
import Transactions
import web3swift

@MainActor
final class AAExecutionService {
    private let rpcClient: RPCClient
    private let executeXPlanner: ExecuteXPlanner

    init(
        rpcClient: RPCClient = RPCClient(),
        executeXPlanner: ExecuteXPlanner = ExecuteXPlanner(),
    ) {
        self.rpcClient = rpcClient
        self.executeXPlanner = executeXPlanner
    }

    func executeCalls(
        accountService: AccountSetupService,
        account: AccountSession,
        chainId: UInt64,
        calls: [Call],
    ) async throws -> String {
        let result = try await executeChainActions(
            accountService: accountService,
            account: account,
            destinationChainId: chainId,
            chainActions: [ChainActionModel(chainId: chainId, calls: calls)],
        )
        return result.destinationSubmission.id
    }

    func estimateExecutionFee(
        chainId: UInt64,
    ) async throws -> Decimal {
        let totalGasLimit: BigUInt = 600_000 // A static upper limit for UI estimation
        let fastFeeWei = try await rpcClient.getEIP1559FastFee(chainId: chainId)
        let totalWei = totalGasLimit * fastFeeWei
        guard let decimal = Decimal(string: totalWei.description) else {
            return 0
        }
        return decimal / 1_000_000_000_000_000_000
    }

    func executeChainActions(
        accountService: AccountSetupService,
        account: AccountSession,
        destinationChainId: UInt64,
        chainActions: [ChainActionModel],
        destinationAccumulatorIntent: AccumulatorExecutionIntent? = nil,
    ) async throws -> AAExecutionSubmissionResultModel {
        guard !chainActions.isEmpty else {
            throw AAExecutionServiceError.executionFailed(SmartAccountError.emptyCalls)
        }

        do {
            let context = try await makeContext(accountService: accountService, account: account)

            let plan = try await buildFlowPlan(
                accountService: accountService,
                context: context,
                destinationChainId: destinationChainId,
                chainActions: chainActions,
                destinationAccumulatorIntent: destinationAccumulatorIntent,
            )

            let submitResult = try await rpcClient.relaySubmit(
                account: context.account.eoaAddress,
                supportMode: currentSupportMode(),
                immediateTxs: plan.immediateRelayTxs,
                backgroundTxs: plan.backgroundRelayTxs,
                deferredTxs: plan.deferredRelayTxs,
            )

            let allSubmissions =
                submitResult.immediateSubmissions
                    + submitResult.backgroundSubmissions
                    + submitResult.deferredSubmissions
            let destinationSubmissionID =
                allSubmissions.last(where: { $0.chainId == destinationChainId })?.id
                    ?? allSubmissions.last?.id

            guard let destinationSubmissionID else {
                throw AAExecutionServiceError.missingRelaySubmission(chainId: destinationChainId)
            }

            let destinationSubmission =
                allSubmissions.last(where: { $0.id == destinationSubmissionID })
                    ?? RelaySubmissionModel(
                        chainId: destinationChainId,
                        id: destinationSubmissionID,
                        transactionHash: nil,
                    )

            return AAExecutionSubmissionResultModel(
                destinationSubmission: destinationSubmission,
                immediateSubmissions: submitResult.immediateSubmissions,
                backgroundSubmissions: submitResult.backgroundSubmissions,
                deferredSubmissions: submitResult.deferredSubmissions,
            )
        } catch {
            if let handled = error as? AAExecutionServiceError {
                throw handled
            }
            throw AAExecutionServiceError.relayFailed(error)
        }
    }

    func waitForRelayInclusion(
        chainId: UInt64,
        relayTaskID: String,
        timeout: TimeInterval = 180,
        pollInterval: TimeInterval = 2,
    ) async throws -> Date {
        let startedAt = Date()
        let relayID = relayTaskID.trimmingCharacters(in: .whitespacesAndNewlines)

        while Date().timeIntervalSince(startedAt) < timeout {
            let status = try await rpcClient.relayStatus(id: relayID)

            switch status.state.lowercased() {
            case "executed", "success":
                if let blockNumber = status.blockNumber {
                    return try await resolveBlockTimestamp(chainId: chainId, blockNumber: blockNumber)
                }
                if let txHash = status.transactionHash {
                    return try await resolveTxTimestamp(chainId: chainId, txHash: txHash)
                }
                return Date()
            case "failed", "reverted", "cancelled":
                throw AAExecutionServiceError.relayStatusFailed(
                    chainId: chainId,
                    id: relayID,
                    status: status.rawStatus,
                    reason: status.failureReason,
                )
            default:
                break
            }

            try await Task.sleep(for: .seconds(pollInterval))
        }

        throw AAExecutionServiceError.relayFailed(
            RPCError.rpcError(code: -1, message: "Timed out waiting for relay task status"),
        )
    }

    func relayStatus(relayTaskID: String) async throws -> RelayStatusModel {
        try await rpcClient.relayStatus(id: relayTaskID)
    }

    private func makeContext(
        accountService: AccountSetupService,
        account: AccountSession,
    ) async throws -> ExecutionContext {
        let passkey = try await accountService.passkeyPublicKeyData(for: account)
        return ExecutionContext(account: account, passkey: passkey)
    }

    private func buildFlowPlan(
        accountService: AccountSetupService,
        context: ExecutionContext,
        destinationChainId: UInt64,
        chainActions: [ChainActionModel],
        destinationAccumulatorIntent: AccumulatorExecutionIntent?,
    ) async throws -> ExecuteXPlan {
        var authorizationsByChainID: [UInt64: RelayAuthorizationModel] = [:]

        while true {
            let flowRequest = ExecuteXFlowPlanRequest(
                account: context.account.eoaAddress,
                passkeyPublicKey: context.passkey,
                destinationChainId: destinationChainId,
                chainActions: chainActions.map { action in
                    ExecuteXChainAction(chainId: action.chainId, calls: action.calls)
                },
                destinationAccumulatorIntent: destinationAccumulatorIntent,
                destinationAccumulatorMode: .deferred,
                authorizationsByChainId: authorizationsByChainID,
            )

            do {
                return try await executeXPlanner.buildFlowPlan(
                    request: flowRequest,
                    signRoot: { digest in
                        do {
                            return try await accountService.signWithStoredPasskey(
                                account: context.account,
                                payload: digest,
                            )
                        } catch {
                            throw AAExecutionServiceError.signingFailed(error)
                        }
                    },
                    signInitialize: { callDataHash in
                        do {
                            return try await accountService.signEthDigestWithStoredWallet(
                                account: context.account,
                                digest32: callDataHash,
                            )
                        } catch {
                            throw AAExecutionServiceError.signingFailed(error)
                        }
                    },
                )
            } catch let plannerError as ExecuteXPlannerError {
                guard case let .missingAuthorization(chainID) = plannerError else {
                    throw plannerError
                }
                guard authorizationsByChainID[chainID] == nil else {
                    throw plannerError
                }

                let auth = try await relayAuthorization(
                    accountService: accountService,
                    account: context.account,
                    chainId: chainID,
                )
                authorizationsByChainID[chainID] = auth
            }
        }
    }

    private func relayAuthorization(
        accountService: AccountSetupService,
        account: AccountSession,
        chainId: UInt64,
    ) async throws -> RelayAuthorizationModel {
        let auth = try await accountService.jitSignedAuthorization(
            account: account, chainId: chainId,
        )
        return RelayAuthorizationModel(
            address: auth.delegateAddress,
            chainId: auth.chainId,
            nonce: auth.nonce,
            r: auth.r,
            s: auth.s,
            yParity: auth.yParity,
        )
    }

    private func resolveTxTimestamp(chainId: UInt64, txHash: String) async throws -> Date {
        struct TransactionReceiptEnvelope: Decodable {
            let blockNumber: String
        }

        let receipt: TransactionReceiptEnvelope = try await rpcClient.makeRpcCall(
            chainId: chainId,
            method: "eth_getTransactionReceipt",
            params: [AnyCodable(txHash)],
            responseType: TransactionReceiptEnvelope.self,
        )

        return try await resolveBlockTimestamp(chainId: chainId, blockNumber: receipt.blockNumber)
    }

    private func resolveBlockTimestamp(chainId: UInt64, blockNumber: String) async throws -> Date {
        struct BlockTimestampEnvelope: Decodable {
            let timestamp: String
        }

        let block: BlockTimestampEnvelope = try await rpcClient.makeRpcCall(
            chainId: chainId,
            method: "eth_getBlockByNumber",
            params: [AnyCodable(blockNumber), AnyCodable(false)],
            responseType: BlockTimestampEnvelope.self,
        )

        let timestampHex = block.timestamp.replacingOccurrences(of: "0x", with: "")
        guard let timestamp = UInt64(timestampHex, radix: 16) else {
            throw AAExecutionServiceError.relayFailed(
                RPCError.rpcError(code: -1, message: "Invalid block timestamp"),
            )
        }
        return Date(timeIntervalSince1970: TimeInterval(timestamp))
    }

    private func currentSupportMode() -> ChainSupportMode {
        ChainSupportRuntime.resolveMode()
    }
}

struct AAExecutionSubmissionResultModel: Sendable {
    let destinationSubmission: RelaySubmissionModel
    let immediateSubmissions: [RelaySubmissionModel]
    let backgroundSubmissions: [RelaySubmissionModel]
    let deferredSubmissions: [RelaySubmissionModel]
}

private struct ExecutionContext {
    let account: AccountSession
    let passkey: PasskeyPublicKeyModel
}
