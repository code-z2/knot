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

    guard let url = URL(string: urlString) else {
      throw ActivityProviderError.invalidURL(urlString)
    }

    var request = URLRequest(url: url)
    request.httpMethod = "GET"
    request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Accept")

    let (data, response) = try await session.data(for: request)

    if let httpResponse = response as? HTTPURLResponse,
       !(200...299).contains(httpResponse.statusCode) {
      throw ActivityProviderError.httpError(statusCode: httpResponse.statusCode)
    }

    let envelope: GoldRushActivityEnvelope
    do {
      envelope = try JSONDecoder().decode(GoldRushActivityEnvelope.self, from: data)
    } catch {
      throw ActivityProviderError.decodingFailed
    }

    if let errorMessage = envelope.errorMessage, envelope.error == true {
      throw ActivityProviderError.apiError(message: errorMessage)
    }

    guard let items = envelope.data?.items else {
      return []
    }

    let activeChainIDs = items.compactMap { item -> UInt64? in
      guard let chainIdString = item.chainId,
            let chainId = UInt64(chainIdString) else { return nil }
      return supportedChainIDs.contains(chainId) ? chainId : nil
    }

    return activeChainIDs.sorted()
  }
}
