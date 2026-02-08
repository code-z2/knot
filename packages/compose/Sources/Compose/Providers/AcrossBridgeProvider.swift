import AA
import BigInt
import Foundation
import Transactions

/// Across V3 bridge provider.
///
/// Fetches relay fee quotes from `https://app.across.to/api/suggested-fees`
/// and encodes `depositV3` calldata targeting the SpokePool contract.
///
/// SpokePool addresses come from `AAConstants.messengerByChain`.
public struct AcrossBridgeProvider: BridgeProvider, Sendable {

  private let baseURL: String

  public init(baseURL: String = "https://app.across.to/api") {
    self.baseURL = baseURL
  }

  // MARK: - BridgeProvider

  public func getQuote(
    inputToken: String,
    outputToken: String,
    inputAmountWei: String,
    sourceChainId: UInt64,
    destinationChainId: UInt64,
    recipient: String,
    message: Data
  ) async throws -> BridgeQuote {
    let messageHex = message.isEmpty ? "0x" : "0x" + message.map { String(format: "%02x", $0) }.joined()

    var components = URLComponents(string: "\(baseURL)/suggested-fees")!
    components.queryItems = [
      URLQueryItem(name: "inputToken", value: inputToken),
      URLQueryItem(name: "outputToken", value: outputToken),
      URLQueryItem(name: "originChainId", value: String(sourceChainId)),
      URLQueryItem(name: "destinationChainId", value: String(destinationChainId)),
      URLQueryItem(name: "amount", value: inputAmountWei),
      URLQueryItem(name: "recipient", value: recipient),
      URLQueryItem(name: "message", value: messageHex),
    ]

    guard let url = components.url else {
      throw RouteError.quoteUnavailable(provider: "Across", reason: "Invalid URL")
    }

    var request = URLRequest(url: url)
    request.httpMethod = "GET"
    request.timeoutInterval = 15

    let (data, response) = try await URLSession.shared.data(for: request)

    guard let httpResponse = response as? HTTPURLResponse,
      (200...299).contains(httpResponse.statusCode)
    else {
      let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
      let body = String(data: data, encoding: .utf8) ?? "unknown"
      throw RouteError.quoteUnavailable(
        provider: "Across",
        reason: "HTTP \(statusCode): \(body)"
      )
    }

    return try parseSuggestedFeesResponse(
      data: data,
      inputToken: inputToken,
      outputToken: outputToken,
      inputAmountWei: inputAmountWei,
      message: message
    )
  }

  public func encodeDeposit(
    quote: BridgeQuote,
    depositor: String,
    recipient: String,
    sourceChainId: UInt64,
    destinationChainId: UInt64
  ) throws -> Call {
    let spokePool = try AAConstants.messengerAddress(chainId: sourceChainId)

    return try SpokePoolEncoder.depositV3Call(
      spokePool: spokePool,
      depositor: depositor,
      recipient: recipient,
      inputToken: quote.inputToken,
      outputToken: quote.outputToken,
      inputAmountWei: quote.inputAmountWei,
      outputAmountWei: quote.outputAmountWei,
      destinationChainId: destinationChainId,
      quoteTimestamp: quote.quoteTimestamp,
      fillDeadline: quote.fillDeadline,
      exclusivityDeadline: quote.exclusivityDeadline,
      message: quote.message
    )
  }

  public func canBridge(token: String, sourceChain: UInt64, destChain: UInt64) -> Bool {
    // Both chains must have a SpokePool configured and the token must be a flight asset
    guard AAConstants.messengerByChain[sourceChain] != nil,
      AAConstants.messengerByChain[destChain] != nil
    else {
      return false
    }
    return FlightAssets.isFlightAsset(contractAddress: token, chainId: sourceChain)
  }

  // MARK: - Private

  private func parseSuggestedFeesResponse(
    data: Data,
    inputToken: String,
    outputToken: String,
    inputAmountWei: String,
    message: Data
  ) throws -> BridgeQuote {
    guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
      throw RouteError.quoteUnavailable(provider: "Across", reason: "Invalid JSON response")
    }

    // Extract key fields from the suggested-fees response
    guard let totalRelayFeeObj = json["totalRelayFee"] as? [String: Any],
      let totalRelayFeeTotal = totalRelayFeeObj["total"] as? String
    else {
      throw RouteError.quoteUnavailable(provider: "Across", reason: "Missing totalRelayFee")
    }

    let timestamp = json["timestamp"] as? String ?? String(UInt64(Date().timeIntervalSince1970))
    let quoteTimestamp = UInt64(timestamp) ?? UInt64(Date().timeIntervalSince1970)

    let exclusivityDeadline = json["exclusivityDeadline"] as? UInt64 ?? 0
    let _ = json["exclusiveRelayer"] as? String

    // Fill deadline: default to 6 hours from now if not in response
    let now = UInt64(Date().timeIntervalSince1970)
    let fillDeadline = (json["estimatedFillTimeSec"] as? UInt64).map { now + $0 + 3600 }
      ?? (now + 21600)

    // Compute output amount = input - relay fee
    guard let inputBig = BigUInt(inputAmountWei, radix: 10),
      let feeBig = BigUInt(totalRelayFeeTotal.replacingOccurrences(of: "0x", with: ""), radix: 16)
        ?? BigUInt(totalRelayFeeTotal, radix: 10)
    else {
      throw RouteError.quoteUnavailable(provider: "Across", reason: "Cannot parse amounts")
    }

    let outputBig = inputBig > feeBig ? inputBig - feeBig : BigUInt.zero
    let outputAmountWei = String(outputBig, radix: 10)

    // Convert to human-readable (approximate, for display only)
    let inputDecimal = Decimal(string: inputAmountWei) ?? .zero
    let outputDecimal = Decimal(string: outputAmountWei) ?? .zero
    let feeDecimal = inputDecimal - outputDecimal

    return BridgeQuote(
      inputAmount: inputDecimal,
      outputAmount: outputDecimal,
      relayFee: feeDecimal,
      inputToken: inputToken,
      outputToken: outputToken,
      inputAmountWei: inputAmountWei,
      outputAmountWei: outputAmountWei,
      fillDeadline: fillDeadline,
      exclusivityDeadline: exclusivityDeadline,
      quoteTimestamp: quoteTimestamp,
      message: message
    )
  }
}
