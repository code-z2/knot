import ENS
import Foundation

actor ENSQuoteWorker {
    private let client: ENSClient

    init(configuration: ENSConfiguration) {
        client = ENSClient(configuration: configuration)
    }

    func quote(name: String) async throws -> ENSNameQuote {
        let quote = try await client.quoteRegistration(
            RegisterNameRequestModel(
                name: name,
                ownerAddress: "0x0000000000000000000000000000000000000000",
                duration: 31_536_000,
            ),
        )
        return ENSNameQuote(
            normalizedName: quote.normalizedName,
            available: quote.available,
            rentPriceWei: quote.rentPriceWei,
        )
    }
}

struct PendingAvatarUpload {
    let id: UUID
    let data: Data
    let mimeType: String
    let fileName: String
}

enum NameInfoTone {
    case info
    case success
    case error
}

enum ProfileAsyncStateModel: Equatable {
    case idle
    case inProgress
    case succeeded
    case failed(String)
}
