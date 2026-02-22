import BigInt
import Foundation
import Web3Core
import web3swift

public extension ENSClient {
    static let ethRegistrarControllerV2ABI = """
    [{"inputs":[{"internalType":"contract BaseRegistrarImplementation","name":"_base","type":"address"},{"internalType":"contract IPriceOracle","name":"_prices","type":"address"},{"internalType":"uint256","name":"_minCommitmentAge","type":"uint256"},{"internalType":"uint256","name":"_maxCommitmentAge","type":"uint256"},{"internalType":"contract IReverseRegistrar","name":"_reverseRegistrar","type":"address"},{"internalType":"contract IDefaultReverseRegistrar","name":"_defaultReverseRegistrar","type":"address"},{"internalType":"contract ENS","name":"_ens","type":"address"}],"stateMutability":"nonpayable","type":"constructor"},{"inputs":[{"internalType":"bytes32","name":"commitment","type":"bytes32"}],"name":"CommitmentNotFound","type":"error"},{"inputs":[{"internalType":"bytes32","name":"commitment","type":"bytes32"},{"internalType":"uint256","name":"minimumCommitmentTimestamp","type":"uint256"},{"internalType":"uint256","name":"currentTimestamp","type":"uint256"}],"name":"CommitmentTooNew","type":"error"},{"inputs":[{"internalType":"bytes32","name":"commitment","type":"bytes32"},{"internalType":"uint256","name":"maximumCommitmentTimestamp","type":"uint256"},{"internalType":"uint256","name":"currentTimestamp","type":"uint256"}],"name":"CommitmentTooOld","type":"error"},{"inputs":[{"internalType":"uint256","name":"duration","type":"uint256"}],"name":"DurationTooShort","type":"error"},{"inputs":[],"name":"InsufficientValue","type":"error"},{"inputs":[],"name":"MaxCommitmentAgeTooHigh","type":"error"},{"inputs":[],"name":"MaxCommitmentAgeTooLow","type":"error"},{"inputs":[{"internalType":"string","name":"name","type":"string"}],"name":"NameNotAvailable","type":"error"},{"inputs":[],"name":"ResolverRequiredForReverseRecord","type":"error"},{"inputs":[],"name":"ResolverRequiredWhenDataSupplied","type":"error"},{"inputs":[{"internalType":"bytes32","name":"commitment","type":"bytes32"}],"name":"UnexpiredCommitmentExists","type":"error"},{"anonymous":false,"inputs":[{"indexed":false,"internalType":"string","name":"label","type":"string"},{"indexed":true,"internalType":"bytes32","name":"labelhash","type":"bytes32"},{"indexed":true,"internalType":"address","name":"owner","type":"address"},{"indexed":false,"internalType":"uint256","name":"baseCost","type":"uint256"},{"indexed":false,"internalType":"uint256","name":"premium","type":"uint256"},{"indexed":false,"internalType":"uint256","name":"expires","type":"uint256"},{"indexed":false,"internalType":"bytes32","name":"referrer","type":"bytes32"}],"name":"NameRegistered","type":"event"},{"anonymous":false,"inputs":[{"indexed":false,"internalType":"string","name":"label","type":"string"},{"indexed":true,"internalType":"bytes32","name":"labelhash","type":"bytes32"},{"indexed":false,"internalType":"uint256","name":"cost","type":"uint256"},{"indexed":false,"internalType":"uint256","name":"expires","type":"uint256"},{"indexed":false,"internalType":"bytes32","name":"referrer","type":"bytes32"}],"name":"NameRenewed","type":"event"},{"anonymous":false,"inputs":[{"indexed":true,"internalType":"address","name":"previousOwner","type":"address"},{"indexed":true,"internalType":"address","name":"newOwner","type":"address"}],"name":"OwnershipTransferred","type":"event"},{"inputs":[],"name":"MIN_REGISTRATION_DURATION","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},{"inputs":[{"internalType":"string","name":"label","type":"string"}],"name":"available","outputs":[{"internalType":"bool","name":"","type":"bool"}],"stateMutability":"view","type":"function"},{"inputs":[{"internalType":"bytes32","name":"commitment","type":"bytes32"}],"name":"commit","outputs":[],"stateMutability":"nonpayable","type":"function"},{"inputs":[{"internalType":"bytes32","name":"","type":"bytes32"}],"name":"commitments","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},{"inputs":[],"name":"defaultReverseRegistrar","outputs":[{"internalType":"contract IDefaultReverseRegistrar","name":"","type":"address"}],"stateMutability":"view","type":"function"},{"inputs":[],"name":"ens","outputs":[{"internalType":"contract ENS","name":"","type":"address"}],"stateMutability":"view","type":"function"},{"inputs":[{"components":[{"internalType":"string","name":"label","type":"string"},{"internalType":"address","name":"owner","type":"address"},{"internalType":"uint256","name":"duration","type":"uint256"},{"internalType":"bytes32","name":"secret","type":"bytes32"},{"internalType":"address","name":"resolver","type":"address"},{"internalType":"bytes[]","name":"data","type":"bytes[]"},{"internalType":"uint8","name":"reverseRecord","type":"uint8"},{"internalType":"bytes32","name":"referrer","type":"bytes32"}],"internalType":"struct IETHRegistrarController.Registration","name":"registration","type":"tuple"}],"name":"makeCommitment","outputs":[{"internalType":"bytes32","name":"commitment","type":"bytes32"}],"stateMutability":"pure","type":"function"},{"inputs":[],"name":"maxCommitmentAge","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},{"inputs":[],"name":"minCommitmentAge","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},{"inputs":[],"name":"owner","outputs":[{"internalType":"address","name":"","type":"address"}],"stateMutability":"view","type":"function"},{"inputs":[],"name":"prices","outputs":[{"internalType":"contract IPriceOracle","name":"","type":"address"}],"stateMutability":"view","type":"function"},{"inputs":[{"internalType":"address","name":"_token","type":"address"},{"internalType":"address","name":"_to","type":"address"},{"internalType":"uint256","name":"_amount","type":"uint256"}],"name":"recoverFunds","outputs":[],"stateMutability":"nonpayable","type":"function"},{"inputs":[{"components":[{"internalType":"string","name":"label","type":"string"},{"internalType":"address","name":"owner","type":"address"},{"internalType":"uint256","name":"duration","type":"uint256"},{"internalType":"bytes32","name":"secret","type":"bytes32"},{"internalType":"address","name":"resolver","type":"address"},{"internalType":"bytes[]","name":"data","type":"bytes[]"},{"internalType":"uint8","name":"reverseRecord","type":"uint8"},{"internalType":"bytes32","name":"referrer","type":"bytes32"}],"internalType":"struct IETHRegistrarController.Registration","name":"registration","type":"tuple"}],"name":"register","outputs":[],"stateMutability":"payable","type":"function"},{"inputs":[{"internalType":"string","name":"label","type":"string"},{"internalType":"uint256","name":"duration","type":"uint256"},{"internalType":"bytes32","name":"referrer","type":"bytes32"}],"name":"renew","outputs":[],"stateMutability":"payable","type":"function"},{"inputs":[],"name":"renounceOwnership","outputs":[],"stateMutability":"nonpayable","type":"function"},{"inputs":[{"internalType":"string","name":"label","type":"string"},{"internalType":"uint256","name":"duration","type":"uint256"}],"name":"rentPrice","outputs":[{"components":[{"internalType":"uint256","name":"base","type":"uint256"},{"internalType":"uint256","name":"premium","type":"uint256"}],"internalType":"struct IPriceOracle.Price","name":"price","type":"tuple"}],"stateMutability":"view","type":"function"},{"inputs":[],"name":"reverseRegistrar","outputs":[{"internalType":"contract IReverseRegistrar","name":"","type":"address"}],"stateMutability":"view","type":"function"},{"inputs":[{"internalType":"bytes4","name":"interfaceID","type":"bytes4"}],"name":"supportsInterface","outputs":[{"internalType":"bool","name":"","type":"bool"}],"stateMutability":"view","type":"function"},{"inputs":[{"internalType":"address","name":"newOwner","type":"address"}],"name":"transferOwnership","outputs":[],"stateMutability":"nonpayable","type":"function"},{"inputs":[{"internalType":"string","name":"label","type":"string"}],"name":"valid","outputs":[{"internalType":"bool","name":"","type":"bool"}],"stateMutability":"pure","type":"function"},{"inputs":[],"name":"withdraw","outputs":[],"stateMutability":"nonpayable","type":"function"}]
    """

