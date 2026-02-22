import Foundation
import Web3Core
import web3swift

public extension ENSClient {
    func resolveName(_ request: ResolveNameRequestModel) async throws -> String {
        let name = Self.normalizedENSName(request.name)
        print("[ENSClient] resolveName: normalized=\(name), chainID=\(configuration.chainID)")
        guard !name.isEmpty else { throw ENSError.invalidName }

        let context: ENSResolverContext
        do {
            context = try await universalResolverContext(forName: name)
            print("[ENSClient] got resolver context: resolver=\(context.resolverAddress.address)")
        } catch {
            print("[ENSClient] ❌ universalResolverContext failed: \(error)")
            throw error
        }

        let encodedCall = try makeCallData(
            web3: context.web3,
            abi: Web3.Utils.resolverABI,
            method: "addr",
            parameters: [context.nodeHash],
        )

        let resolved: Data
        do {
            resolved = try await universalResolve(
                web3: context.web3,
                normalizedName: context.normalizedName,
                callData: encodedCall,
            )
            print("[ENSClient] universalResolve returned \(resolved.count) bytes")
        } catch {
            print("[ENSClient] ❌ universalResolve failed: \(error)")
            throw error
        }

        guard let address = Self.abiDecodeAddress(from: resolved) else {
            print("[ENSClient] ❌ could not decode address from resolved data")
            throw ENSError.ensUnavailable
        }
        guard address.address.lowercased() != Self.zeroAddressHex else {
            print("[ENSClient] ❌ resolved to zero address")
            throw ENSError.ensUnavailable
        }
        print("[ENSClient] ✅ resolved \(name) → \(address.address)")
        return address.address
    }

    func reverseAddress(_ request: ReverseAddressRequestModel) async throws -> String {
        guard let address = EthereumAddress(request.address) else {
            throw ENSError.invalidAddress(request.address)
        }

        let reverseNode = Self.reverseNode(for: address)
        let context = try await universalResolverContext(forName: reverseNode)

        let encodedCall = try makeCallData(
            web3: context.web3,
            abi: Web3.Utils.resolverABI,
            method: "name",
            parameters: [context.nodeHash],
        )
        let resolved = try await universalResolve(
            web3: context.web3,
            normalizedName: context.normalizedName,
            callData: encodedCall,
        )
        guard let name = Self.abiDecodeString(from: resolved) else {
            throw ENSError.ensUnavailable
        }
        let normalized = Self.normalizedENSName(name)
        guard !normalized.isEmpty else { throw ENSError.ensUnavailable }
        return normalized
    }
}
