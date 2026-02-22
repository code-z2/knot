import Foundation
import RPC

public enum AAConstants {
    // Single addresses — same on all chains (deterministic CREATE2 deployment).
    public static let accumulatorFactoryAddress = "0xEc8191FaAb7b7288456b4Ef00E437c7422Dd42D0"
    public static let delegateImplementationAddress = "0x0f08F204c361e977Ed2fe095E112a559268e2344"

    public static func spokePoolAddress(chainId: UInt64) throws -> String {
        guard let value = ChainRegistry.spokePoolAddress(chainID: chainId) else {
            throw SmartAccountError.missingConfiguration(key: "spokePool", chainId: chainId)
        }

        return value
    }
}
