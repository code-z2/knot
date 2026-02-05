import BigInt
import Foundation

public enum AACompactionTemp {
  // Temporary helper: normalize selected gas/fee fields across operations.
  // used to create a single sign 4337 userop for cross chain calls
  public static func compactOperations(_ operations: [UserOperation]) throws -> [UserOperation] {
    guard !operations.isEmpty else { return [] }

    var maxMaxFeePerGas = BigUInt.zero
    var maxMaxPriorityFeePerGas = BigUInt.zero
    var maxVerificationGasLimit = BigUInt.zero
    var maxCallGasLimit = BigUInt.zero

    for op in operations {
      maxMaxFeePerGas = max(maxMaxFeePerGas, try AAUtils.parseQuantity(op.maxFeePerGas))
      maxMaxPriorityFeePerGas = max(maxMaxPriorityFeePerGas, try AAUtils.parseQuantity(op.maxPriorityFeePerGas))
      maxVerificationGasLimit = max(maxVerificationGasLimit, try AAUtils.parseQuantity(op.verificationGasLimit))
      maxCallGasLimit = max(maxCallGasLimit, try AAUtils.parseQuantity(op.callGasLimit))
    }

    let maxFeeHex = quantityHex(maxMaxFeePerGas)
    let maxPriorityHex = quantityHex(maxMaxPriorityFeePerGas)
    let maxVerificationHex = quantityHex(maxVerificationGasLimit)
    let maxCallHex = quantityHex(maxCallGasLimit)

    return operations.map { op in
      var copy = op
      copy.maxFeePerGas = maxFeeHex
      copy.maxPriorityFeePerGas = maxPriorityHex
      copy.verificationGasLimit = maxVerificationHex
      copy.callGasLimit = maxCallHex
      return copy
    }
  }

  private static func quantityHex(_ value: BigUInt) -> String {
    if value == .zero { return "0x0" }
    return "0x" + value.serialize().toHexString()
  }
}