    func quoteRegistration(_ request: RegisterNameRequestModel) async throws
        -> NameAvailabilityQuoteModel
    {
        let normalizedName = Self.normalizedENSName(request.name)
        let label = Self.ethLabel(from: normalizedName)
        guard !label.isEmpty, !label.contains(".") else {
            throw ENSError.invalidName
        }

        guard let controllerAddress = EthereumAddress(configuration.registrarControllerAddress) else {
            throw ENSError.invalidAddress(configuration.registrarControllerAddress)
        }

        let web3 = try await getWeb3ForENSChain()
        async let availabilityResult = makeReadResult(
            web3: web3,
            abi: Self.ethRegistrarControllerV2ABI,
            to: controllerAddress,
            method: "available",
            parameters: [label],
        )

        let rentPriceWei: BigUInt
        if let override = request.rentPriceWeiOverride {
            rentPriceWei = try parseWeiOverride(override)
        } else {
            async let quoteResultTask = makeReadResult(
                web3: web3,
                abi: Self.ethRegistrarControllerV2ABI,
                to: controllerAddress,
                method: "rentPrice",
                parameters: [label, request.duration],
            )
            let quoteResult = try await quoteResultTask
            print("   [DEBUG-ENS] raw quoteResult: \(quoteResult)")
            guard let priceArray = quoteResult["0"] as? [Any],
                  priceArray.count >= 2,
                  let base = priceArray[0] as? BigUInt,
                  let premium = priceArray[1] as? BigUInt
            else {
                throw ENSError.missingResult("rentPrice.base")
            }
            rentPriceWei = base + premium
        }
        let resolvedAvailabilityResult = try await availabilityResult
        guard let available = resolvedAvailabilityResult["0"] as? Bool else {
            throw ENSError.missingResult("available")
        }

        return NameAvailabilityQuoteModel(
            label: label,
            normalizedName: normalizedName,
            available: available,
            rentPriceWei: rentPriceWei.description,
        )
    }

