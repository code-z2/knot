import AA
import AccountSetup
import Foundation
import Passkey
import RPC
internal import SignHandler
import Transactions

enum AAExecutionServiceError: Error {
  case executionFailed(Error)
  case relayFailed(Error)
  case signingFailed(Error)
  case initializationFailed(chainId: UInt64, underlying: Error)
  case simulationFailed(chainId: UInt64, underlying: Error)
  case chainBundleFailed(chainId: UInt64, underlying: Error)
  case relayStatusFailed(chainId: UInt64, id: String, status: String, reason: String?)
  case missingRelaySubmission(chainId: UInt64)
}

extension AAExecutionServiceError: LocalizedError {
  var errorDescription: String? {
    switch self {
    case .executionFailed(let error):
      return "AA execution failed: \(error.localizedDescription)"
    case .relayFailed(let error):
      return "Relay flow failed: \(error.localizedDescription)"
    case .signingFailed(let error):
      return "Signing failed: \(error.localizedDescription)"
    case .initializationFailed(let chainId, let underlying):
      return "Initialization failed on chain \(chainId): \(underlying.localizedDescription)"
    case .simulationFailed(let chainId, let underlying):
      return "Simulation failed on chain \(chainId): \(underlying.localizedDescription)"
    case .chainBundleFailed(let chainId, let underlying):
      return "Bundle failed on chain \(chainId): \(underlying.localizedDescription)"
    case .relayStatusFailed(let chainId, let id, let status, let reason):
      if let reason, !reason.isEmpty {
        return "Relay task \(id) failed on chain \(chainId) with status \(status): \(reason)"
      }
      return "Relay task \(id) failed on chain \(chainId) with status \(status)"
    case .missingRelaySubmission(let chainId):
      return "Relay submission missing for chain \(chainId)"
    }
  }
}

@MainActor
final class AAExecutionService {
  private let smartAccountClient: SmartAccountClient
  private let rpcClient: RPCClient

  private let executionDeadlineWindow: UInt64 = 15 * 60
  private let defaultGasLimitHex = "0x0f4240"  // 1,000,000

  init(
    smartAccountClient: SmartAccountClient = SmartAccountClient(),
    rpcClient: RPCClient = RPCClient()
  ) {
    self.smartAccountClient = smartAccountClient
    self.rpcClient = rpcClient
  }

  func executeCalls(
    accountService: AccountSetupService,
    account: AccountIdentity,
    chainId: UInt64,
    calls: [Call]
  ) async throws -> String {
    guard !calls.isEmpty else {
      throw AAExecutionServiceError.executionFailed(SmartAccountError.emptyCalls)
    }

    do {
      let context = try await makeContext(accountService: accountService, account: account)
      var priorityTxs: [RelayTx] = []

      if let initRequest = try await buildInitializationRequestIfNeeded(
        accountService: accountService,
        context: context,
        chainId: chainId
      ) {
        priorityTxs.append(RelayTx(chainId: chainId, request: initRequest))
      }
      let needsInitialization = priorityTxs.contains(where: { $0.request.authorization != nil })

      let executionRequest = try await buildExecutionRequest(
        accountService: accountService,
        context: context,
        chainId: chainId,
        calls: calls,
        skipPreflight: needsInitialization
      )
      priorityTxs.append(RelayTx(chainId: chainId, request: executionRequest))

      let submitResult = try await rpcClient.relaySubmit(
        account: context.account.eoaAddress,
        supportMode: currentSupportMode(),
        priorityTxs: priorityTxs,
        txs: []
      )

      guard let executionSubmission = submitResult.prioritySubmissions.last(where: { $0.chainId == chainId }) else {
        throw AAExecutionServiceError.missingRelaySubmission(chainId: chainId)
      }
      return executionSubmission.id
    } catch {
      if let handled = error as? AAExecutionServiceError {
        throw handled
      }
      throw AAExecutionServiceError.executionFailed(error)
    }
  }

