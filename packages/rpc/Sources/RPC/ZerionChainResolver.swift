import Foundation

/// Resolved Zerion chain mapping: bidirectional map between numeric EVM chain IDs
/// and Zerion's string chain identifiers.
public struct ZerionChainMappingModel: Sendable {
    /// Numeric chain ID → Zerion string identifier (e.g. 1 → "ethereum").
    public let zerionIDByChainID: [UInt64: String]
    /// Zerion string identifier → Numeric chain ID (e.g. "ethereum" → 1).
    public let chainIDByZerionID: [String: UInt64]

    public init(zerionIDByChainID: [UInt64: String], chainIDByZerionID: [String: UInt64]) {
        self.zerionIDByChainID = zerionIDByChainID
        self.chainIDByZerionID = chainIDByZerionID
    }

    public static let empty = ZerionChainMappingModel(zerionIDByChainID: [:], chainIDByZerionID: [:])

    public var isEmpty: Bool {
        zerionIDByChainID.isEmpty
    }

    /// Resolve the Zerion chain identifiers for a set of supported chain IDs.
    /// Chains without a Zerion mapping are silently excluded.
    public func zerionChainIDs(for chainIDs: Set<UInt64>) -> [String] {
        chainIDs.compactMap { zerionIDByChainID[$0] }
    }

    /// Reverse-resolve a Zerion chain identifier to a numeric chain ID.
    public func chainID(zerionChainID: String) -> UInt64? {
        chainIDByZerionID[zerionChainID.lowercased()]
    }

    public func filtered(to supportedChainIDs: Set<UInt64>) -> ZerionChainMappingModel {
        guard !supportedChainIDs.isEmpty else { return .empty }
        var nextZerionByChain: [UInt64: String] = [:]
        var nextChainByZerion: [String: UInt64] = [:]

        for chainID in supportedChainIDs {
            guard let zerionID = zerionIDByChainID[chainID] else { continue }
            nextZerionByChain[chainID] = zerionID
            nextChainByZerion[zerionID] = chainID
        }

        return ZerionChainMappingModel(
            zerionIDByChainID: nextZerionByChain,
            chainIDByZerionID: nextChainByZerion,
        )
    }
}

/// Actor that fetches the list of supported chains from the Zerion API and builds
/// a bidirectional mapping between numeric EVM chain IDs and Zerion identifiers.
///
/// The mapping is cached in memory per mode and configured chain set.
public actor ZerionChainResolver {
    public static let shared = ZerionChainResolver()

    private var cachedMappings: [String: ZerionChainMappingModel] = [:]
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    /// Resolve the chain mapping, using a cached result if available.
    ///
    /// - Parameters:
    ///   - apiBaseURL: Base URL for the Zerion API (e.g., the wallet API URL without the wallet path).
    ///   - apiKey: Zerion API key for Basic auth.
    ///   - mode: Current chain support mode.
    ///   - supportedChainIDs: Configured chain IDs for the selected mode.
    /// - Returns: The chain mapping resolved from Zerion.
    public func resolve(
        apiBaseURL: String,
        apiKey: String,
        mode: ChainSupportMode,
        supportedChainIDs: Set<UInt64>,
    ) async throws -> ZerionChainMappingModel {
        let key = cacheKey(mode: mode, supportedChainIDs: supportedChainIDs)
        if let cached = cachedMappings[key] {
            return cached
        }

        let includeTestnets = mode == .limitedTestnet
        let remote = try await fetchChains(
            apiBaseURL: apiBaseURL,
            apiKey: apiKey,
            includeTestnets: includeTestnets,
        )
        let filtered = remote.filtered(to: supportedChainIDs)
        guard !filtered.isEmpty else {
            throw ZerionChainResolverError.noSupportedChainsResolved(
                mode: mode,
                supportedChainIDs: supportedChainIDs.sorted(),
            )
        }
        cachedMappings[key] = filtered
        return filtered
    }

    /// Force clear the cache (e.g., on network mode change).
    public func invalidate() {
        cachedMappings.removeAll()
    }

    // MARK: - Private

    private func cacheKey(mode: ChainSupportMode, supportedChainIDs: Set<UInt64>) -> String {
        let chainList = supportedChainIDs.sorted().map(String.init).joined(separator: ",")
        return "\(mode.rawValue)|\(chainList)"
    }

    private func fetchChains(
        apiBaseURL: String,
        apiKey: String,
        includeTestnets: Bool,
    ) async throws -> ZerionChainMappingModel {
        // Build URL: {apiBaseURL}/v1/chains/
        let baseURL =
            apiBaseURL
                .replacingOccurrences(of: #"\/v1\/wallets\/.*"#, with: "", options: .regularExpression)
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let urlString = "\(baseURL)/v1/chains/"

        guard let url = URL(string: urlString) else {
            throw ZerionChainResolverError.invalidURL(urlString)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(Self.basicAuthValue(apiKey: apiKey), forHTTPHeaderField: "Authorization")
        if includeTestnets {
            request.setValue("testnet", forHTTPHeaderField: "X-Env")
        }

        let (data, response) = try await session.data(for: request)

        if let httpResponse = response as? HTTPURLResponse,
           !(200 ... 299).contains(httpResponse.statusCode)
        {
            throw ZerionChainResolverError.httpError(statusCode: httpResponse.statusCode)
        }

        guard
            let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let rawChains = root["data"] as? [[String: Any]]
        else {
            throw ZerionChainResolverError.invalidResponse
        }

        var zerionIDByChainID: [UInt64: String] = [:]
        var chainIDByZerionID: [String: UInt64] = [:]

        for chain in rawChains {
            guard let zerionID = (chain["id"] as? String)?.lowercased(), !zerionID.isEmpty else {
                continue
            }
            guard
                let attributes = chain["attributes"] as? [String: Any],
                let rawExternalID = attributes["external_id"],
                let chainID = parseExternalChainID(rawExternalID)
            else {
                continue
            }
            zerionIDByChainID[chainID] = zerionID
            chainIDByZerionID[zerionID] = chainID
        }

        return ZerionChainMappingModel(
            zerionIDByChainID: zerionIDByChainID,
            chainIDByZerionID: chainIDByZerionID,
        )
    }

    private static func basicAuthValue(apiKey: String) -> String {
        let raw = "\(apiKey):"
        return "Basic \(Data(raw.utf8).base64EncodedString())"
    }

    private func parseExternalChainID(_ raw: Any) -> UInt64? {
        parseChainIDValue(raw)
    }

    private func parseChainIDValue(_ raw: Any) -> UInt64? {
        if let value = raw as? UInt64 { return value }
        if let value = raw as? Int, value >= 0 { return UInt64(value) }
        if let value = raw as? Double, value >= 0, floor(value) == value { return UInt64(value) }
        if let value = raw as? NSNumber { return value.uint64Value }
        if let value = raw as? String { return parseChainIDString(value) }
        return nil
    }

    private func parseChainIDString(_ value: String) -> UInt64? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return nil }

        if trimmed.hasPrefix("0x") {
            return UInt64(String(trimmed.dropFirst(2)), radix: 16)
        }

        if let direct = UInt64(trimmed) {
            return direct
        }

        let separators: [Character] = [":", "/"]
        for separator in separators {
            if let suffix = trimmed.split(separator: separator).last {
                let suffixValue = String(suffix)
                if suffixValue.hasPrefix("0x"),
                   let parsedHex = UInt64(String(suffixValue.dropFirst(2)), radix: 16)
                {
                    return parsedHex
                }
                if let parsed = UInt64(suffixValue) {
                    return parsed
                }
            }
        }

        return nil
    }
}
