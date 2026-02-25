import Foundation
import RPC

public enum AAConstants {
    // Single addresses — same on all chains (deterministic CREATE2 deployment).
    public static let accumulatorFactoryAddress = "0x6edfE18365C911CFC88e241c87b3a0D313aD7129"
    public static let delegateImplementationAddress = "0xE8dB5e6226364deDD69E57c7A437ad1c8805c9f2"

    public static func spokePoolAddress(chainId: UInt64) throws -> String {
        guard let value = ChainRegistry.spokePoolAddress(chainID: chainId) else {
            throw SmartAccountError.missingConfiguration(key: "spokePool", chainId: chainId)
        }

        return value
    }
}
