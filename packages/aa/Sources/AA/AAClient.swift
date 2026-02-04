import Foundation
import RPC

public actor AAClient {
  private let core: AACore

  public init(rpcClient: RPCClient = RPCClient()) {
    self.core = AACore(rpcClient: rpcClient)
  }

  public func buildUserOperation(
    chainId: UInt64,
    sender: String,
    nonce: String,
    payload: String,
    eip7702Auth: EIP7702Auth
  ) async throws -> UserOperation {
    var op = UserOperation(
      chainId: chainId,
      sender: sender,
      nonce: nonce,
      callData: payload,
      eip7702Auth: eip7702Auth
    )

    let gasPrice = try await core.getUserOperationGasPrice(chainId: chainId)
    op.setGasPrice(maxFeePerGas: gasPrice.maxFeePerGas, maxPriorityFeePerGas: gasPrice.maxPriorityFeePerGas)
    op = try await core.estimateUserOperationGas(op)
    op = try await core.sponsorUserOperation(op)
    return op
  }

  public func getGasPrice(chainId: UInt64) async throws -> UserOperationGasPrice {
    try await core.getUserOperationGasPrice(chainId: chainId)
  }

  public func estimateUserOperationGas(_ userOperation: UserOperation) async throws -> UserOperation {
    try await core.estimateUserOperationGas(userOperation)
  }

  public func sponsorUserOperation(_ userOperation: UserOperation) async throws -> UserOperation {
    try await core.sponsorUserOperation(userOperation)
  }

  public func sendUserOperation(_ userOperation: UserOperation) async throws -> String {
    try await core.sendUserOperation(userOperation)
  }

  public func sendUserOperations(_ operations: [ChainUserOperation]) async throws {
    for operation in operations {
      guard var op = operation.userOperation.value as? UserOperation else {
        throw AAError.invalidPayloadType
      }
      if op.chainId != operation.chainId {
        op = UserOperation(
          chainId: operation.chainId,
          entryPoint: op.entryPoint,
          sender: op.sender,
          nonce: op.nonce,
          callData: op.callData,
          maxPriorityFeePerGas: op.maxPriorityFeePerGas,
          maxFeePerGas: op.maxFeePerGas,
          callGasLimit: op.callGasLimit,
          verificationGasLimit: op.verificationGasLimit,
          preVerificationGas: op.preVerificationGas,
          paymaster: op.paymaster,
          paymasterData: op.paymasterData,
          paymasterPostOpGasLimit: op.paymasterPostOpGasLimit,
          paymasterVerificationGasLimit: op.paymasterVerificationGasLimit,
          signature: op.signature,
          eip7702Auth: op.eip7702Auth
        )
      }
      _ = try await sendUserOperation(op)
    }
  }
}
