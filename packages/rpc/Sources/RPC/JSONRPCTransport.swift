import Foundation

public protocol JSONRPCTransporting: Sendable {
  func send<Response: Decodable>(
    urlString: String,
    method: String,
    params: [AnyCodable],
    requestID: Int,
    responseType: Response.Type
  ) async throws -> Response
}

public struct URLSessionJSONRPCTransport: JSONRPCTransporting, Sendable {
  public init() {}

  public func send<Response: Decodable>(
    urlString: String,
    method: String,
    params: [AnyCodable] = [],
    requestID: Int,
    responseType: Response.Type = Response.self
  ) async throws -> Response {
    guard let url = URL(string: urlString), !urlString.isEmpty else {
      throw RPCError.invalidURL(urlString)
    }

    let payload = JSONRPCRequest(id: requestID, method: method, params: params)
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try JSONEncoder().encode(payload)

    let (data, _) = try await URLSession.shared.data(for: request)

    do {
      let decoded = try JSONDecoder().decode(JSONRPCResponse<Response>.self, from: data)
      if let error = decoded.error {
        throw RPCError.rpcError(code: error.code, message: error.message)
      }

      guard let result = decoded.result else {
        throw RPCError.missingResult
      }
      return result
    } catch {
      if let rpcError = error as? RPCError {
        throw rpcError
      }
      throw error
    }
  }
}
