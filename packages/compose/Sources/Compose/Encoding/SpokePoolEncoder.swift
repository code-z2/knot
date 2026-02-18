import AA
import BigInt
import Foundation
import Transactions

/// Encodes Across V3 SpokePool `depositV3` calls.
public enum SpokePoolEncoder {
    /// Encode a `depositV3` call to the Across SpokePool contract.
    ///
    /// Function signature:
    /// `depositV3(address depositor, address recipient, address inputToken, address outputToken,
    ///            uint256 inputAmount, uint256 outputAmount, uint256 destinationChainId,
    ///            address exclusiveRelayer, uint32 quoteTimestamp, uint32 fillDeadline,
    ///            uint32 exclusivityDeadline, bytes message)`
    ///
    /// - Parameters:
    ///   - spokePool: SpokePool contract address on the source chain (from ChainRegistry).
    ///   - depositor: User's smart account address.
    ///   - recipient: Recipient on destination (user for simple bridge, accumulator for scatter-gather).
    ///   - inputToken: Token address on source chain.
    ///   - outputToken: Token address on destination chain.
    ///   - inputAmountWei: Input amount in wei.
    ///   - outputAmountWei: Output amount in wei (from bridge quote, after relay fee).
    ///   - destinationChainId: Destination chain ID.
    ///   - exclusiveRelayer: Exclusive relayer address (address(0) for no exclusivity).
    ///   - quoteTimestamp: Quote timestamp from the bridge provider.
    ///   - fillDeadline: Fill deadline as unix timestamp.
    ///   - exclusivityDeadline: Exclusivity deadline as unix timestamp.
    ///   - message: Encoded message payload (empty for simple bridge).
    public static func depositV3Call(
        spokePool: String,
        depositor: String,
        recipient: String,
        inputToken: String,
        outputToken: String,
        inputAmountWei: String,
        outputAmountWei: String,
        destinationChainId: UInt64,
        exclusiveRelayer: String = "0x0000000000000000000000000000000000000000",
        quoteTimestamp: UInt64,
        fillDeadline: UInt64,
        exclusivityDeadline: UInt64,
        message: Data,
    ) throws -> Call {
        let depositorWord = try ABIWord.address(depositor)
        let recipientWord = try ABIWord.address(recipient)
        let inputTokenWord = try ABIWord.address(inputToken)
        let outputTokenWord = try ABIWord.address(outputToken)
        let inputAmountWord = try ABIWord.uint(inputAmountWei)
        let outputAmountWord = try ABIWord.uint(outputAmountWei)
        let destChainWord = ABIWord.uint(BigUInt(destinationChainId))
        let relayerWord = try ABIWord.address(exclusiveRelayer)
        let quoteTimestampWord = ABIWord.uint(BigUInt(quoteTimestamp))
        let fillDeadlineWord = ABIWord.uint(BigUInt(fillDeadline))
        let exclusivityDeadlineWord = ABIWord.uint(BigUInt(exclusivityDeadline))
        let messageEncoded = ABIEncoder.encodeBytes(message)

        let data = ABIEncoder.functionCall(
            signature:
            "depositV3(address,address,address,address,uint256,uint256,uint256,address,uint32,uint32,uint32,bytes)",
            words: [
                depositorWord,
                recipientWord,
                inputTokenWord,
                outputTokenWord,
                inputAmountWord,
                outputAmountWord,
                destChainWord,
                relayerWord,
                quoteTimestampWord,
                fillDeadlineWord,
                exclusivityDeadlineWord,
            ],
            dynamic: [messageEncoded],
        )

        return Call(
            to: spokePool,
            dataHex: "0x" + data.map { String(format: "%02x", $0) }.joined(),
        )
    }
}
