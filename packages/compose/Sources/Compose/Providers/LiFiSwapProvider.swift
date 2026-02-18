import Foundation
import Transactions

/// LiFi swap provider for same-chain swaps.
///
/// Uses the LiFi quote API in **non-intent mode** — the swap executes atomically
/// in the same transaction. No cross-chain routing via LiFi (Across handles bridging).
public struct LiFiSwapProvider: SwapProvider, Sendable {
    private let baseURL: String

    public init(baseURL: String = "https://li.quest/v1") {
        self.baseURL = baseURL
    }

    // MARK: - SwapProvider

    public func getQuote(
        inputToken: String,
        outputToken: String,
        inputAmountWei: String,
        chainId: UInt64,
        fromAddress: String,
    ) async throws -> SwapQuote {
        var components = URLComponents(string: "\(baseURL)/quote")!
        components.queryItems = [
            URLQueryItem(name: "fromChain", value: String(chainId)),
            URLQueryItem(name: "toChain", value: String(chainId)),
            URLQueryItem(name: "fromToken", value: inputToken),
            URLQueryItem(name: "toToken", value: outputToken),
            URLQueryItem(name: "fromAmount", value: inputAmountWei),
            URLQueryItem(name: "fromAddress", value: fromAddress),
            URLQueryItem(name: "order", value: "CHEAPEST"),
            URLQueryItem(name: "allowDestinationCall", value: "false"),
        ]

        guard let url = components.url else {
            throw RouteError.quoteUnavailable(provider: "LiFi", reason: "Invalid URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200 ... 299).contains(httpResponse.statusCode)
        else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            let body = String(data: data, encoding: .utf8) ?? "unknown"
            throw RouteError.quoteUnavailable(
                provider: "LiFi",
                reason: "HTTP \(statusCode): \(body)",
            )
        }

        return try parseQuoteResponse(
            data: data,
            inputToken: inputToken,
            outputToken: outputToken,
            inputAmountWei: inputAmountWei,
            chainId: chainId,
        )
    }

    // MARK: - Private

    private func parseQuoteResponse(
        data: Data,
        inputToken: String,
        outputToken: String,
        inputAmountWei: String,
        chainId: UInt64,
    ) throws -> SwapQuote {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw RouteError.quoteUnavailable(provider: "LiFi", reason: "Invalid JSON response")
        }

        // Extract transactionRequest
        guard let txRequest = json["transactionRequest"] as? [String: Any],
              let swapTargetAddress = txRequest["to"] as? String,
              let txDataHex = txRequest["data"] as? String
        else {
            throw RouteError.quoteUnavailable(
                provider: "LiFi",
                reason: "Missing transactionRequest in response",
            )
        }

        let txValue = txRequest["value"] as? String ?? "0"

        // Extract estimate
        guard let estimate = json["estimate"] as? [String: Any],
              let toAmountStr = estimate["toAmount"] as? String
        else {
            throw RouteError.quoteUnavailable(
                provider: "LiFi",
                reason: "Missing estimate in response",
            )
        }

        let approvalAddress = estimate["approvalAddress"] as? String ?? swapTargetAddress

        // Convert calldata hex to Data
        let cleanHex = txDataHex.replacingOccurrences(of: "0x", with: "")
        var swapCalldata = Data()
        var index = cleanHex.startIndex
        while index < cleanHex.endIndex {
            let nextIndex = cleanHex.index(index, offsetBy: 2, limitedBy: cleanHex.endIndex) ?? cleanHex.endIndex
            if let byte = UInt8(cleanHex[index ..< nextIndex], radix: 16) {
                swapCalldata.append(byte)
            }
            index = nextIndex
        }

        let inputDecimal = Decimal(string: inputAmountWei) ?? .zero
        let outputDecimal = Decimal(string: toAmountStr) ?? .zero

        return SwapQuote(
            inputAmount: inputDecimal,
            outputAmount: outputDecimal,
            inputToken: inputToken,
            outputToken: outputToken,
            chainId: chainId,
            approvalTarget: approvalAddress,
            swapTarget: swapTargetAddress,
            swapCalldata: swapCalldata,
            swapValue: txValue,
            inputAmountWei: inputAmountWei,
            outputAmountWei: toAmountStr,
        )
    }
}
