import Foundation

public struct ChainEndpointsModel: Sendable, Equatable {
    public let rpcURL: String
    public let walletAPIURL: String
    public let walletAPIBearerToken: String
    public let addressActivityAPIURL: String
    public let addressActivityAPIBearerToken: String

    public init(
        rpcURL: String,
        walletAPIURL: String = "",
        walletAPIBearerToken: String = "",
        addressActivityAPIURL: String = "",
        addressActivityAPIBearerToken: String = "",
    ) {
        self.rpcURL = rpcURL
        self.walletAPIURL = walletAPIURL
        self.walletAPIBearerToken = walletAPIBearerToken
        self.addressActivityAPIURL = addressActivityAPIURL
        self.addressActivityAPIBearerToken = addressActivityAPIBearerToken
    }
}

struct JSONRPCRequest: Encodable {
    let jsonrpc: String = "2.0"
    let id: Int
    let method: String
    let params: [AnyCodable]
}

struct JSONRPCResponse<ResultType: Decodable>: Decodable {
    let jsonrpc: String
    let id: Int
    let result: ResultType?
    let error: JSONRPCErrorPayload?
}

struct JSONRPCErrorPayload: Decodable {
    let code: Int
    let message: String
    let data: AnyCodable?
}
