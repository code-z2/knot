import AA
import BigInt
import Foundation
import Transactions

/// Encodes ERC20 approve and transfer calls.
public enum ERC20Encoder {

  /// Sentinel address representing native ETH.
  public static let nativeAddress = "0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE"

  /// Whether the given address represents native ETH.
  public static func isNative(_ address: String) -> Bool {
    address.lowercased() == nativeAddress.lowercased()
      || address == "0x0000000000000000000000000000000000000000"
  }

  /// Build an ERC20 `approve(spender, amount)` call.
  ///
  /// - Parameters:
  ///   - token: ERC20 contract address.
  ///   - spender: Address to approve.
  ///   - amountWei: Amount in wei (decimal string or hex).
  /// - Returns: A `Call` targeting the token contract.
  public static func approveCall(
    token: String,
    spender: String,
    amountWei: String
  ) throws -> Call {
    let spenderWord = try ABIWord.address(spender)
    let amountWord = try ABIWord.uint(amountWei)
    let data = ABIEncoder.functionCall(
      signature: "approve(address,uint256)",
      words: [spenderWord, amountWord],
      dynamic: []
    )
    return Call(
      to: token,
      dataHex: "0x" + data.map { String(format: "%02x", $0) }.joined()
    )
  }

  /// Build an ERC20 `transfer(to, amount)` call.
  ///
  /// - Parameters:
  ///   - token: ERC20 contract address.
  ///   - to: Recipient address.
  ///   - amountWei: Amount in wei (decimal string or hex).
  /// - Returns: A `Call` targeting the token contract.
  public static func transferCall(
    token: String,
    to: String,
    amountWei: String
  ) throws -> Call {
    let toWord = try ABIWord.address(to)
    let amountWord = try ABIWord.uint(amountWei)
    let data = ABIEncoder.functionCall(
      signature: "transfer(address,uint256)",
      words: [toWord, amountWord],
      dynamic: []
    )
    return Call(
      to: token,
      dataHex: "0x" + data.map { String(format: "%02x", $0) }.joined()
    )
  }

  /// Build a native ETH transfer call (no calldata, just value).
  ///
  /// - Parameters:
  ///   - to: Recipient address.
  ///   - amountWei: Amount in wei.
  /// - Returns: A `Call` with the value field set.
  public static func nativeTransferCall(
    to: String,
    amountWei: String
  ) -> Call {
    Call(
      to: to,
      dataHex: "0x",
      valueWei: amountWei
    )
  }
}
