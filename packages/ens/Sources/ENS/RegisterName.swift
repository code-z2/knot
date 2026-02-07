import Foundation
import BigInt
import Web3Core
import web3swift

extension ENSClient {
  static let ethRegistrarControllerV2ABI = """
  [{"inputs":[],"name":"minCommitmentAge","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},{"inputs":[{"internalType":"string","name":"name","type":"string"}],"name":"available","outputs":[{"internalType":"bool","name":"","type":"bool"}],"stateMutability":"view","type":"function"},{"inputs":[{"internalType":"string","name":"name","type":"string"},{"internalType":"uint256","name":"duration","type":"uint256"}],"name":"rentPrice","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},{"inputs":[{"internalType":"string","name":"name","type":"string"},{"internalType":"address","name":"owner","type":"address"},{"internalType":"uint256","name":"duration","type":"uint256"},{"internalType":"bytes32","name":"secret","type":"bytes32"},{"internalType":"address","name":"resolver","type":"address"},{"internalType":"bytes[]","name":"data","type":"bytes[]"},{"internalType":"bool","name":"reverseRecord","type":"bool"},{"internalType":"uint16","name":"ownerControlledFuses","type":"uint16"}],"name":"makeCommitment","outputs":[{"internalType":"bytes32","name":"","type":"bytes32"}],"stateMutability":"pure","type":"function"},{"inputs":[{"internalType":"bytes32","name":"commitment","type":"bytes32"}],"name":"commit","outputs":[],"stateMutability":"nonpayable","type":"function"},{"inputs":[{"internalType":"string","name":"name","type":"string"},{"internalType":"address","name":"owner","type":"address"},{"internalType":"uint256","name":"duration","type":"uint256"},{"internalType":"bytes32","name":"secret","type":"bytes32"},{"internalType":"address","name":"resolver","type":"address"},{"internalType":"bytes[]","name":"data","type":"bytes[]"},{"internalType":"bool","name":"reverseRecord","type":"bool"},{"internalType":"uint16","name":"ownerControlledFuses","type":"uint16"}],"name":"register","outputs":[],"stateMutability":"payable","type":"function"}]
  """

  public func quoteRegistration(_ request: RegisterNameRequest) async throws -> NameAvailabilityQuote {
    let normalizedName = Self.normalizedENSName(request.name)
    let label = Self.ethLabel(from: normalizedName)
    guard !label.isEmpty, !label.contains(".") else {
      throw ENSError.invalidName
    }

    guard let controllerAddress = EthereumAddress(configuration.registrarControllerAddress) else {
      throw ENSError.invalidAddress(configuration.registrarControllerAddress)
    }

    let web3 = try await rpcClient.getWeb3Client(chainId: configuration.chainID)
    let availabilityResult = try await makeReadResult(
      web3: web3,
      abi: Self.ethRegistrarControllerV2ABI,
      to: controllerAddress,
      method: "available",
      parameters: [label]
    )
    guard let available = availabilityResult["0"] as? Bool else {
      throw ENSError.missingResult("available")
    }
    let rentPriceWei: BigUInt
    if let override = request.rentPriceWeiOverride {
      rentPriceWei = try parseWeiOverride(override)
    } else {
      let quoteResult = try await makeReadResult(
        web3: web3,
        abi: Self.ethRegistrarControllerV2ABI,
        to: controllerAddress,
        method: "rentPrice",
        parameters: [label, request.duration]
      )
      guard let quote = quoteResult["0"] as? BigUInt else {
        throw ENSError.missingResult("rentPrice")
      }
      rentPriceWei = quote
    }

    return NameAvailabilityQuote(
      label: label,
      normalizedName: normalizedName,
      available: available,
      rentPriceWei: rentPriceWei.description
    )
  }

  public func registerName(_ request: RegisterNameRequest) async throws -> RegisterNameResult {
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

    let web3 = try await rpcClient.getWeb3Client(chainId: configuration.chainID)
    let availabilityResult = try await makeReadResult(
      web3: web3,
      abi: Self.ethRegistrarControllerV2ABI,
      to: controllerAddress,
      method: "available",
      parameters: [label]
    )
    guard let available = availabilityResult["0"] as? Bool else {
      throw ENSError.missingResult("available")
    }
    guard available else {
      throw ENSError.nameUnavailable(label)
    }

    let secretHex = Self.secretHex(from: request.secretHex)
    var resolverData: [Data] = []
    resolverData.append(
      try makeCallData(
        web3: web3,
        abi: Web3.Utils.resolverABI,
        method: "setAddr",
        parameters: [nodeHash, owner.address]
      )
    )
    for record in request.initialTextRecords where !record.key.isEmpty {
      resolverData.append(
        try makeCallData(
          web3: web3,
          abi: Web3.Utils.resolverABI,
          method: "setText",
          parameters: [nodeHash, record.key, record.value]
        )
      )
    }

    let commitmentResult = try await makeReadResult(
      web3: web3,
      abi: Self.ethRegistrarControllerV2ABI,
      to: controllerAddress,
      method: "makeCommitment",
      parameters: [
        label,
        owner.address,
        request.duration,
        secretHex,
        resolverAddress.address,
        resolverData,
        request.setReverseRecord,
        BigUInt(request.ownerControlledFuses),
      ]
    )
    guard let commitment = commitmentResult["0"] as? Data else {
      throw ENSError.missingResult("commitment")
    }

    let quoteResult = try await makeReadResult(
      web3: web3,
      abi: Self.ethRegistrarControllerV2ABI,
      to: controllerAddress,
      method: "rentPrice",
      parameters: [label, request.duration]
    )
    guard let rentPriceWei = quoteResult["0"] as? BigUInt else {
      throw ENSError.missingResult("rentPrice")
    }
    let minCommitmentAgeSeconds = await minimumCommitmentAgeSeconds(
      web3: web3,
      controllerAddress: controllerAddress
    )
    let commitPayload = try makeWritePayload(
      web3: web3,
      abi: Self.ethRegistrarControllerV2ABI,
      to: controllerAddress,
      method: "commit",
      parameters: [commitment],
      valueWei: .zero
    )
    let registerPayload = try makeWritePayload(
      web3: web3,
      abi: Self.ethRegistrarControllerV2ABI,
      to: controllerAddress,
      method: "register",
      parameters: [
        label,
        owner.address,
        request.duration,
        secretHex,
        resolverAddress.address,
        resolverData,
        request.setReverseRecord,
        BigUInt(request.ownerControlledFuses),
      ],
      valueWei: rentPriceWei
    )

    return RegisterNameResult(
      commitCall: commitPayload,
      registerCall: registerPayload,
      minCommitmentAgeSeconds: minCommitmentAgeSeconds,
      secretHex: secretHex
    )
  }

  private func minimumCommitmentAgeSeconds(
    web3: Web3,
    controllerAddress: EthereumAddress
  ) async -> UInt64 {
    do {
      let minAgeResult = try await makeReadResult(
        web3: web3,
        abi: Self.ethRegistrarControllerV2ABI,
        to: controllerAddress,
        method: "minCommitmentAge",
        parameters: []
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
      guard let amount = BigUInt(hex, radix: 16) else { throw ENSError.missingResult("rentPriceWeiOverride") }
      return amount
    }
    guard let amount = BigUInt(normalized, radix: 10) else { throw ENSError.missingResult("rentPriceWeiOverride") }
    return amount
  }
}