    func registerName(_ request: RegisterNameRequestModel) async throws
        -> RegisterNameResultModel
    {
        let normalizedName = Self.normalizedENSName(request.name)
        let label = Self.ethLabel(from: normalizedName)
        guard !label.isEmpty, !label.contains(".") else {
            throw ENSError.invalidName
        }

        guard let owner = EthereumAddress(request.ownerAddress) else {
            throw ENSError.invalidAddress(request.ownerAddress)
        }

        guard let controllerAddress = EthereumAddress(configuration.registrarControllerAddress) else {
            throw ENSError.invalidAddress(configuration.registrarControllerAddress)
        }
        let resolverAddressString = request.resolverAddress ?? configuration.publicResolverAddress
        guard let resolverAddress = EthereumAddress(resolverAddressString) else {
            throw ENSError.invalidAddress(resolverAddressString)
        }
        guard let nodeHash = NameHash.nameHash(normalizedName) else {
            throw ENSError.invalidName
        }

        let web3 = try await getWeb3ForENSChain()
        async let minCommitmentAgeTask = minimumCommitmentAgeSeconds(
            web3: web3,
            controllerAddress: controllerAddress,
        )
        async let availabilityResultTask = makeReadResult(
            web3: web3,
            abi: Self.ethRegistrarControllerV2ABI,
            to: controllerAddress,
            method: "available",
            parameters: [label],
        )
        async let quoteResultTask = makeReadResult(
            web3: web3,
            abi: Self.ethRegistrarControllerV2ABI,
            to: controllerAddress,
            method: "rentPrice",
            parameters: [label, request.duration],
        )

        let availabilityResult: [String: Any]
        do {
            availabilityResult = try await availabilityResultTask
            print("   ✅ [ENSClient] Availability Check succeeded")
        } catch {
            print("   ❌ [ENSClient] Availability Check failed: \(error)")
            throw error
        }
        guard let available = availabilityResult["0"] as? Bool else {
            throw ENSError.missingResult("available")
        }
        guard available else {
            throw ENSError.nameUnavailable(label)
        }

        let secretHex = Self.secretHex(from: request.secretHex)
        var resolverData: [Data] = []
        try resolverData.append(
            makeCallData(
                web3: web3,
                abi: Web3.Utils.resolverABI,
                method: "setAddr",
                parameters: [nodeHash, owner.address],
            ),
        )
        for record in request.initialTextRecords where !record.key.isEmpty {
            try resolverData.append(
                makeCallData(
                    web3: web3,
                    abi: Web3.Utils.resolverABI,
                    method: "setText",
                    parameters: [nodeHash, record.key, record.value],
                ),
            )
        }

        let commitmentResult: [String: Any]
        do {
            commitmentResult = try await makeReadResult(
                web3: web3,
                abi: Self.ethRegistrarControllerV2ABI,
                to: controllerAddress,
                method: "makeCommitment",
                parameters: [
                    [
                        label,
                        owner.address,
                        request.duration,
                        secretHex,
                        resolverAddress.address,
                        resolverData,
                        request.setReverseRecord ? 1 : 0, // uint8 mapping for bool
                        Data(count: 32), // referrer bytes32 (empty)
                    ],
                ],
            )
            print("   ✅ [ENSClient] makeCommitment Simulation succeeded")
        } catch {
            print("   ❌ [ENSClient] makeCommitment Simulation failed: \(error)")
            throw error
        }
        guard let commitment = commitmentResult["0"] as? Data else {
            throw ENSError.missingResult("commitment")
        }

        let quoteResult: [String: Any]
        do {
            quoteResult = try await quoteResultTask
            print("   ✅ [ENSClient] rentPrice Check succeeded")
        } catch {
            print("   ❌ [ENSClient] rentPrice Check failed: \(error)")
            throw error
        }
        guard let priceArray = quoteResult["0"] as? [Any],
              priceArray.count >= 2,
              let baseWei = priceArray[0] as? BigUInt,
              let premiumWei = priceArray[1] as? BigUInt
        else {
            print("   [DEBUG-ENS] raw rentPrice dict: \(quoteResult)")
            throw ENSError.missingResult("rentPrice")
        }
        let rentPriceWei = baseWei + premiumWei
        let minCommitmentAgeSeconds = await minCommitmentAgeTask
        let commitPayload = try makeWritePayload(
            web3: web3,
            abi: Self.ethRegistrarControllerV2ABI,
            to: controllerAddress,
            method: "commit",
            parameters: [commitment],
            valueWei: .zero,
        )
        let registerPayload = try makeWritePayload(
            web3: web3,
            abi: Self.ethRegistrarControllerV2ABI,
            to: controllerAddress,
            method: "register",
            parameters: [
                [
                    label,
                    owner.address,
                    request.duration,
                    secretHex,
                    resolverAddress.address,
                    resolverData,
                    request.setReverseRecord ? 1 : 0, // uint8 mapping for bool
                    Data(count: 32), // referrer bytes32 (empty)
                ],
            ],
            valueWei: rentPriceWei,
        )

        return RegisterNameResultModel(
            commitCall: commitPayload,
            registerCall: registerPayload,
            minCommitmentAgeSeconds: minCommitmentAgeSeconds,
            secretHex: secretHex,
        )
    }

    private func minimumCommitmentAgeSeconds(
        web3: Web3,
        controllerAddress: EthereumAddress,
    ) async -> UInt64 {
        do {
            let minAgeResult = try await makeReadResult(
                web3: web3,
                abi: Self.ethRegistrarControllerV2ABI,
                to: controllerAddress,
                method: "minCommitmentAge",
                parameters: [],
            )
            guard let minAge = minAgeResult["0"] as? BigUInt else {
                return 60
            }
            let clamped = min(minAge, BigUInt(UInt64.max))
            return UInt64(clamped.description) ?? 60
        } catch {
            return 60
        }
    }

    private func parseWeiOverride(_ value: String) throws -> BigUInt {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalized.hasPrefix("0x") {
            let hex = String(normalized.dropFirst(2))
            guard let amount = BigUInt(hex, radix: 16) else {
                throw ENSError.missingResult("rentPriceWeiOverride")
            }
            return amount
        }
        guard let amount = BigUInt(normalized, radix: 10) else {
            throw ENSError.missingResult("rentPriceWeiOverride")
        }
        return amount
    }
}
