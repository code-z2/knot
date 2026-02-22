import Foundation

public struct ChainDefinitionModel: Sendable, Hashable, Identifiable {
    public let chainID: UInt64
    public let slug: String
    public let name: String
    public let assetName: String
    public let keywords: [String]
    public let rpcURL: String?
    public let explorerBaseURL: String?
    public let isTestnet: Bool
    public let spokePoolAddress: String?
    public let wrappedNativeTokenAddress: String?

    public var id: UInt64 {
        chainID
    }

    public init(
        chainID: UInt64,
        slug: String,
        name: String,
        assetName: String,
        keywords: [String],
        rpcURL: String?,
        explorerBaseURL: String?,
        isTestnet: Bool = false,
        spokePoolAddress: String? = nil,
        wrappedNativeTokenAddress: String? = nil,
    ) {
        self.chainID = chainID
        self.slug = slug
        self.name = name
        self.assetName = assetName
        self.keywords = keywords
        self.rpcURL = rpcURL
        self.explorerBaseURL = explorerBaseURL
        self.isTestnet = isTestnet
        self.spokePoolAddress = spokePoolAddress
        self.wrappedNativeTokenAddress = wrappedNativeTokenAddress
    }

    public func makeEndpoints(config: RPCEndpointBuilderConfig) -> ChainEndpointsModel? {
        let templatedRPCURL = makeURL(
            chainID: chainID,
            slug: slug,
            template: config.jsonRPCURLTemplate,
            apiKey: config.jsonRPCAPIKey,
        )
        let resolvedRPCURL = firstNonEmpty(templatedRPCURL, rpcURL ?? "")
        guard !resolvedRPCURL.isEmpty else {
            return nil
        }

        let walletAPIURL = makeURL(
            chainID: chainID,
            slug: slug,
            template: config.walletAPIURLTemplate,
        )
        let addressActivityAPIURL = makeURL(
            chainID: chainID,
            slug: slug,
            template: config.addressActivityAPIURLTemplate,
        )

        return ChainEndpointsModel(
            rpcURL: resolvedRPCURL,
            walletAPIURL: walletAPIURL,
            walletAPIBearerToken: config.walletAPIKey,
            addressActivityAPIURL: addressActivityAPIURL,
            addressActivityAPIBearerToken: config.addressActivityAPIKey,
        )
    }

    public func addressURL(address: String) -> URL? {
        guard let explorerBaseURL else {
            return nil
        }

        let normalized = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            return nil
        }

        return URL(string: "\(explorerBaseURL)/address/\(normalized)")
    }

    public func transactionURL(transactionHash: String) -> URL? {
        guard let explorerBaseURL else {
            return nil
        }

        let normalized = transactionHash.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            return nil
        }

        return URL(string: "\(explorerBaseURL)/tx/\(normalized)")
    }
}

private func makeURL(chainID: UInt64, slug: String, template: String) -> String {
    makeURL(chainID: chainID, slug: slug, template: template, apiKey: "")
}

private func makeURL(chainID: UInt64, slug: String, template: String, apiKey: String) -> String {
    var resolved = template.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !resolved.isEmpty else {
        return ""
    }

    resolved = resolved.replacingOccurrences(of: "{chainId}", with: String(chainID))
    resolved = resolved.replacingOccurrences(of: "{slug}", with: slug)

    if resolved.contains("{apiKey}") {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            return ""
        }
        resolved = resolved.replacingOccurrences(of: "{apiKey}", with: key)
    }

    return resolved
}

private func firstNonEmpty(_ candidates: String...) -> String {
    for candidate in candidates {
        let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            return trimmed
        }
    }

    return ""
}
