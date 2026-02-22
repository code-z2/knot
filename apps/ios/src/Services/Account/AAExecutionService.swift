import AA
import AccountSetup
import Compose
import Foundation
import Passkey
import RPC
internal import SignHandler
import Transactions

enum AAExecutionServiceError: Error {
    case executionFailed(Error)
    case relayFailed(Error)
    case signingFailed(Error)
    case invalidExecutionPlan(reason: String)
    case relayStatusFailed(chainId: UInt64, id: String, status: String, reason: String?)
    case missingRelaySubmission(chainId: UInt64)
}

extension AAExecutionServiceError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case let .executionFailed(error):
            return "AA execution failed: \(error.localizedDescription)"
        case let .relayFailed(error):
            return "Relay flow failed: \(error.localizedDescription)"
        case let .signingFailed(error):
            return "Signing failed: \(error.localizedDescription)"
        case let .invalidExecutionPlan(reason):
            return "Invalid execution plan: \(reason)"
        case let .relayStatusFailed(chainId, id, status, reason):
            if let reason, !reason.isEmpty {
                return "Relay task \(id) failed on chain \(chainId) with status \(status): \(reason)"
            }
            return "Relay task \(id) failed on chain \(chainId) with status \(status)"
        case let .missingRelaySubmission(chainId):
            return "Relay submission missing for chain \(chainId)"
        }
    }
}

@MainActor
final class AAExecutionService {
    private let rpcClient: RPCClient
    private let executeXPlanner: ExecuteXPlanner
    private let biometricAuth: BiometricAuthService

    init(
        rpcClient: RPCClient = RPCClient(),
        executeXPlanner: ExecuteXPlanner = ExecuteXPlanner(),
        biometricAuth: BiometricAuthService? = nil,
    ) {
        self.rpcClient = rpcClient
        self.executeXPlanner = executeXPlanner
        self.biometricAuth = biometricAuth ?? BiometricAuthService()
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

            print(
                "⚙️ [AAExecutionService] Building ExecuteX Flow Plan for destination chain \(destinationChainId)",
            )
            for action in chainActions {
                print("   - Chain Action (\(action.chainId)): \(action.calls.count) calls")
                for (i, call) in action.calls.enumerated() {
                    print("     - Call \(i) Value (Wei): \(call.valueWei)")
                }
            }

            let plan = try await buildFlowPlan(
                accountService: accountService,
                context: context,
                destinationChainId: destinationChainId,
                chainActions: chainActions,
                destinationAccumulatorIntent: destinationAccumulatorIntent,
            )
            print("✅ [AAExecutionService] Flow Plan built successfully.")

            print("🚀 [AAExecutionService] Submitting Flow Plan to Relayer...")
            let submitResult = try await rpcClient.relaySubmit(
                account: context.account.eoaAddress,
                supportMode: currentSupportMode(),
                immediateTxs: plan.immediateRelayTxs,
                backgroundTxs: plan.backgroundRelayTxs,
                deferredTxs: plan.deferredRelayTxs,
            )
            print("✅ [AAExecutionService] Relayer submission accepted.")

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
        let sessionAccount = try await accountService.restoreSession(eoaAddress: account.eoaAddress)
        let passkey = try await accountService.passkeyPublicKeyData(for: sessionAccount)
        return ExecutionContext(account: sessionAccount, passkey: passkey)
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
        try await biometricAuth.authenticate(reason: "Authenticate to sign transaction")
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
