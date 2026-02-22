import Foundation
import RPC

enum ProfileImageStorageError: LocalizedError {
    case missingCacheDirectory
    case invalidResponse
    case requestFailed(statusCode: Int, reason: String?)
    case pendingUpload

    var isRetryable: Bool {
        switch self {
        case .missingCacheDirectory, .pendingUpload:
            false
        case .invalidResponse:
            true
        case let .requestFailed(statusCode, _):
            statusCode == 429 || (500 ... 599).contains(statusCode)
        }
    }

    var errorDescription: String? {
        switch self {
        case .missingCacheDirectory:
            return "Unable to access local image cache directory."
        case .invalidResponse:
            return "Profile image upload returned an invalid response."
        case let .requestFailed(statusCode, reason):
            if let reason, !reason.isEmpty {
                return "Image upload request failed (\(statusCode)): \(reason)"
            }
            return "Image upload request failed (\(statusCode))."
        case .pendingUpload:
            return "Image upload is still pending. Please try saving again."
        }
    }
}

private struct PinataUploadResponse: Decodable {
    struct UploadData: Decodable {
        let cid: String
    }

    let data: UploadData?
    let cid: String?
}

final class ProfileImageStorageService {
    private let fileManager: FileManager
    private let session: URLSession
    private let rpcClient: RPCClient

    init(
        fileManager: FileManager = .default,
        session: URLSession = .shared,
        rpcClient: RPCClient = RPCClient(),
    ) {
        self.fileManager = fileManager
        self.session = session
        self.rpcClient = rpcClient
    }

    func persistLocally(data: Data, eoaAddress: String, fileName: String) throws -> URL {
        guard
            let cacheDirectory = fileManager.urls(
                for: .cachesDirectory,
                in: .userDomainMask,
            ).first
        else {
            throw ProfileImageStorageError.missingCacheDirectory
        }

        let userDirectory =
            cacheDirectory
                .appendingPathComponent("profile-images", isDirectory: true)
                .appendingPathComponent(sanitizedPathComponent(eoaAddress), isDirectory: true)
        try fileManager.createDirectory(at: userDirectory, withIntermediateDirectories: true)

        let fileURL = userDirectory.appendingPathComponent(fileName, isDirectory: false)
        try data.write(to: fileURL, options: .atomic)
        return fileURL
    }

    func uploadAvatar(
        data: Data,
        eoaAddress: String,
        fileName: String,
        mimeType: String,
    ) async throws -> URL {
        let uploadSession = try await withRetry {
            try await self.createDirectUploadSession(
                eoaAddress: eoaAddress,
                fileName: fileName,
                mimeType: mimeType,
            )
        }
        let cid = try await withRetry {
            try await self.uploadBinary(
                data: data,
                mimeType: mimeType,
                fileName: fileName,
                uploadURL: uploadSession.uploadURL,
            )
        }

        return try resolveDeliveryURL(
            gatewayBaseURL: uploadSession.gatewayBaseURL,
            cid: cid,
        )
    }

    private func createDirectUploadSession(
        eoaAddress: String,
        fileName: String,
        mimeType: String,
    ) async throws -> RelayImageUploadSessionModel {
        try await rpcClient.relayCreateImageUploadSession(
            eoaAddress: eoaAddress,
            fileName: fileName,
            contentType: mimeType,
        )
    }

    private func uploadBinary(
        data: Data,
        mimeType: String,
        fileName: String,
        uploadURL: URL,
    ) async throws -> String {
        let boundary = "Boundary-\(UUID().uuidString)"
        var request = URLRequest(url: uploadURL)
        request.httpMethod = "POST"
        request.setValue(
            "multipart/form-data; boundary=\(boundary)",
            forHTTPHeaderField: "Content-Type",
        )
        request.httpBody = buildMultipartBody(
            data: data,
            fileName: fileName,
            mimeType: mimeType,
            boundary: boundary,
        )

        let (responseData, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ProfileImageStorageError.invalidResponse
        }

        guard (200 ... 299).contains(httpResponse.statusCode) else {
            let reason = String(data: responseData, encoding: .utf8)
            throw ProfileImageStorageError.requestFailed(
                statusCode: httpResponse.statusCode,
                reason: reason,
            )
        }

        let uploadResponse: PinataUploadResponse
        do {
            uploadResponse = try JSONDecoder().decode(PinataUploadResponse.self, from: responseData)
        } catch {
            throw ProfileImageStorageError.invalidResponse
        }

        let cid = uploadResponse.data?.cid ?? uploadResponse.cid
        guard let cid, !cid.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ProfileImageStorageError.invalidResponse
        }
        return cid
    }

    private func buildMultipartBody(
        data: Data,
        fileName: String,
        mimeType: String,
        boundary: String,
    ) -> Data {
        let lineBreak = "\r\n"
        var body = Data()

        body.append(Data("--\(boundary)\(lineBreak)".utf8))
        body.append(
            Data("Content-Disposition: form-data; name=\"file\"; filename=\"\(fileName)\"\(lineBreak)".utf8),
        )
        body.append(Data("Content-Type: \(mimeType)\(lineBreak)\(lineBreak)".utf8))
        body.append(data)
        body.append(Data(lineBreak.utf8))

        body.append(Data("--\(boundary)--\(lineBreak)".utf8))
        return body
    }

    private func resolveDeliveryURL(gatewayBaseURL: String, cid: String) throws -> URL {
        let normalizedCID = cid.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedCID.isEmpty else {
            throw ProfileImageStorageError.invalidResponse
        }

        let base = gatewayBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !base.isEmpty else {
            throw ProfileImageStorageError.invalidResponse
        }

        let urlString: String
        if base.contains("{cid}") {
            urlString = base.replacingOccurrences(of: "{cid}", with: normalizedCID)
        } else {
            let trimmedBase = base.hasSuffix("/") ? String(base.dropLast()) : base
            urlString = "\(trimmedBase)/\(normalizedCID)"
        }

        guard let url = URL(string: urlString), let host = url.host, !host.isEmpty else {
            throw ProfileImageStorageError.invalidResponse
        }

        return url
    }

    private func sanitizedPathComponent(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let filteredScalars = value.lowercased().unicodeScalars.filter { allowed.contains($0) }
        let normalized = String(String.UnicodeScalarView(filteredScalars))
        return normalized.isEmpty ? "user" : normalized
    }

    private func withRetry<T>(
        maxAttempts: Int = 2,
        operation: @escaping () async throws -> T,
    ) async throws -> T {
        precondition(maxAttempts >= 1)
        var attempt = 0
        var lastError: Error?

        while attempt < maxAttempts {
            do {
                return try await operation()
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                lastError = error
                attempt += 1
                guard attempt < maxAttempts, shouldRetry(error: error) else {
                    throw error
                }
                do {
                    try await Task.sleep(for: .milliseconds(300))
                } catch {
                    throw error
                }
            }
        }

        throw lastError ?? ProfileImageStorageError.invalidResponse
    }

    private func shouldRetry(error: Error) -> Bool {
        if let storageError = error as? ProfileImageStorageError {
            return storageError.isRetryable
        }

        if error is URLError {
            return true
        }

        let nsError = error as NSError
        return nsError.domain == NSURLErrorDomain
    }
}
