import Foundation

struct FeeAbstractionSnapshotModel: Codable, Sendable, Equatable {
    let payAsYouGoEnabled: Bool
    let overdraftEnabled: Bool
    let balanceNative: String?
    let initialized: Bool
    let minimumAllowedNative: String?
    let requiredTopUpNative: String?
    let suggestedTopUpNative: String?
    let lastUpdatedAt: Date?

    var isOverdraftEligible: Bool {
        guard let minimumAllowedNative else { return false }
        guard let minimumAllowed = DecimalParser.parse(minimumAllowedNative) else { return false }
        return minimumAllowed < 0
    }
}
