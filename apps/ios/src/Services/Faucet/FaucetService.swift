import Foundation

/// Best-effort faucet that requests testnet USDC and ETH for a newly created account.
/// All errors are silently swallowed — the faucet is purely additive and never blocks the user.
final class FaucetService: Sendable {
  private let session: URLSession
  private let baseURL: URL
  private let clientToken: String?

  init(
    session: URLSession = .shared,
    baseURL: URL = FaucetService.defaultBaseURL,
    clientToken: String? = FaucetService.defaultClientToken
  ) {
    self.session = session
    self.baseURL = baseURL
    self.clientToken = clientToken?.isEmpty == true ? nil : clientToken
  }

  /// Fire-and-forget: requests the server to fund the given EOA on all testnet chains.
  /// Returns silently on any failure.
  func fundAccount(eoaAddress: String) async {
    do {
      let url = baseURL
        .appendingPathComponent("v1", isDirectory: true)
        .appendingPathComponent("faucet", isDirectory: true)
        .appendingPathComponent("fund", isDirectory: false)

      var request = URLRequest(url: url)
      request.httpMethod = "POST"
      request.setValue("application/json", forHTTPHeaderField: "Content-Type")
      if let clientToken {
        request.setValue("Bearer \(clientToken)", forHTTPHeaderField: "Authorization")
      }

      let body = FaucetFundRequest(eoaAddress: eoaAddress)
      request.httpBody = try JSONEncoder().encode(body)
      request.timeoutInterval = 30

      let (_, _) = try await session.data(for: request)
      // 202 Accepted is expected; we ignore the response.
    } catch {
      // Silently fail — faucet funding is best-effort.
    }
  }

  // MARK: - Defaults (reuse the same worker as ProfileImageStorageService)

  static var defaultBaseURL: URL {
    if let configured = Bundle.main.object(
      forInfoDictionaryKey: "PROFILE_IMAGE_UPLOAD_WORKER_BASE_URL"
    ) as? String, !configured.isEmpty {
      let normalized = configured.trimmingCharacters(in: .whitespacesAndNewlines)
      let urlString = normalized.contains("://") ? normalized : "https://\(normalized)"
      if let url = URL(string: urlString), let host = url.host, !host.isEmpty {
        return url
      }
    }
    return URL(string: "https://upload.peteranyaogu.com")!
  }

  static var defaultClientToken: String? {
    Bundle.main.object(forInfoDictionaryKey: "PROFILE_IMAGE_UPLOAD_CLIENT_TOKEN") as? String
  }
}

// MARK: - Request Model

private struct FaucetFundRequest: Encodable {
  let eoaAddress: String
}
