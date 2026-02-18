import Foundation
import RPC

public enum AAConstants {
    // Single addresses — same on all chains (deterministic CREATE2 deployment).
    public static let accumulatorFactoryAddress = "0xb329c298dfa2f7fce4de1329d8cd1dd1dea9f41f"
    public static let delegateImplementationAddress = "0x919FB6f181DC306825Dc8F570A1BDF8c456c56Da"

    public static func spokePoolAddress(chainId: UInt64) throws -> String {
        guard let value = ChainRegistry.spokePoolAddress(chainID: chainId) else {
            throw SmartAccountError.missingConfiguration(key: "spokePool", chainId: chainId)
        }
        return value
    }

    public static func wrappedNativeTokenAddress(chainId: UInt64) throws -> String {
        guard let value = ChainRegistry.wrappedNativeTokenAddress(chainID: chainId) else {
            throw SmartAccountError.missingConfiguration(key: "wrappedNativeToken", chainId: chainId)
        }
        return value
    }
}
