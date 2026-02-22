import BigInt
import Foundation
import web3swift

enum AAUtils {
    static let eip712DomainTypeHash = Data(
        "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)".utf8,
    ).sha3(.keccak256)
    static let accountDomainNameHash = Data("UnifiedAccount".utf8).sha3(.keccak256)
    static let accountDomainVersionHash = Data("1".utf8).sha3(.keccak256)

    /// EIP-712 typehash for the executeX leaf: `ExecuteX(bytes32 callsHash, bytes32 salt)`
    static let executeXTypeHash = Data(
        "ExecuteX(bytes32 callsHash,bytes32 salt)".utf8,
    ).sha3(.keccak256)

    /// EIP-712 typehash for Accumulator execution params.
    static let executionParamsTypeHash = Data(
        "ExecutionParams(bytes32 salt,uint32 fillDeadline,uint256 sumOutput,address outputToken,uint256 finalMinOutput,address finalOutputToken,address recipient,address destinationCaller,bytes32 destCallsHash)"
            .utf8,
    ).sha3(.keccak256)

    /// EIP-712 typehash for DispatchOrder, used as `orderDataType` in OnchainCrossChainOrder.
    static let dispatchOrderTypeHash = Data(
        "DispatchOrder(bytes32 salt,uint256 destChainId,address outputToken,uint256 sumOutput,uint256 inputAmount,address inputToken,uint256 minOutput)"
            .utf8,
    ).sha3(.keccak256)

    static func normalizeHexBytes(_ value: String) -> String {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalized.isEmpty || normalized == "0x" { return "0x" }
        return normalized.hasPrefix("0x") ? normalized : "0x" + normalized
    }

    static func normalizeAddressOrEmpty(_ value: String) -> String {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalized.isEmpty || normalized == "0x" { return "0x" }
        return normalized.hasPrefix("0x") ? normalized : "0x" + normalized
    }

    static func normalizeHexQuantity(_ value: String) -> String {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalized.hasPrefix("0x") {
            var stripped = String(normalized.dropFirst(2))
            while stripped.hasPrefix("0"), stripped.count > 1 {
                stripped.removeFirst()
            }
            return "0x" + stripped
        }

        guard let number = BigUInt(normalized, radix: 10) else { return normalized }
        if number == .zero { return "0x0" }
        return "0x" + number.serialize().toHexString()
    }

    static func parseQuantity(_ value: String) throws -> BigUInt {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalized.hasPrefix("0x") {
            let hex = String(normalized.dropFirst(2))
            if hex.isEmpty { return .zero }
            guard let out = BigUInt(hex, radix: 16) else { throw AAError.invalidHexValue(value) }
            return out
        }
        guard let out = BigUInt(normalized, radix: 10) else { throw AAError.invalidQuantity(value) }
        return out
    }

    static func hexToData(_ value: String) throws -> Data {
        let clean = normalizeHexBytes(value).replacingOccurrences(of: "0x", with: "")
        if clean.isEmpty { return Data() }
        guard let out = Data.fromHex(clean) else { throw AAError.invalidHexValue(value) }
        return out
    }

    static func addressData(_ value: String) throws -> Data {
        let clean = normalizeAddressOrEmpty(value).replacingOccurrences(of: "0x", with: "")
        guard clean.count == 40, let out = Data.fromHex(clean) else {
            throw AAError.invalidAddress(value)
        }
        return out
    }

    static func uint128Data(_ value: String) throws -> Data {
        let n = try parseQuantity(value)
        if n > ((BigUInt(1) << 128) - 1) { throw AAError.invalidQuantity(value) }
        let s = n.serialize()
        return Data(repeating: 0, count: max(0, 16 - s.count)) + s
    }

    static func wordData(_ value: String) throws -> Data {
        let d = try hexToData(value)
        guard d.count == 32 else { throw AAError.invalidPackedWord(value) }
        return d
    }

    static func uintWord(_ value: String) throws -> Data {
        try ABIWord.uint(parseQuantity(value))
    }

    static func wordHex(_ value: BigUInt) -> String {
        let bytes = value.serialize()
        let padded = Data(repeating: 0, count: max(0, 32 - bytes.count)) + bytes
        return "0x" + padded.toHexString()
    }

    static func accountDomainSeparator(chainId: UInt64, account: String) throws -> Data {
        let chainWord = ABIWord.uint(BigUInt(chainId))
        let accountWord = try ABIWord.address(account)
        return Data(
            (eip712DomainTypeHash + accountDomainNameHash + accountDomainVersionHash + chainWord + accountWord).sha3(
                .keccak256,
            ),
        )
    }

    static func hashTypedDataV4(domainSeparator: Data, structHash: Data) -> Data {
        Data((Data([0x19, 0x01]) + domainSeparator + structHash).sha3(.keccak256))
    }

    static func toEthSignedMessageHash(_ digest32: Data) -> Data {
        Data((Data("\u{19}Ethereum Signed Message:\n32".utf8) + digest32).sha3(.keccak256))
    }
}
