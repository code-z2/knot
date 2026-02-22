import Foundation
import Web3Core
import web3swift

public enum EIP7702AuthorizationCodec {
    public static let magic: UInt8 = 0x05

    public static func messageToSign(_ unsigned: EIP7702AuthorizationUnsignedModel) -> Data {
        var payload = Data([magic])
        payload.append(rlpAuthorizationFields(unsigned))
        return payload
    }

    /// EIP-7702 message hash: keccak256(MAGIC || rlp([chain_id, address, nonce]))
    public static func messageHash(_ unsigned: EIP7702AuthorizationUnsignedModel) -> Data {
        messageToSign(unsigned).sha3(.keccak256)
    }

    public static func signAuthorization(
        _ unsigned: EIP7702AuthorizationUnsignedModel,
        privateKeyHex: String,
    ) throws -> EIP7702AuthorizationSignedModel {
        guard let privateKey = Data.fromHex(privateKeyHex) else {
            throw EIP7702AuthorizationError.invalidPrivateKey
        }

        let hash = messageHash(unsigned)
        let (recoverableSignature, _) = SECP256K1.signForRecovery(hash: hash, privateKey: privateKey)
        guard let recoverable = recoverableSignature, recoverable.count >= 65 else {
            throw EIP7702AuthorizationError.malformedSignature
        }

        let r = Data(recoverable[0 ..< 32]).toHexString().addHexPrefix()
        let s = Data(recoverable[32 ..< 64]).toHexString().addHexPrefix()
        let rawV = recoverable[64]
        let yParity = (rawV == 27 || rawV == 28) ? rawV - 27 : rawV

        return EIP7702AuthorizationSignedModel(
            chainId: unsigned.chainId,
            delegateAddress: unsigned.delegateAddress,
            nonce: unsigned.nonce,
            yParity: yParity,
            r: r,
            s: s,
        )
    }

    public static func recoverAuthorityAddress(
        _ signed: EIP7702AuthorizationSignedModel,
    ) throws -> String {
        let unsigned = EIP7702AuthorizationUnsignedModel(
            chainId: signed.chainId,
            delegateAddress: signed.delegateAddress,
            nonce: signed.nonce,
        )
        let hash = messageHash(unsigned)
        let signature = recoverableSignatureData(signed)

        if let address = recoverAddress(hash: hash, signature: signature) {
            return address
        }

        // Some libs expect 27/28 in the recovery byte.
        var signatureWithAdjustedV = signature
        signatureWithAdjustedV[64] = signed.yParity + 27
        if let address = recoverAddress(hash: hash, signature: signatureWithAdjustedV) {
            return address
        }

        throw EIP7702AuthorizationError.recoveryFailed
    }

    public static func rlpTuple(_ signed: EIP7702AuthorizationSignedModel) -> Data {
        RLP.encode(
            .list([
                .bytes(RLP.uintData(signed.chainId)),
                .bytes(Data(hexAddress: signed.delegateAddress)),
                .bytes(RLP.uintData(signed.nonce)),
                .bytes(Data([signed.yParity])),
                .bytes(Data(hexString: signed.r).trimmedLeadingZeros()),
                .bytes(Data(hexString: signed.s).trimmedLeadingZeros()),
            ]),
        )
    }

    private static func rlpAuthorizationFields(_ unsigned: EIP7702AuthorizationUnsignedModel) -> Data {
        RLP.encode(
            .list([
                .bytes(RLP.uintData(unsigned.chainId)),
                .bytes(Data(hexAddress: unsigned.delegateAddress)),
                .bytes(RLP.uintData(unsigned.nonce)),
            ]),
        )
    }
}

private extension Data {
    init(hexAddress: String) {
        let cleaned = hexAddress.replacingOccurrences(of: "0x", with: "")
        self.init(hexString: cleaned)
    }

    init(hexString: String) {
        self.init()
        var input = hexString
        if input.count % 2 != 0 {
            input = "0" + input
        }

        var index = input.startIndex
        while index < input.endIndex {
            let next = input.index(index, offsetBy: 2)
            let byte = UInt8(input[index ..< next], radix: 16) ?? 0
            append(byte)
            index = next
        }
    }

    func trimmedLeadingZeros() -> Data {
        var bytes = [UInt8](self)
        while bytes.first == 0, bytes.count > 1 {
            bytes.removeFirst()
        }
        return Data(bytes)
    }

    static func leftPadTo32(_ data: Data) -> Data {
        if data.count >= 32 {
            return Data(data.suffix(32))
        }

        return Data(repeating: 0, count: 32 - data.count) + data
    }
}

private extension EIP7702AuthorizationCodec {
    static func recoverableSignatureData(_ signed: EIP7702AuthorizationSignedModel) -> Data {
        let r = Data.leftPadTo32(Data(hexString: signed.r.replacingOccurrences(of: "0x", with: "")))
        let s = Data.leftPadTo32(Data(hexString: signed.s.replacingOccurrences(of: "0x", with: "")))
        return r + s + Data([signed.yParity])
    }

    static func recoverAddress(hash: Data, signature: Data) -> String? {
        guard let publicKey = SECP256K1.recoverPublicKey(hash: hash, signature: signature, compressed: false) else {
            return nil
        }

        let uncompressed = publicKey.count == 65 ? Data(publicKey.dropFirst()) : publicKey
        let digest = uncompressed.sha3(.keccak256)
        guard digest.count >= 20 else {
            return nil
        }

        let addressBytes = digest.suffix(20)
        return "0x" + Data(addressBytes).toHexString()
    }
}
