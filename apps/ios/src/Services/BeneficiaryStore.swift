import Foundation
import Security

struct Beneficiary: Codable, Identifiable, Equatable, Sendable {
  let id: UUID
  var name: String
  var address: String
  var chainLabel: String?

  init(id: UUID = UUID(), name: String, address: String, chainLabel: String? = nil) {
    self.id = id
    self.name = name
    self.address = address
    self.chainLabel = chainLabel
  }
}

enum BeneficiaryStoreError: Error {
  case keychain(OSStatus)
  case decodingFailed
}

extension BeneficiaryStoreError: LocalizedError {
  var errorDescription: String? {
    switch self {
    case .keychain(let status):
      if let message = SecCopyErrorMessageString(status, nil) as String? {
        return "Keychain failed (\(status)): \(message)"
      }
      return "Keychain failed with status \(status)."
    case .decodingFailed:
      return "Stored beneficiaries data could not be decoded."
    }
  }
}

actor BeneficiaryStore {
  private let service: String
  private let accountPrefix = "beneficiaries.v1"

  init(service: String = "com.peteranyaogu.metu") {
    self.service = service
  }

  func list(eoaAddress: String) throws -> [Beneficiary] {
    do {
      let data = try readData(eoaAddress: eoaAddress)
      return try JSONDecoder().decode([Beneficiary].self, from: data)
    } catch BeneficiaryStoreError.keychain(let status) where status == errSecItemNotFound {
      return []
    } catch is DecodingError {
      throw BeneficiaryStoreError.decodingFailed
    }
  }

  func upsert(_ beneficiary: Beneficiary, for eoaAddress: String) throws {
    var all = try list(eoaAddress: eoaAddress)
    if let index = all.firstIndex(where: { $0.id == beneficiary.id }) {
      all[index] = beneficiary
    } else {
      all.append(beneficiary)
    }
    try save(all, eoaAddress: eoaAddress)
  }

  func delete(id: UUID, for eoaAddress: String) throws {
    let filtered = try list(eoaAddress: eoaAddress).filter { $0.id != id }
    try save(filtered, eoaAddress: eoaAddress)
  }

  private func save(_ beneficiaries: [Beneficiary], eoaAddress: String) throws {
    let payload = try JSONEncoder().encode(beneficiaries)
    let account = accountName(for: eoaAddress)

    var query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
    ]

    let update: [String: Any] = [kSecValueData as String: payload]
    let updateStatus = SecItemUpdate(query as CFDictionary, update as CFDictionary)

    if updateStatus == errSecSuccess { return }

    if updateStatus == errSecItemNotFound {
      query[kSecValueData as String] = payload
      query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
      let addStatus = SecItemAdd(query as CFDictionary, nil)
      guard addStatus == errSecSuccess else {
        throw BeneficiaryStoreError.keychain(addStatus)
      }
      return
    }

    throw BeneficiaryStoreError.keychain(updateStatus)
  }

  private func readData(eoaAddress: String) throws -> Data {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: accountName(for: eoaAddress),
      kSecReturnData as String: true,
      kSecMatchLimit as String: kSecMatchLimitOne,
    ]

    var result: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &result)
    guard status == errSecSuccess else {
      throw BeneficiaryStoreError.keychain(status)
    }
    guard let data = result as? Data else {
      throw BeneficiaryStoreError.decodingFailed
    }
    return data
  }

  private func accountName(for eoaAddress: String) -> String {
    let normalized = eoaAddress.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    return "\(accountPrefix).\(normalized)"
  }
}
