import AA
import Foundation
import Transactions
import AccountSetup
internal import CryptoSwift
internal import SignHandler
internal import BigInt


enum AAExecutionServiceError: Error {
  case executionFailed(Error)
  case userOperationFailed(Error)
  case signingFailed(Error)
}

extension AAExecutionServiceError: LocalizedError {
  var errorDescription: String? {
    switch self {
    case .executionFailed(let error):
      return "AA execution failed: \(error.localizedDescription)"
    case .userOperationFailed(let error):
      return "UserOperation flow failed: \(error.localizedDescription)"
    case .signingFailed(let error):
      return "Passkey signing failed: \(error.localizedDescription)"
    }
  }
}

@MainActor
final class AAExecutionService {
  private let smartAccountClient: SmartAccountClient
  private let aaClient: AAClient

  init(
    smartAccountClient: SmartAccountClient = SmartAccountClient(),
    aaClient: AAClient = AAClient()
  ) {
    self.smartAccountClient = smartAccountClient
    self.aaClient = aaClient
  }

  func executeCalls(
    accountService: AccountSetupService,
    account: AccountIdentity,
    chainId: UInt64,
    calls: [Call]
  ) async throws -> String {
    do {
      let context = try await makeContext(accountService: accountService, account: account)
      let passkey = try await accountService.passkeyPublicKeyData(for: context.account)
      let execute = try await smartAccountClient.execute(
        account: context.account.eoaAddress,
        chainId: chainId,
        passkeyPublicKey: passkey,
        calls: calls
      )
      let userOp = try await buildAndSign(
        accountService: accountService,
        context: context,
        chainId: chainId,
        payload: execute.payload
      )
      return try await sendUserOperation(userOp, useSyncSend: false
)
    } catch {
      throw AAExecutionServiceError.executionFailed(error)
    }
  }

  func executeChainCalls(
    accountService: AccountSetupService,
    account: AccountIdentity,
    destinationChainId: UInt64,
    jobId: Data,
    chainCalls: [ChainCalls]
  ) async throws -> ExecuteChainCallsResult {
    do {
      let context = try await makeContext(accountService: accountService, account: account)
      let passkey = try await accountService.passkeyPublicKeyData(for: context.account)
      let execute = try await smartAccountClient.executeChainCalls(
        account: context.account.eoaAddress,
        destinationChainId: destinationChainId,
        jobId: jobId,
        passkeyPublicKey: passkey,
        chainCalls: chainCalls
      )

      // 1. Build Ops in Parallel
      let unsignedOps: [UserOperation] = try await withThrowingTaskGroup(of: UserOperation.self) { group in
        for call in chainCalls {
          group.addTask {
            return try await self.buildUserOperation(
              context: context,
              chainId: call.chainId,
              payload: execute.payload
            )
          }
        }
        var results = [UserOperation]()
        for try await op in group { results.append(op) }
        return results
      }

      // 2. Compact
      let compactedOps = try AACompactionTemp.compactOperations(unsignedOps)
      guard let representativeOp = compactedOps.first else {
        throw AAExecutionServiceError.executionFailed(SmartAccountError.emptyCalls)
      }

      // 3. Sign Once
      let hash = try hashUserOperation(representativeOp)
      let signature = try await accountService.signPayloadWithStoredPasskey(
        account: context.account,
        payload: hash
      )
      
      let signedOps = try compactedOps.map {
        try updateUserOperationSignature($0, signature: signature)
      }

      // 4. Send
      // Separate destination op from others
      guard let destIndex = signedOps.firstIndex(where: { $0.chainId == destinationChainId }) else {
        throw AAExecutionServiceError.executionFailed(SmartAccountError.emptyCalls)
      }
      let destinationOp = signedOps[destIndex]
      let otherOps = signedOps.enumerated().compactMap { index, element in
        return index == destIndex ? nil : element
      }

      // Send destination synchronously first
      let destTxHash = try await self.sendUserOperation(destinationOp, useSyncSend: true)

      // Send others in parallel
      let otherSubmissions: [String] = try await withThrowingTaskGroup(of: String.self) { group in
        for op in otherOps {
          group.addTask {
            try await self.sendUserOperation(op, useSyncSend: false)
          }
        }
        var results = [String]()
        for try await txHash in group {
          results.append(txHash)
        }
        return results
      }

      return ExecuteChainCallsResult(
        destinationSubmission: destTxHash,
        otherSubmissions: otherSubmissions
      )
    } catch {
      throw AAExecutionServiceError.userOperationFailed(error)
    }
  }

  private func buildUserOperation(
    context: ExecutionContext,
    chainId: UInt64,
    payload: Data
  ) async throws -> UserOperation {
    let nonce = try await smartAccountClient.getNonce(
      account: context.account.eoaAddress,
      chainId: chainId
    )
    let nonceHex: String = {
      if nonce == .zero { return "0x0" }
      return "0x" + nonce.serialize().toHexString()
    }()
    let userOp = try await aaClient.buildUserOperation(
      chainId: chainId,
      sender: context.account.eoaAddress,
      nonce: nonceHex,
      payload: "0x" + payload.toHexString(),
      eip7702Auth: context.auth
    )
    return userOp
  }

  private func hashUserOperation(_ userOp: UserOperation) throws -> Data {
    do {
      return try userOp.hash()
    } catch {
      throw AAExecutionServiceError.userOperationFailed(error)
    }
  }

  private func updateUserOperationSignature(
    _ userOp: UserOperation,
    signature: Data
  ) throws -> UserOperation {
    return userOp.update(signature: signature)
  }

  private func sendUserOperation(
    _ userOp: UserOperation,
    useSyncSend: Bool
  ) async throws -> String {
    do {
      if useSyncSend {
        return try await aaClient.sendUserOperationSync(userOp)
      }
      return try await aaClient.sendUserOperation(userOp)
    } catch {
      throw AAExecutionServiceError.userOperationFailed(error)
    }
  }

  private func makeContext(
    accountService: AccountSetupService,
    account: AccountIdentity
  ) async throws -> ExecutionContext {
    let sessionAccount = try await accountService.restoreSession(eoaAddress: account.eoaAddress)
    let authorization = try await accountService.storedSignedAuthorization(account: sessionAccount)
    let auth = EIP7702Auth(
      address: authorization.delegateAddress,
      chainId: "0x" + String(authorization.chainId, radix: 16),
      nonce: "0x" + String(authorization.nonce, radix: 16),
      r: authorization.r,
      s: authorization.s,
      yParity: "0x" + String(authorization.yParity, radix: 16)
    )
    return ExecutionContext(account: sessionAccount, auth: auth)
  }

  private func buildAndSign(
    accountService: AccountSetupService,
    context: ExecutionContext,
    chainId: UInt64,
    payload: Data,
  ) async throws -> UserOperation {
     let userOp = try await buildUserOperation(
      context: context,
      chainId: chainId,
      payload: payload
    )
    let hash = try hashUserOperation(userOp)
    let signature = try await accountService.signPayloadWithStoredPasskey(
      account: context.account,
      payload: hash
    )
    let signed = try updateUserOperationSignature(userOp, signature: signature)
    return signed
  }
}

private struct ExecutionContext {
  let account: AccountIdentity
  let auth: EIP7702Auth
}
