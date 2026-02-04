import Foundation
import BigInt
import Web3Core
import web3swift

extension ENSClient {
  public func quoteRegistration(_ request: RegisterNameRequest) async throws -> NameAvailabilityQuote {
    let normalizedName = Self.normalizedENSName(request.name)
    let label = Self.ethLabel(from: normalizedName)
    guard !label.isEmpty, !label.contains(".") else {
      throw ENSError.invalidName
    }

    guard let controllerAddress = EthereumAddress(request.registrarControllerAddress) else {
      throw ENSError.invalidAddress(request.registrarControllerAddress)
    }

    let web3 = try await rpcClient.getWeb3Client(chainId: 1)
    let controller = web3swift.ENS.ETHRegistrarController(web3: web3, address: controllerAddress)

    let available = try await controller.isNameAvailable(name: label)
    let rentPriceWei: BigUInt = if let override = request.rentPriceWeiOverride {
      try parseWeiOverride(override)
    } else {
      try await controller.getRentPrice(name: label, duration: request.duration)
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

    guard let controllerAddress = EthereumAddress(request.registrarControllerAddress) else {
      throw ENSError.invalidAddress(request.registrarControllerAddress)
    }

    let web3 = try await rpcClient.getWeb3Client(chainId: 1)

    let controller = web3swift.ENS.ETHRegistrarController(web3: web3, address: controllerAddress)

    let available = try await controller.isNameAvailable(name: label)
    guard available else {
      throw ENSError.nameUnavailable(label)
    }

    let secretHex = Self.secretHex(from: request.secretHex)

    let commitment = try await controller.calculateCommitmentHash(
      name: label,
      owner: owner,
      secret: secretHex
    )

    let rentPriceWei = try await controller.getRentPrice(name: label, duration: request.duration)
    let commitPayload = try makeWritePayload(
      web3: web3,
      abi: Web3.Utils.ethRegistrarControllerABI,
      to: controllerAddress,
      method: "commit",
      parameters: [commitment],
      valueWei: .zero
    )
    let registerPayload = try makeWritePayload(
      web3: web3,
      abi: Web3.Utils.ethRegistrarControllerABI,
      to: controllerAddress,
      method: "register",
      parameters: [label, owner.address, request.duration, secretHex],
      valueWei: rentPriceWei
    )

    return RegisterNameResult(calls: [commitPayload, registerPayload], secretHex: secretHex)
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
