import CryptoKit
import Foundation

public extension RPCClient {
    func relaySubmit(
        account: String,
        supportMode: ChainSupportMode,
        immediateTxs: [RelayTransactionEnvelopeModel],
        backgroundTxs: [RelayTransactionEnvelopeModel],
        deferredTxs: [RelayTransactionEnvelopeModel],
        paymentOptions: [RelayPaymentOptionModel] = [],
    ) async throws -> RelaySubmitResultModel {
        let payload = RelaySubmitRequest(
            account: account,
            supportMode: supportMode.rawValue,
            immediateTxs: immediateTxs,
            backgroundTxs: backgroundTxs,
            deferredTxs: deferredTxs,
            paymentOptions: paymentOptions,
        )

        do {
            let encoded = try JSONEncoder().encode(payload)
            if let jsonString = String(data: encoded, encoding: .utf8) {
                print("================ [RELAYER SUBMIT PAYLOAD] ================")
                print(jsonString)
                print("==========================================================")
            }
        } catch {
            print("   [DEBUG-RPC] failed to debug-encode relay submit payload: \(error)")
        }

        return try await relayCall(
            path: "/v1/relay/submit",
            method: "POST",
            body: payload,
            responseType: RelaySubmitResultModel.self,
        )
    }

    func relayStatus(
        id: String,
        supportMode: ChainSupportMode = ChainSupportRuntime.resolveMode(),
    ) async throws -> RelayStatusModel {
        let response: RelayStatusResponse = try await relayCall(
            path: "/v1/relay/status",
            method: "GET",
            queryItems: [
                URLQueryItem(name: "id", value: id),
                URLQueryItem(name: "supportMode", value: supportMode.rawValue),
            ],
            responseType: RelayStatusResponse.self,
        )
        return response.status
    }

    func relayCredit(
        account: String,
        supportMode: ChainSupportMode,
    ) async throws -> RelayCreditResultModel {
        try await relayCall(
            path: "/v1/relay/credit",
            method: "GET",
            queryItems: [
                URLQueryItem(name: "account", value: account),
                URLQueryItem(name: "supportMode", value: supportMode.rawValue),
            ],
            responseType: RelayCreditResultModel.self,
        )
    }

    func relayFaucetFund(
        eoaAddress: String,
        supportMode: ChainSupportMode,
    ) async throws -> RelayFaucetFundResultModel {
        let payload = RelayFaucetFundRequestPayload(
            eoaAddress: eoaAddress,
            supportMode: supportMode.rawValue,
        )
        return try await relayCall(
            path: "/v1/faucet/fund",
            method: "POST",
            body: payload,
            responseType: RelayFaucetFundResultModel.self,
        )
    }

    func relayCreateImageUploadSession(
        eoaAddress: String,
        fileName: String,
        contentType: String,
    ) async throws -> RelayImageUploadSessionModel {
        let payload = RelayImageUploadSessionRequestPayload(
            eoaAddress: eoaAddress,
            fileName: fileName,
            contentType: contentType,
        )

        let bodyData: Data
        do {
            bodyData = try JSONEncoder().encode(payload)
        } catch {
            throw RPCError.relayRequestEncodingFailed(error)
        }

        return try await relayCall(
            path: "/v1/images/direct-upload",
            method: "POST",
            queryItems: [],
            bodyData: bodyData,
            responseType: RelayImageUploadSessionModel.self,
            endpointBaseURL: uploadProxyBaseURL(),
        )
    }

    func relayCall<Response: Decodable>(
        path: String,
        method: String,
        queryItems: [URLQueryItem] = [],
        body: some Encodable,
        responseType: Response.Type = Response.self,
    ) async throws -> Response {
        let bodyData: Data
        do {
            bodyData = try JSONEncoder().encode(body)
        } catch {
            throw RPCError.relayRequestEncodingFailed(error)
        }

        return try await relayCall(
            path: path,
            method: method,
            queryItems: queryItems,
            bodyData: bodyData,
            responseType: responseType,
        )
    }

    func relayCall<Response: Decodable>(
        path: String,
        method: String,
        queryItems: [URLQueryItem] = [],
        responseType: Response.Type = Response.self,
    ) async throws -> Response {
        try await relayCall(
            path: path,
            method: method,
            queryItems: queryItems,
            bodyData: Data(),
            responseType: responseType,
        )
    }

