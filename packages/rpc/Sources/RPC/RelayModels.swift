import Foundation

public struct RelayAuthorizationModel: Sendable, Codable, Equatable {
    public let address: String

    public let chainId: UInt64

    public let nonce: UInt64

    public let r: String

    public let s: String

    public let yParity: UInt8

    public init(
        address: String,
        chainId: UInt64,
        nonce: UInt64,
        r: String,
        s: String,
        yParity: UInt8,
    ) {
        self.address = address
        self.chainId = chainId
        self.nonce = nonce
        self.r = r
        self.s = s
        self.yParity = yParity
    }
}

public struct RelayTransactionRequestModel: Sendable, Codable, Equatable {
    public let from: String

    public let to: String

    public let data: String

    public let value: String

    public let isSponsored: Bool

    public let authorizationList: [RelayAuthorizationModel]

    public let paymentToken: String?

    public init(
        from: String,
        to: String,
        data: String,
        value: String = "0x0",
        isSponsored: Bool = true,
        authorizationList: [RelayAuthorizationModel] = [],
        paymentToken: String? = nil,
    ) {
        self.from = from
        self.to = to
        self.data = data
        self.value = value
        self.isSponsored = isSponsored
        self.authorizationList = authorizationList
        self.paymentToken = paymentToken
    }
}

public struct RelayTransactionEnvelopeModel: Sendable, Codable, Equatable {
    public let chainId: UInt64

    public let request: RelayTransactionRequestModel

    public init(chainId: UInt64, request: RelayTransactionRequestModel) {
        self.chainId = chainId
        self.request = request
    }
}

public struct RelaySubmissionModel: Sendable, Decodable, Equatable {
    public let chainId: UInt64

    public let id: String

    public let transactionHash: String?

    public init(chainId: UInt64, id: String, transactionHash: String?) {
        self.chainId = chainId
        self.id = id
        self.transactionHash = transactionHash
    }
}

public struct RelayStatusModel: Sendable, Decodable, Equatable {
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
        failureReason: String?,
    ) {
        self.id = id
        self.rawStatus = rawStatus
        self.state = state
        self.transactionHash = transactionHash
        self.blockNumber = blockNumber
        self.failureReason = failureReason
    }
}

public struct RelaySubmitResultModel: Sendable, Decodable, Equatable {
    public struct Accounting: Sendable, Decodable, Equatable {
        public let supportMode: String

        public let estimatedDebitUsdc: String

        public let balanceBeforeUsdc: String

        public let balanceAfterUsdc: String

        public init(
            supportMode: String,
            estimatedDebitUsdc: String,
            balanceBeforeUsdc: String,
            balanceAfterUsdc: String,
        ) {
            self.supportMode = supportMode
            self.estimatedDebitUsdc = estimatedDebitUsdc
            self.balanceBeforeUsdc = balanceBeforeUsdc
            self.balanceAfterUsdc = balanceAfterUsdc
        }
    }

    public let ok: Bool

    public let accounting: Accounting?

    public let immediateSubmissions: [RelaySubmissionModel]

    public let backgroundSubmissions: [RelaySubmissionModel]

    public let deferredSubmissions: [RelaySubmissionModel]

    public init(
        ok: Bool,
        accounting: Accounting?,
        immediateSubmissions: [RelaySubmissionModel],
        backgroundSubmissions: [RelaySubmissionModel],
        deferredSubmissions: [RelaySubmissionModel] = [],
    ) {
        self.ok = ok
        self.accounting = accounting
        self.immediateSubmissions = immediateSubmissions
        self.backgroundSubmissions = backgroundSubmissions
        self.deferredSubmissions = deferredSubmissions
    }

    enum CodingKeys: String, CodingKey {
        case ok
        case accounting
        case immediateSubmissions
        case backgroundSubmissions
        case deferredSubmissions
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        ok = try container.decode(Bool.self, forKey: .ok)
        accounting = try container.decodeIfPresent(Accounting.self, forKey: .accounting)
        immediateSubmissions =
            try container.decodeIfPresent([RelaySubmissionModel].self, forKey: .immediateSubmissions)
                ?? []
        backgroundSubmissions =
            try container.decodeIfPresent([RelaySubmissionModel].self, forKey: .backgroundSubmissions)
                ?? []
        deferredSubmissions =
            try container.decodeIfPresent([RelaySubmissionModel].self, forKey: .deferredSubmissions)
                ?? []
    }
}

public struct RelayCreditResultModel: Sendable, Decodable, Equatable {
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

public struct RelayImageUploadSessionModel: Sendable, Decodable, Equatable {
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

public struct RelayFaucetFundResultModel: Sendable, Decodable, Equatable {
    public let ok: Bool

    public let status: String

    public init(ok: Bool, status: String) {
        self.ok = ok
        self.status = status
    }
}

public struct RelayPaymentOptionModel: Sendable, Codable, Equatable {
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

public struct RelayPaymentRequiredModel: Sendable, Decodable, Equatable {
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

    public let paymentOptions: [RelayPaymentOptionModel]

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
        paymentOptions: [RelayPaymentOptionModel],
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

public struct RelayProxyConfigModel: Sendable, Equatable {
    public let baseURL: String

    public let uploadBaseURL: String

    public let clientToken: String

    public let hmacSecret: String

    public init(
        baseURL: String = "",
        uploadBaseURL: String = "",
        clientToken: String = "",
        hmacSecret: String = "",
    ) {
        self.baseURL = baseURL
        self.uploadBaseURL = uploadBaseURL
        self.clientToken = clientToken
        self.hmacSecret = hmacSecret
    }
}

struct RelaySubmitRequest: Encodable {
    let account: String
    let supportMode: String
    let immediateTxs: [RelayTransactionEnvelopeModel]
    let backgroundTxs: [RelayTransactionEnvelopeModel]
    let deferredTxs: [RelayTransactionEnvelopeModel]
    let paymentOptions: [RelayPaymentOptionModel]
}

struct RelayStatusResponse: Decodable {
    let ok: Bool
    let status: RelayStatusModel
}

struct RelayImageUploadSessionRequestPayload: Encodable {
    let eoaAddress: String
    let fileName: String
    let contentType: String
}

struct RelayFaucetFundRequestPayload: Encodable {
    let eoaAddress: String
    let supportMode: String
}