  func executeChainCalls(
    accountService: AccountSetupService,
    account: AccountIdentity,
    destinationChainId: UInt64,
    chainCalls: [ChainCalls]
  ) async throws -> (destinationSubmission: String, otherSubmissions: [String]) {
    guard !chainCalls.isEmpty else {
      throw AAExecutionServiceError.executionFailed(SmartAccountError.emptyCalls)
    }

    do {
      let context = try await makeContext(accountService: accountService, account: account)

      let destinationBundle = chainCalls.first(where: { $0.chainId == destinationChainId })
        ?? ChainCalls(chainId: destinationChainId, calls: [])
      let otherBundles = chainCalls.filter { $0.chainId != destinationChainId }

      var priorityTxs: [RelayTx] = []
      var txs: [RelayTx] = []

      try await appendBundleTransactions(
        accountService: accountService,
        context: context,
        bundle: destinationBundle,
        target: &priorityTxs
      )

      for bundle in otherBundles {
        try await appendBundleTransactions(
          accountService: accountService,
          context: context,
          bundle: bundle,
          target: &txs
        )
      }

      let submitResult = try await rpcClient.relaySubmit(
        account: context.account.eoaAddress,
        supportMode: currentSupportMode(),
        priorityTxs: priorityTxs,
        txs: txs
      )

      let destinationSubmissionID =
        submitResult.prioritySubmissions.last(where: { $0.chainId == destinationChainId })?.id
        ?? submitResult.submissions.last(where: { $0.chainId == destinationChainId })?.id

      guard let destinationSubmissionID else {
        throw AAExecutionServiceError.missingRelaySubmission(chainId: destinationChainId)
      }

      let otherSubmissionIDs = (submitResult.prioritySubmissions + submitResult.submissions)
        .filter { $0.chainId != destinationChainId }
        .map(\.id)

      return (destinationSubmission: destinationSubmissionID, otherSubmissions: otherSubmissionIDs)
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
    pollInterval: TimeInterval = 2
  ) async throws -> Date {
    let startedAt = Date()
    let relayID = relayTaskID.trimmingCharacters(in: .whitespacesAndNewlines)

    while Date().timeIntervalSince(startedAt) < timeout {
      let status = try await rpcClient.relayStatus(chainId: chainId, id: relayID)

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
          reason: status.failureReason
        )
      default:
        break
      }

      try? await Task.sleep(for: .seconds(pollInterval))
    }

