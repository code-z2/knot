import Foundation

public struct ENSConfiguration: Sendable, Equatable {
  public let chainID: UInt64
  public let registrarControllerAddress: String
  public let publicResolverAddress: String
  public let universalResolverAddress: String

  public init(
    chainID: UInt64,
    registrarControllerAddress: String,
    publicResolverAddress: String,
    universalResolverAddress: String
  ) {
    self.chainID = chainID
    self.registrarControllerAddress = registrarControllerAddress
    self.publicResolverAddress = publicResolverAddress
    self.universalResolverAddress = universalResolverAddress
  }
}

public extension ENSConfiguration {
  static let sepolia = ENSConfiguration(
    chainID: 11155111,
    registrarControllerAddress: "0xfb3cE5D01e0f33f41DbB39035dB9745962F1f968",
    publicResolverAddress: "0xE99638b40E4Fff0129D56f03b55b6bbC4BBE49b5",
    universalResolverAddress: "0xeEeEEEeE14D718C2B47D9923Deab1335E144EeEe"
  )
}
