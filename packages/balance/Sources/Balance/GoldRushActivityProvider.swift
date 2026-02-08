import Foundation

public enum ActivityProviderError: LocalizedError {
  case invalidURL(String)
  case httpError(statusCode: Int)
  case apiError(message: String)
  case decodingFailed

  public var errorDescription: String? {
    switch self {
    case .invalidURL(let url):
      return "Invalid activity API URL: \(url)"
    case .httpError(let statusCode):
      return "Activity API returned HTTP \(statusCode)."
    case .apiError(let message):
      return "Activity API error: \(message)"
    case .decodingFailed:
      return "Failed to decode activity response."
    }
  }
}

/// Fetches the list of chain IDs where a wallet has on-chain activity
/// via the GoldRush Address Activity endpoint.
public actor GoldRushActivityProvider {
  private let session: URLSession

  public init(session: URLSession = .shared) {
    self.session = session
  }

  /// Discover which chains the wallet is active on.
  ///
  /// - Parameters:
  ///   - walletAddress: The 0x EOA address.
  ///   - activityAPIURL: URL template containing `{walletAddress}` placeholder.
  ///   - bearerToken: GoldRush API key.
  ///   - supportedChainIDs: Only return chain IDs present in this set.
  /// - Returns: Sorted array of active chain IDs (filtered to supported chains).
  public func fetchActiveChainIDs(
    walletAddress: String,
    activityAPIURL: String,
    bearerToken: String,
    supportedChainIDs: Set<UInt64>
  ) async throws -> [UInt64] {
    let urlString = activityAPIURL.replacingOccurrences(
      of: "{walletAddress}",
      with: walletAddress
    )

    guard var components = URLComponents(string: urlString) else {
      throw ActivityProviderError.invalidURL(urlString)
    }

    // Include testnets so testnet chain activity is returned.
    var queryItems = components.queryItems ?? []
    // TODO: Re-enable when Covalent testnet indexers are stable (currently returning 567).
    // queryItems.append(URLQueryItem(name: "testnets", value: "true"))
    components.queryItems = queryItems

    guard let url = components.url else {
      throw ActivityProviderError.invalidURL(urlString)
    }

    var request = URLRequest(url: url)
    request.httpMethod = "GET"
    request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    request.setValue(
      "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148",
      forHTTPHeaderField: "User-Agent")

    print("[GoldRushActivity] GET \(url.absoluteString)")
    let (data, response) = try await session.data(for: request)

    let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
    print("[GoldRushActivity] HTTP \(statusCode), \(data.count) bytes")

    if let httpResponse = response as? HTTPURLResponse,
      !(200...299).contains(httpResponse.statusCode)
    {
      if let body = String(data: data, encoding: .utf8)?.prefix(500) {
        print("[GoldRushActivity] ❌ error body: \(body)")
      }
      throw ActivityProviderError.httpError(statusCode: httpResponse.statusCode)
    }

    let envelope: GoldRushActivityEnvelope
    do {
      envelope = try JSONDecoder().decode(GoldRushActivityEnvelope.self, from: data)
    } catch {
      print("[GoldRushActivity] ❌ decode failed: \(error)")
      if let body = String(data: data, encoding: .utf8)?.prefix(500) {
        print("[GoldRushActivity] raw response: \(body)")
      }
      throw ActivityProviderError.decodingFailed
    }

    if let errorMessage = envelope.errorMessage, envelope.error == true {
      print("[GoldRushActivity] ❌ API error: \(errorMessage)")
      throw ActivityProviderError.apiError(message: errorMessage)
    }

    guard let items = envelope.data?.items else {
      print("[GoldRushActivity] ⚠️ envelope.data.items is nil — returning empty")
      return []
    }
    print("[GoldRushActivity] \(items.count) activity item(s)")

    let activeChainIDs = items.compactMap { item -> UInt64? in
      guard let chainIdString = item.chainId,
        let chainId = UInt64(chainIdString)
      else { return nil }
      return supportedChainIDs.contains(chainId) ? chainId : nil
    }

    return activeChainIDs.sorted()
  }
}
