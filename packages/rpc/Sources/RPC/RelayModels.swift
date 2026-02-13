import Foundation

public enum RelaySupportMode: String, Sendable, Codable {
  case limitedTestnet = "LIMITED_TESTNET"
  case limitedMainnet = "LIMITED_MAINNET"
  case fullMainnet = "FULL_MAINNET"
}

public struct RelayAuthorization: Sendable, Codable, Equatable {
  public let address: String
  public let chainId: String
  public let nonce: String
  public let r: String
  public let s: String
  public let yParity: String

  public init(address: String, chainId: String, nonce: String, r: String, s: String, yParity: String) {
    self.address = address
    self.chainId = chainId
    self.nonce = nonce
    self.r = r
    self.s = s
    self.yParity = yParity
  }
}

public struct RelayTransactionRequest: Sendable, Codable, Equatable {
  public let from: String
  public let to: String
  public let data: String
  public let value: String
  public let gasLimit: String?
  public let isSponsored: Bool
  public let authorization: RelayAuthorization?
  public let paymentToken: String?

  public init(
    from: String,
    to: String,
    data: String,
    value: String = "0x0",
    gasLimit: String? = nil,
    isSponsored: Bool = true,
    authorization: RelayAuthorization? = nil,
    paymentToken: String? = nil
  ) {
    self.from = from
    self.to = to
    self.data = data
    self.value = value
    self.gasLimit = gasLimit
    self.isSponsored = isSponsored
    self.authorization = authorization
    self.paymentToken = paymentToken
  }
}

public struct RelayTx: Sendable, Codable, Equatable {
  public let chainId: UInt64
  public let request: RelayTransactionRequest

  public init(chainId: UInt64, request: RelayTransactionRequest) {
    self.chainId = chainId
    self.request = request
  }
}

public struct RelaySubmission: Sendable, Decodable, Equatable {
  public let chainId: UInt64
  public let id: String
  public let transactionHash: String?

  public init(chainId: UInt64, id: String, transactionHash: String?) {
    self.chainId = chainId
    self.id = id
    self.transactionHash = transactionHash
  }
}

public struct RelayStatus: Sendable, Decodable, Equatable {
  public let id: String
  public let rawStatus: String
  public let state: String
  public let transactionHash: String?
  public let blockNumber: String?
  public let failureReason: String?

  public init(
    id: String,
    rawStatus: String,
    state: String,
    transactionHash: String?,
    blockNumber: String?,
    failureReason: String?
  ) {
    self.id = id
    self.rawStatus = rawStatus
    self.state = state
    self.transactionHash = transactionHash
    self.blockNumber = blockNumber
    self.failureReason = failureReason
  }
}

public struct RelaySubmitResult: Sendable, Decodable, Equatable {
  public struct Accounting: Sendable, Decodable, Equatable {
    public let supportMode: String
    public let estimatedDebitUsdc: String
    public let balanceBeforeUsdc: String
    public let balanceAfterUsdc: String

    public init(
      supportMode: String,
      estimatedDebitUsdc: String,
      balanceBeforeUsdc: String,
      balanceAfterUsdc: String
    ) {
      self.supportMode = supportMode
      self.estimatedDebitUsdc = estimatedDebitUsdc
      self.balanceBeforeUsdc = balanceBeforeUsdc
      self.balanceAfterUsdc = balanceAfterUsdc
    }
  }

  public let ok: Bool
  public let accounting: Accounting?
  public let prioritySubmissions: [RelaySubmission]
  public let submissions: [RelaySubmission]

  public init(
    ok: Bool,
    accounting: Accounting?,
    prioritySubmissions: [RelaySubmission],
    submissions: [RelaySubmission]
  ) {
    self.ok = ok
    self.accounting = accounting
    self.prioritySubmissions = prioritySubmissions
    self.submissions = submissions
  }
}

public struct RelayCreditResult: Sendable, Decodable, Equatable {
  public let ok: Bool
  public let account: String
  public let supportMode: String
  public let balanceUsdc: String

  public init(ok: Bool, account: String, supportMode: String, balanceUsdc: String) {
    self.ok = ok
    self.account = account
    self.supportMode = supportMode
    self.balanceUsdc = balanceUsdc
  }
}

public struct RelayImageUploadSession: Sendable, Decodable, Equatable {
  public let ok: Bool
  public let uploadURL: URL
  public let imageID: String
  public let gatewayBaseURL: String

  public init(ok: Bool, uploadURL: URL, imageID: String, gatewayBaseURL: String) {
    self.ok = ok
    self.uploadURL = uploadURL
    self.imageID = imageID
    self.gatewayBaseURL = gatewayBaseURL
  }
}

