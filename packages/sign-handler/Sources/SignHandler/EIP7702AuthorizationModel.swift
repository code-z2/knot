import Foundation

public struct EIP7702AuthorizationUnsignedModel: Equatable, Sendable, Codable {
    public let chainId: UInt64
    public let delegateAddress: String
    public let nonce: UInt64

    public init(chainId: UInt64, delegateAddress: String, nonce: UInt64) {
        self.chainId = chainId
        self.delegateAddress = delegateAddress
        self.nonce = nonce
    }
}

public struct EIP7702AuthorizationSignedModel: Equatable, Sendable, Codable {
    public let chainId: UInt64
    public let delegateAddress: String
    public let nonce: UInt64
    public let yParity: UInt8
    public let r: String
    public let s: String

    public init(
        chainId: UInt64,
        delegateAddress: String,
        nonce: UInt64,
        yParity: UInt8,
        r: String,
        s: String,
    ) {
        self.chainId = chainId
        self.delegateAddress = delegateAddress
        self.nonce = nonce
        self.yParity = yParity
        self.r = r
        self.s = s
    }
}
