import AA
import BigInt
import Foundation
import Transactions
import web3swift

/// Encodes payloads for the Accumulator contract.
///
/// The Accumulator expects messages decoded via:
/// `abi.decode(message, (address, address, address, uint256, uint256, Call[], uint256))`
///
/// Where Call = (address target, uint256 value, bytes data) — matching the Solidity struct.
///
/// The jobId is the inner hash (without salt). The salt `(nonce << 60) | chainId`
/// is applied on-chain by `UnifiedTokenAccount.registerJob()`.
public enum AccumulatorEncoder {
    /// Encode the Accumulator message payload for bridge messages.
    ///
    /// This payload is sent as the `message` parameter to Across `depositV3`,
    /// and decoded by `Accumulator.handleMessage()` on the destination chain.
    ///
    /// - Parameters:
    ///   - inputToken: Destination chain input token address (the bridged token).
    ///   - outputToken: Destination chain output token address (what the recipient gets).
    ///   - recipient: Final recipient address.
    ///   - minInputWei: Minimum input threshold for accumulation (wei).
    ///   - minOutputWei: Minimum output after swap (wei). Use same as minInput for no-swap flows.
    ///   - swapCalls: Swap calls to execute on destination chain (empty for no-swap).
    ///   - nonce: Unique nonce for this intent.
    /// - Returns: ABI-encoded message payload.
    public static func encodeMessage(
        inputToken: String,
        outputToken: String,
        recipient: String,
        minInputWei: String,
        minOutputWei: String,
        swapCalls: [Call],
        nonce: UInt64,
    ) throws -> Data {
        // Encode each component as ABI words
        let inputTokenWord = try ABIWord.address(inputToken)
        let outputTokenWord = try ABIWord.address(outputToken)
        let recipientWord = try ABIWord.address(recipient)
        let minInputWord = try ABIWord.uint(minInputWei)
        let minOutputWord = try ABIWord.uint(minOutputWei)
        let nonceWord = ABIWord.uint(BigUInt(nonce))

        // Encode the Call[] array
        let encodedCalls = try ABIEncoder.encodeCallTupleArray(swapCalls)

        // Build the full abi.encode(...) manually
        // Layout: 7 head slots, with the Call[] being dynamic
        // Slots 0-4: inputToken, outputToken, recipient, minInput, minOutput (all static)
        // Slot 5: offset to Call[] (dynamic)
        // Slot 6: nonce (static)
        //
        // Dynamic section starts at offset 7*32 = 224

        var head = Data()
        head.append(inputTokenWord) // slot 0
        head.append(outputTokenWord) // slot 1
        head.append(recipientWord) // slot 2
        head.append(minInputWord) // slot 3
        head.append(minOutputWord) // slot 4

        // Offset to the Call[] array (7 words * 32 bytes = 224)
        let callsOffset = ABIWord.uint(BigUInt(7 * 32))
        head.append(callsOffset) // slot 5

        head.append(nonceWord) // slot 6

        // Tail: the encoded Call[] array
        return head + encodedCalls
    }

    /// Compute the jobId (inner hash without salt) matching `Accumulator._intentHash`.
    ///
    /// ```solidity
    /// bytes memory data = abi.encode(owner, inputToken, outputToken, recipientOut, minInput, minOutput, swapCalls);
    /// inner = keccak256(data);
    /// ```
    ///
    /// The salt `(nonce << 60) | block.chainid` is applied on-chain by `registerJob`.
    /// The Swift side only computes the inner hash (the jobId).
    ///
    /// - Parameters:
    ///   - owner: The smart account owner address.
    ///   - inputToken: Destination chain input token address.
    ///   - outputToken: Destination chain output token address.
    ///   - recipient: Final recipient address.
    ///   - minInputWei: Minimum input threshold (wei).
    ///   - minOutputWei: Minimum output after swap (wei).
    ///   - swapCalls: Swap calls on destination chain.
    /// - Returns: 32-byte keccak256 hash (the jobId).
    public static func computeJobId(
        owner: String,
        inputToken: String,
        outputToken: String,
        recipient: String,
        minInputWei: String,
        minOutputWei: String,
        swapCalls: [Call],
    ) throws -> Data {
        let ownerWord = try ABIWord.address(owner)
        let inputTokenWord = try ABIWord.address(inputToken)
        let outputTokenWord = try ABIWord.address(outputToken)
        let recipientWord = try ABIWord.address(recipient)
        let minInputWord = try ABIWord.uint(minInputWei)
        let minOutputWord = try ABIWord.uint(minOutputWei)

        // Encode the Call[] array
        let encodedCalls = try ABIEncoder.encodeCallTupleArray(swapCalls)

        // Build abi.encode(owner, inputToken, outputToken, recipientOut, minInput, minOutput, swapCalls)
        // 7 head slots, swapCalls is dynamic
        var head = Data()
        head.append(ownerWord) // slot 0
        head.append(inputTokenWord) // slot 1
        head.append(outputTokenWord) // slot 2
        head.append(recipientWord) // slot 3
        head.append(minInputWord) // slot 4
        head.append(minOutputWord) // slot 5

        // Offset to the Call[] array (7 words * 32 bytes = 224)
        let callsOffset = ABIWord.uint(BigUInt(7 * 32))
        head.append(callsOffset) // slot 6

        let data = head + encodedCalls

        // keccak256(data)
        return Data(data.sha3(.keccak256))
    }
}