public struct RelayFaucetFundResult: Sendable, Decodable, Equatable {
  public let ok: Bool
  public let status: String

  public init(ok: Bool, status: String) {
    self.ok = ok
    self.status = status
  }
}

public struct RelayPaymentOption: Sendable, Codable, Equatable {
  public let chainId: UInt64
  public let tokenAddress: String
  public let symbol: String
  public let amount: String

  public init(chainId: UInt64, tokenAddress: String, symbol: String, amount: String) {
    self.chainId = chainId
    self.tokenAddress = tokenAddress
    self.symbol = symbol
    self.amount = amount
  }
}

public struct RelayPaymentRequired: Sendable, Decodable, Equatable {
  public let ok: Bool
  public let error: String
  public let account: String
  public let supportMode: String
  public let estimatedDebitUsdc: String
  public let balanceUsdc: String
  public let postDebitUsdc: String
  public let minimumAllowedUsdc: String
  public let requiredTopUpUsdc: String
  public let suggestedTopUpUsdc: String
  public let paymentOptions: [RelayPaymentOption]

  public init(
    ok: Bool,
    error: String,
    account: String,
    supportMode: String,
    estimatedDebitUsdc: String,
    balanceUsdc: String,
    postDebitUsdc: String,
    minimumAllowedUsdc: String,
    requiredTopUpUsdc: String,
    suggestedTopUpUsdc: String,
    paymentOptions: [RelayPaymentOption]
  ) {
    self.ok = ok
    self.error = error
    self.account = account
    self.supportMode = supportMode
    self.estimatedDebitUsdc = estimatedDebitUsdc
    self.balanceUsdc = balanceUsdc
    self.postDebitUsdc = postDebitUsdc
    self.minimumAllowedUsdc = minimumAllowedUsdc
    self.requiredTopUpUsdc = requiredTopUpUsdc
    self.suggestedTopUpUsdc = suggestedTopUpUsdc
    self.paymentOptions = paymentOptions
  }
}

public struct RelayProxyConfig: Sendable, Equatable {
  public let baseURL: String
  public let uploadBaseURL: String
  public let clientToken: String
  public let hmacSecret: String

  public init(
    baseURL: String = "",
    uploadBaseURL: String = "",
    clientToken: String = "",
    hmacSecret: String = ""
  ) {
    self.baseURL = baseURL
    self.uploadBaseURL = uploadBaseURL
    self.clientToken = clientToken
    self.hmacSecret = hmacSecret
  }
}

struct RelaySubmitAuthorizationPayload: Encodable {
  let address: String
  let chainId: String
  let nonce: String
  let r: String
  let s: String
  let yParity: String

  init(_ auth: RelayAuthorization) {
    self.address = auth.address
    self.chainId = auth.chainId
    self.nonce = auth.nonce
    self.r = auth.r
    self.s = auth.s
    self.yParity = auth.yParity
  }
}

struct RelaySubmitRequestPayload: Encodable {
  let from: String
  let to: String
  let data: String
  let value: String
  let gasLimit: String?
  let isSponsored: Bool
  let authorizationList: [RelaySubmitAuthorizationPayload]?
  let eip7702Auth: RelaySubmitAuthorizationPayload?
  let paymentToken: String?

  init(_ request: RelayTransactionRequest) {
    self.from = request.from
    self.to = request.to
    self.data = request.data
    self.value = request.value
    self.gasLimit = request.gasLimit
    self.isSponsored = request.isSponsored
    if let auth = request.authorization {
      let encoded = RelaySubmitAuthorizationPayload(auth)
      self.authorizationList = [encoded]
      self.eip7702Auth = encoded
    } else {
      self.authorizationList = nil
      self.eip7702Auth = nil
    }
    self.paymentToken = request.paymentToken
  }
}

struct RelaySubmitTxPayload: Encodable {
  let chainId: UInt64
  let request: RelaySubmitRequestPayload

  init(_ tx: RelayTx) {
    self.chainId = tx.chainId
    self.request = RelaySubmitRequestPayload(tx.request)
  }
}

struct RelaySubmitRequest: Encodable {
  let account: String
  let supportMode: String
  let priorityTxs: [RelaySubmitTxPayload]
  let txs: [RelaySubmitTxPayload]
  let paymentOptions: [RelayPaymentOption]
}

struct RelayStatusResponse: Decodable {
  let ok: Bool
  let chainId: UInt64
  let status: RelayStatus
}

struct RelayImageUploadSessionRequestPayload: Encodable {
  let eoaAddress: String
  let fileName: String
  let contentType: String
}

struct RelayFaucetFundRequestPayload: Encodable {
  let eoaAddress: String
}