    private func relayCall<Response: Decodable>(
        path: String,
        method: String,
        queryItems: [URLQueryItem],
        bodyData: Data,
        responseType: Response.Type,
        endpointBaseURL: URL? = nil,
    ) async throws -> Response {
        let token = try relayClientToken()
        let baseURL = try (endpointBaseURL ?? relayBaseURL())
        let endpointBase = relayEndpoint(baseURL: baseURL, path: path)
        var components = URLComponents(
            url: endpointBase,
            resolvingAgainstBaseURL: false,
        )
        if !queryItems.isEmpty {
            components?.queryItems = queryItems
        }
        guard let endpoint = components?.url else {
            throw RPCError.invalidRelayProxyBaseURL(baseURL.absoluteString + path)
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = bodyData.isEmpty ? nil : bodyData
        applyRelaySignatureHeaders(&request, bodyData: bodyData)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw RPCError.relayServerError(status: -1, message: "No HTTP response")
        }

        if httpResponse.statusCode == 402 {
            do {
                let paymentRequired = try JSONDecoder().decode(
                    RelayPaymentRequiredModel.self,
                    from: data,
                )
                throw RPCError.relayPaymentRequired(paymentRequired)
            } catch let error as RPCError {
                throw error
            } catch {
                throw RPCError.relayResponseDecodingFailed(error)
            }
        }

        guard (200 ... 299).contains(httpResponse.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "Unknown relay proxy error"
            throw RPCError.relayServerError(status: httpResponse.statusCode, message: message)
        }

        do {
            return try JSONDecoder().decode(responseType, from: data)
        } catch {
            throw RPCError.relayResponseDecodingFailed(error)
        }
    }

    private func relayBaseURL() throws -> URL {
        let relayConfig = runtimeRelayConfig()
        let configured = relayConfig.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallback = RPCSecrets.relayProxyBaseURLDefault
        let resolved = configured.isEmpty ? fallback : configured
        let urlString = resolved.contains("://") ? resolved : "https://\(resolved)"
        guard let url = URL(string: urlString), let host = url.host, !host.isEmpty else {
            throw RPCError.invalidRelayProxyBaseURL(resolved)
        }
        return url
    }

    private func uploadProxyBaseURL() throws -> URL {
        let relayConfig = runtimeRelayConfig()
        let configured = relayConfig.uploadBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if configured.isEmpty {
            throw RPCError.invalidRelayProxyBaseURL("UPLOAD_PROXY_BASE_URL is not configured.")
        }

        let urlString = configured.contains("://") ? configured : "https://\(configured)"
        guard let url = URL(string: urlString), let host = url.host, !host.isEmpty else {
            throw RPCError.invalidRelayProxyBaseURL(configured)
        }
        return url
    }

    private func relayEndpoint(baseURL: URL, path: String) -> URL {
        path
            .split(separator: "/")
            .reduce(baseURL) { partialResult, segment in
                partialResult.appendingPathComponent(String(segment), isDirectory: false)
            }
    }

    private func relayClientToken() throws -> String {
        let relayConfig = runtimeRelayConfig()
        let token = relayConfig.clientToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else {
            throw RPCError.missingRelayProxyToken
        }
        return token
    }

    private func applyRelaySignatureHeaders(_ request: inout URLRequest, bodyData: Data) {
        let timestamp = String(Int(Date().timeIntervalSince1970))
        request.setValue(timestamp, forHTTPHeaderField: "X-Relay-Timestamp")

        let relayConfig = runtimeRelayConfig()
        let hmacSecret = relayConfig.hmacSecret.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !hmacSecret.isEmpty else {
            return
        }

        let payload = "\(timestamp).\(String(data: bodyData, encoding: .utf8) ?? "")"
        let key = SymmetricKey(data: Data(hmacSecret.utf8))
        let mac = HMAC<SHA256>.authenticationCode(for: Data(payload.utf8), using: key)
        let signature = mac.map { String(format: "%02x", $0) }.joined()
        request.setValue(signature, forHTTPHeaderField: "X-Relay-Signature")
    }
}