    throw AAExecutionServiceError.relayFailed(
      RPCError.rpcError(code: -1, message: "Timed out waiting for relay task status")
    )
  }

  private func appendBundleTransactions(
    accountService: AccountSetupService,
    context: ExecutionContext,
    bundle: ChainCalls,
    target: inout [RelayTx]
  ) async throws {
    do {
      if let initRequest = try await buildInitializationRequestIfNeeded(
        accountService: accountService,
        context: context,
        chainId: bundle.chainId
      ) {
        target.append(RelayTx(chainId: bundle.chainId, request: initRequest))
      }
      let needsInitialization = target.contains {
        $0.chainId == bundle.chainId && $0.request.authorization != nil
      }

      guard !bundle.calls.isEmpty else {
        return
      }

      let executionRequest = try await buildExecutionRequest(
        accountService: accountService,
        context: context,
        chainId: bundle.chainId,
        calls: bundle.calls,
        skipPreflight: needsInitialization
      )
      target.append(RelayTx(chainId: bundle.chainId, request: executionRequest))
    } catch {
      throw AAExecutionServiceError.chainBundleFailed(chainId: bundle.chainId, underlying: error)
    }
  }

  private func makeContext(
    accountService: AccountSetupService,
    account: AccountIdentity
  ) async throws -> ExecutionContext {
    let sessionAccount = try await accountService.restoreSession(eoaAddress: account.eoaAddress)
    let passkey = try await accountService.passkeyPublicKeyData(for: sessionAccount)
    return ExecutionContext(account: sessionAccount, passkey: passkey)
  }

  private func buildExecutionRequest(
    accountService: AccountSetupService,
    context: ExecutionContext,
    chainId: UInt64,
    calls: [Call],
    skipPreflight: Bool = false
  ) async throws -> RelayTransactionRequest {
    let executionData = try await buildSignedExecutionData(
      accountService: accountService,
      context: context,
      chainId: chainId,
      calls: calls
    )

    if !skipPreflight {
      do {
        try await smartAccountClient.simulateCall(
          account: context.account.eoaAddress,
          chainId: chainId,
          from: context.account.eoaAddress,
          data: executionData
        )
      } catch {
        throw AAExecutionServiceError.simulationFailed(chainId: chainId, underlying: error)
      }
    }

    let gasLimit: String
    if skipPreflight {
      gasLimit = defaultGasLimitHex
    } else {
      gasLimit = try await estimateGasWithFallback(
        chainId: chainId,
        from: context.account.eoaAddress,
        to: context.account.eoaAddress,
        data: executionData
      )
    }

    return RelayTransactionRequest(
      from: context.account.eoaAddress,
      to: context.account.eoaAddress,
      data: "0x" + hexString(executionData),
      gasLimit: gasLimit,
      isSponsored: true
    )
  }

  private func buildSignedExecutionData(
    accountService: AccountSetupService,
    context: ExecutionContext,
    chainId: UInt64,
    calls: [Call]
  ) async throws -> Data {
    let nonce = try await smartAccountClient.getTransactionCount(
      account: context.account.eoaAddress,
      chainId: chainId,
      blockTag: "pending"
    )
    let deadline = UInt64(Date().timeIntervalSince1970) + executionDeadlineWindow

    if calls.count == 1, let call = calls.first {
      let digest = try SmartAccount.ExecuteAuthorized.hashSingle(
        account: context.account.eoaAddress,
        chainId: chainId,
        call: call,
        nonce: nonce,
        deadline: deadline
      )
      let signature: Data
      do {
        signature = try await accountService.signPayloadWithStoredPasskey(
          account: context.account,
          payload: digest
        )
      } catch {
        throw AAExecutionServiceError.signingFailed(error)
      }

      return try SmartAccount.ExecuteAuthorized.encodeSingle(
        call: call,
        nonce: nonce,
        deadline: deadline,
        signature: signature
      )
    }

    let digest = try SmartAccount.ExecuteAuthorized.hashBatch(
      account: context.account.eoaAddress,
      chainId: chainId,
      calls: calls,
      nonce: nonce,
      deadline: deadline
    )
    let signature: Data
    do {
      signature = try await accountService.signPayloadWithStoredPasskey(
        account: context.account,
        payload: digest
      )
    } catch {
      throw AAExecutionServiceError.signingFailed(error)
    }

    return try SmartAccount.ExecuteAuthorized.encodeBatch(
      calls: calls,
      nonce: nonce,
      deadline: deadline,
      signature: signature
    )
  }

  private func buildInitializationRequestIfNeeded(
    accountService: AccountSetupService,
    context: ExecutionContext,
    chainId: UInt64
  ) async throws -> RelayTransactionRequest? {
    let isDeployed = try await smartAccountClient.isDeployed(account: context.account.eoaAddress, chainId: chainId)
    if isDeployed {
      return nil
    }

    do {
      let initConfig = try InitializationConfig(
        accumulatorFactory: AAConstants.accumulatorFactoryAddress,
        wrappedNativeToken: AAConstants.wrappedNativeTokenAddress(chainId: chainId),
        spokePool: AAConstants.spokePoolAddress(chainId: chainId)
      )

      let digest = try SmartAccount.Initialize.initSignatureDigest(
        account: context.account.eoaAddress,
        chainId: chainId,
        passkeyPublicKey: context.passkey,
        config: initConfig
      )

      let initSignature = try await accountService.signEthMessageDigestWithStoredWallet(
        account: context.account,
        digest32: digest
      )

      let initializeData = try SmartAccount.Initialize.encodeCall(
        passkeyPublicKey: context.passkey,
        config: initConfig,
        initSignature: initSignature
      )

      let auth = try await accountService.storedSignedAuthorization(account: context.account, chainId: chainId)
      let relayAuth = RelayAuthorization(
        address: auth.delegateAddress,
        chainId: "0x" + String(auth.chainId, radix: 16),
        nonce: "0x" + String(auth.nonce, radix: 16),
        r: auth.r,
        s: auth.s,
        yParity: "0x" + String(auth.yParity, radix: 16)
      )

      return RelayTransactionRequest(
        from: context.account.eoaAddress,
        to: context.account.eoaAddress,
        data: "0x" + hexString(initializeData),
        isSponsored: true,
        authorization: relayAuth
      )
    } catch {
      throw AAExecutionServiceError.initializationFailed(chainId: chainId, underlying: error)
    }
  }

  private func estimateGasWithFallback(
    chainId: UInt64,
    from: String,
    to: String,
    data: Data
  ) async throws -> String {
    do {
      let estimate = try await smartAccountClient.estimateGas(
        account: to,
        chainId: chainId,
        from: from,
        data: data,
        valueHex: "0x0"
      )
      return "0x" + String(estimate, radix: 16)
    } catch {
      return defaultGasLimitHex
    }
  }

  private func resolveTxTimestamp(chainId: UInt64, txHash: String) async throws -> Date {
    struct TransactionReceiptEnvelope: Decodable {
      let blockNumber: String
    }

    let receipt: TransactionReceiptEnvelope = try await rpcClient.makeRpcCall(
      chainId: chainId,
      method: "eth_getTransactionReceipt",
      params: [AnyCodable(txHash)],
      responseType: TransactionReceiptEnvelope.self
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
      responseType: BlockTimestampEnvelope.self
    )

    let timestampHex = block.timestamp.replacingOccurrences(of: "0x", with: "")
    guard let timestamp = UInt64(timestampHex, radix: 16) else {
      throw AAExecutionServiceError.relayFailed(
        RPCError.rpcError(code: -1, message: "Invalid block timestamp")
      )
    }
    return Date(timeIntervalSince1970: TimeInterval(timestamp))
  }

  private func currentSupportMode() -> RelaySupportMode {
    switch ChainSupportRuntime.resolveMode() {
    case .limitedTestnet:
      return .limitedTestnet
    case .limitedMainnet:
      return .limitedMainnet
    case .fullMainnet:
      return .fullMainnet
    }
  }

  private func hexString(_ data: Data) -> String {
    data.map { String(format: "%02x", $0) }.joined()
  }
}

private struct ExecutionContext {
  let account: AccountIdentity
  let passkey: PasskeyPublicKey
}
