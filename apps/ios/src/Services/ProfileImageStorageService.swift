import Foundation

enum ProfileImageStorageError: LocalizedError {
  case missingCacheDirectory
  case invalidConfiguration
  case invalidResponse
  case requestFailed(statusCode: Int, reason: String?)
  case pendingUpload

  var errorDescription: String? {
    switch self {
    case .missingCacheDirectory:
      return "Unable to access local image cache directory."
    case .invalidConfiguration:
      return "Profile image upload is not configured."
    case .invalidResponse:
      return "Profile image upload returned an invalid response."
    case .requestFailed(let statusCode, let reason):
      if let reason, !reason.isEmpty {
        return "Image upload request failed (\(statusCode)): \(reason)"
      }
      return "Image upload request failed (\(statusCode))."
    case .pendingUpload:
      return "Image upload is still pending. Please try saving again."
    }
  }
}

private struct DirectUploadSession: Decodable {
  let uploadURL: URL
  let imageID: String
  let deliveryURL: URL
}

private struct DirectUploadSessionRequest: Encodable {
  let eoaAddress: String
  let fileName: String
  let contentType: String
}

final class ProfileImageStorageService {
  private let fileManager: FileManager
  private let session: URLSession
  private let workerBaseURL: URL
  private let clientToken: String?

  init(
    fileManager: FileManager = .default,
    session: URLSession = .shared,
    workerBaseURL: URL = ProfileImageStorageService.defaultWorkerBaseURL,
    clientToken: String? = ProfileImageStorageService.defaultClientToken
  ) {
    self.fileManager = fileManager
    self.session = session
    self.workerBaseURL = workerBaseURL
    self.clientToken = clientToken?.isEmpty == true ? nil : clientToken
  }

  func persistLocally(data: Data, eoaAddress: String, fileName: String) throws -> URL {
    guard let cacheDirectory = fileManager.urls(
      for: .cachesDirectory,
      in: .userDomainMask
    ).first else {
      throw ProfileImageStorageError.missingCacheDirectory
    }

    let userDirectory = cacheDirectory
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
    mimeType: String
  ) async throws -> URL {
    let uploadSession = try await createDirectUploadSession(
      eoaAddress: eoaAddress,
      fileName: fileName,
      mimeType: mimeType
    )
    try await uploadBinary(
      data: data,
      fileName: fileName,
      mimeType: mimeType,
      uploadURL: uploadSession.uploadURL
    )
    return uploadSession.deliveryURL
  }

  private func createDirectUploadSession(
    eoaAddress: String,
    fileName: String,
    mimeType: String
  ) async throws -> DirectUploadSession {
    guard !workerBaseURL.absoluteString.isEmpty else {
      throw ProfileImageStorageError.invalidConfiguration
    }

    let url = workerBaseURL
      .appendingPathComponent("v1", isDirectory: true)
      .appendingPathComponent("images", isDirectory: true)
      .appendingPathComponent("direct-upload", isDirectory: false)

    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    if let clientToken {
      request.setValue("Bearer \(clientToken)", forHTTPHeaderField: "Authorization")
    }

    request.httpBody = try JSONEncoder().encode(
      DirectUploadSessionRequest(
        eoaAddress: eoaAddress,
        fileName: fileName,
        contentType: mimeType
      )
    )

    let (data, response) = try await session.data(for: request)
    guard let httpResponse = response as? HTTPURLResponse else {
      throw ProfileImageStorageError.invalidResponse
    }

    guard (200...299).contains(httpResponse.statusCode) else {
      let reason = String(data: data, encoding: .utf8)
      throw ProfileImageStorageError.requestFailed(
        statusCode: httpResponse.statusCode,
        reason: reason
      )
    }

    do {
      return try JSONDecoder().decode(DirectUploadSession.self, from: data)
    } catch {
      throw ProfileImageStorageError.invalidResponse
    }
  }

  private func uploadBinary(
    data: Data,
    fileName: String,
    mimeType: String,
    uploadURL: URL
  ) async throws {
    let boundary = "Boundary-\(UUID().uuidString)"
    var request = URLRequest(url: uploadURL)
    request.httpMethod = "POST"
    request.setValue(
      "multipart/form-data; boundary=\(boundary)",
      forHTTPHeaderField: "Content-Type"
    )

    let body = makeMultipartBody(
      data: data,
      fileName: fileName,
      mimeType: mimeType,
      boundary: boundary
    )

    let (_, response) = try await session.upload(for: request, from: body)
    guard let httpResponse = response as? HTTPURLResponse else {
      throw ProfileImageStorageError.invalidResponse
    }
    guard (200...299).contains(httpResponse.statusCode) else {
      throw ProfileImageStorageError.requestFailed(
        statusCode: httpResponse.statusCode,
        reason: nil
      )
    }
  }

  private func makeMultipartBody(
    data: Data,
    fileName: String,
    mimeType: String,
    boundary: String
  ) -> Data {
    var body = Data()
    let header = """
      --\(boundary)\r
      Content-Disposition: form-data; name="file"; filename="\(fileName)"\r
      Content-Type: \(mimeType)\r
      \r
      """
    body.append(Data(header.utf8))
    body.append(data)
    body.append(Data("\r\n--\(boundary)--\r\n".utf8))
    return body
  }

  private func sanitizedPathComponent(_ value: String) -> String {
    let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
    let filteredScalars = value.lowercased().unicodeScalars.filter { allowed.contains($0) }
    let normalized = String(String.UnicodeScalarView(filteredScalars))
    return normalized.isEmpty ? "user" : normalized
  }

  static var defaultWorkerBaseURL: URL {
    if let configured = Bundle.main.object(
      forInfoDictionaryKey: "PROFILE_IMAGE_UPLOAD_WORKER_BASE_URL"
    ) as? String,
      let url = URL(string: configured),
      !configured.isEmpty {
      return url
    }

    return URL(string: "https://upload.peteranyaogu.com")!
  }

  static var defaultClientToken: String? {
    Bundle.main.object(forInfoDictionaryKey: "PROFILE_IMAGE_UPLOAD_CLIENT_TOKEN") as? String
  }
}
