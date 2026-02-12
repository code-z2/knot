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
    }
  }
}

@MainActor
final class AAExecutionService {
  private let smartAccountClient: SmartAccountClient
  private let aaClient: AAClient
  private let rpcClient: RPCClient

  private let executionDeadlineWindow: UInt64 = 15 * 60

  init(
    smartAccountClient: SmartAccountClient = SmartAccountClient(),
    aaClient: AAClient = AAClient(),
    rpcClient: RPCClient = RPCClient()
  ) {
    self.smartAccountClient = smartAccountClient
    self.aaClient = aaClient
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

      _ = try await ensureInitializedIfNeeded(
        accountService: accountService,
        context: context,
        chainId: chainId,
        waitForCompletion: true
      )

      let executionData = try await buildSignedExecutionData(
        accountService: accountService,
        context: context,
        chainId: chainId,
        calls: calls
      )

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

      let gasLimit = try await estimateGasWithFallback(
        chainId: chainId,
        from: context.account.eoaAddress,
        to: context.account.eoaAddress,
        data: executionData
      )

      var request = RelayerTransactionRequest(
        from: context.account.eoaAddress,
        to: context.account.eoaAddress,
        data: "0x" + hexString(executionData),
        gasLimit: gasLimit,
        isSponsored: true
      )

      _ = try? await aaClient.getFeeQuote(chainId: chainId, request: request)

      let submission = try await aaClient.sendTransaction(chainId: chainId, request: request)
      return submission.id
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

      // Destination chain is hard-gated first. If destination needs init, it is relayed sync and waited.
      let destinationSubmission = try await submitBundle(
        accountService: accountService,
        context: context,
        bundle: destinationBundle,
        syncSend: true,
        waitForCompletion: true
      )

      let otherSubmissions: [String] = try await withThrowingTaskGroup(of: String?.self) { group in
        for bundle in otherBundles {
          group.addTask {
            try await self.submitBundle(
              accountService: accountService,
              context: context,
              bundle: bundle,
              syncSend: false,
              waitForCompletion: false
            )
          }
        }

        var ids: [String] = []
        for try await maybeID in group {
          if let id = maybeID { ids.append(id) }
        }
        return ids
      }

      return (
        destinationSubmission: destinationSubmission ?? "noop",
        otherSubmissions: otherSubmissions
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
    pollInterval: TimeInterval = 2
  ) async throws -> Date {
    let startedAt = Date()
    let relayID = relayTaskID.trimmingCharacters(in: .whitespacesAndNewlines)

    while Date().timeIntervalSince(startedAt) < timeout {
      let status = try await aaClient.getStatus(chainId: chainId, id: relayID)

      switch status.state {
      case .executed, .success:
        if let blockNumber = status.blockNumber {
          return try await resolveBlockTimestamp(chainId: chainId, blockNumber: blockNumber)
        }
        if let txHash = status.transactionHash {
          return try await resolveTxTimestamp(chainId: chainId, txHash: txHash)
        }
        return Date()
      case .failed, .reverted, .cancelled:
        throw AAExecutionServiceError.relayStatusFailed(
          chainId: chainId,
          id: relayID,
          status: status.rawStatus,
          reason: status.failureReason
        )
      case .pending, .waiting, .unknown:
        break
      }

      try? await Task.sleep(for: .seconds(pollInterval))
    }

    throw AAExecutionServiceError.relayFailed(
      RPCError.rpcError(code: -1, message: "Timed out waiting for relay task status")
    )
  }

  private func makeContext(
    accountService: AccountSetupService,
    account: AccountIdentity
  ) async throws -> ExecutionContext {
    let sessionAccount = try await accountService.restoreSession(eoaAddress: account.eoaAddress)
    let passkey = try await accountService.passkeyPublicKeyData(for: sessionAccount)
    return ExecutionContext(account: sessionAccount, passkey: passkey)
  }

  private func submitBundle(
    accountService: AccountSetupService,
    context: ExecutionContext,
    bundle: ChainCalls,
    syncSend: Bool,
    waitForCompletion: Bool
  ) async throws -> String? {
    do {
      let initSubmission = try await ensureInitializedIfNeeded(
        accountService: accountService,
        context: context,
        chainId: bundle.chainId,
        waitForCompletion: true
      )

      guard !bundle.calls.isEmpty else {
        return initSubmission
      }

      let executionData = try await buildSignedExecutionData(
        accountService: accountService,
        context: context,
        chainId: bundle.chainId,
        calls: bundle.calls
      )

      do {
        try await smartAccountClient.simulateCall(
          account: context.account.eoaAddress,
          chainId: bundle.chainId,
          from: context.account.eoaAddress,
          data: executionData
        )
      } catch {
        throw AAExecutionServiceError.simulationFailed(chainId: bundle.chainId, underlying: error)
      }

      let gasLimit = try await estimateGasWithFallback(
        chainId: bundle.chainId,
        from: context.account.eoaAddress,
        to: context.account.eoaAddress,
        data: executionData
      )

      let request = RelayerTransactionRequest(
        from: context.account.eoaAddress,
        to: context.account.eoaAddress,
        data: "0x" + hexString(executionData),
        gasLimit: gasLimit,
        isSponsored: true
      )

      _ = try? await aaClient.getFeeQuote(chainId: bundle.chainId, request: request)

      let submission = try await (syncSend
        ? aaClient.sendTransactionSync(chainId: bundle.chainId, request: request)
        : aaClient.sendTransaction(chainId: bundle.chainId, request: request)
      )

      if waitForCompletion {
        _ = try await waitForTerminalRelayState(chainId: bundle.chainId, relayID: submission.id)
      }

      return submission.id
    } catch {
      throw AAExecutionServiceError.chainBundleFailed(chainId: bundle.chainId, underlying: error)
    }
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

  private func ensureInitializedIfNeeded(
    accountService: AccountSetupService,
    context: ExecutionContext,
    chainId: UInt64,
    waitForCompletion: Bool
  ) async throws -> String? {
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
      let relayAuth = RelayerAuthorization(
        address: auth.delegateAddress,
        chainId: "0x" + String(auth.chainId, radix: 16),
        nonce: "0x" + String(auth.nonce, radix: 16),
        r: auth.r,
        s: auth.s,
        yParity: "0x" + String(auth.yParity, radix: 16)
      )

      // First-touch tx: per product decision we skip gas estimation and sponsor initialize directly.
      let request = RelayerTransactionRequest(
        from: context.account.eoaAddress,
        to: context.account.eoaAddress,
        data: "0x" + hexString(initializeData),
        isSponsored: true,
        authorization: relayAuth
      )

      let submission = try await aaClient.sendTransactionSync(chainId: chainId, request: request)
      if waitForCompletion {
        _ = try await waitForTerminalRelayState(chainId: chainId, relayID: submission.id)
      }
      return submission.id
    } catch {
      throw AAExecutionServiceError.initializationFailed(chainId: chainId, underlying: error)
    }
  }

  private func waitForTerminalRelayState(
    chainId: UInt64,
    relayID: String,
    timeout: TimeInterval = 240,
    pollInterval: TimeInterval = 2
  ) async throws -> RelayerStatus {
    let startedAt = Date()

    while Date().timeIntervalSince(startedAt) < timeout {
      let status = try await aaClient.getStatus(chainId: chainId, id: relayID)

      switch status.state {
      case .executed, .success:
        return status
      case .failed, .reverted, .cancelled:
        throw AAExecutionServiceError.relayStatusFailed(
          chainId: chainId,
          id: relayID,
          status: status.rawStatus,
          reason: status.failureReason
        )
      case .pending, .waiting, .unknown:
        try? await Task.sleep(for: .seconds(pollInterval))
      }
    }

    throw AAExecutionServiceError.relayFailed(
      RPCError.rpcError(code: -1, message: "Timed out waiting for relay task completion")
    )
  }

  private func estimateGasWithFallback(
    chainId: UInt64,
    from: String,
    to: String,
    data: Data
  ) async throws -> String {
    do {
      return try await aaClient.estimateGas(
        chainId: chainId,
        from: from,
        to: to,
        data: "0x" + hexString(data),
        value: "0x0"
      )
    } catch {
      // Conservative fallback for signature-validated account execute/executeBatch paths.
      return "0x0f4240"  // 1,000,000
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

  private func hexString(_ data: Data) -> String {
    data.map { String(format: "%02x", $0) }.joined()
  }
}

private struct ExecutionContext {
  let account: AccountIdentity
  let passkey: PasskeyPublicKey
}
