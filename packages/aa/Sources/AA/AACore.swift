import Foundation
import RPC

public enum AAError: Error {
    case invalidPayloadType
    case invalidAddress(String)
    case invalidHexValue(String)
    case invalidQuantity(String)
    case invalidPackedWord(String)
    case invalidEip7702SenderCodePrefix(String)
    case missingEip7702Auth
}

extension AAError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidPayloadType: "Unsupported AA payload type."
        case let .invalidAddress(value): "Invalid address: \(value)"
        case let .invalidHexValue(value): "Invalid hex value: \(value)"
        case let .invalidQuantity(value): "Invalid numeric quantity: \(value)"
        case let .invalidPackedWord(value): "Invalid packed word: \(value)"
        case let .invalidEip7702SenderCodePrefix(value):
            "Invalid EIP-7702 sender code prefix: \(value)"
        case .missingEip7702Auth: "Missing EIP-7702 authorization."
        }
    }
}

public actor AACore {
    private let rpcClient: RPCClient

    public init(rpcClient: RPCClient = RPCClient()) {
        self.rpcClient = rpcClient
    }

    public func estimateGas(
        chainId: UInt64,
        from: String,
        to: String,
        data: String,
        value: String = "0x0",
    ) async throws -> String {
        let txObject: [String: Any] = [
            "from": AAUtils.normalizeAddressOrEmpty(from),
            "to": AAUtils.normalizeAddressOrEmpty(to),
            "data": AAUtils.normalizeHexBytes(data),
            "value": AAUtils.normalizeHexQuantity(value),
        ]
        let gasHex: String = try await rpcClient.makeRpcCall(
            chainId: chainId,
            method: "eth_estimateGas",
            params: [AnyCodable(txObject)],
            responseType: String.self,
        )
        return AAUtils.normalizeHexQuantity(gasHex)
    }
}
