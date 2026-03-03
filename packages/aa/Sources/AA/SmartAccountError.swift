import Foundation

public enum SmartAccountError: Error {
    case invalidAddress(String)

    case invalidHex(String)

    case invalidBytes32Length(Int)

    case invalidUIntValue(String)

    case malformedRPCResponse(String)

    case emptyCalls

    case emptyLeaves

    case duplicateChainLeaf(UInt64)
}
