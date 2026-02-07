import Foundation
import ENS
import Transactions

enum ENSServiceError: Error {
  case actionFailed(Error)
}

struct ENSNameQuote {
  let normalizedName: String
  let available: Bool
  let rentPriceWei: String
}

struct ENSRecordDraft {
  let key: String
  let value: String
}

struct ENSRegistrationPayloads {
  let commitCall: Call
  let registerCall: Call
  let minCommitmentAgeSeconds: UInt64

  var calls: [Call] {
    [commitCall, registerCall]
  }
}

extension ENSServiceError: LocalizedError {
  var errorDescription: String? {
    switch self {
    case .actionFailed(let error):
      return "ENS action failed: \(error.localizedDescription)"
    }
  }
}

@MainActor
final class ENSService {
  private let client: ENSClient
  let configuration: ENSConfiguration

  var chainID: UInt64 {
    configuration.chainID
  }

  init(
    configuration: ENSConfiguration = .sepolia,
    client: ENSClient? = nil
  ) {
    self.configuration = configuration
    self.client = client ?? ENSClient(configuration: configuration)
  }

  func resolveName(name: String) async throws -> String {
    do {
      return try await client.resolveName(
        ResolveNameRequest(name: name)
      )
    } catch {
      throw ENSServiceError.actionFailed(error)
    }
  }

  func reverseAddress(address: String) async throws -> String {
    do {
      return try await client.reverseAddress(
        ReverseAddressRequest(address: address)
      )
    } catch {
      throw ENSServiceError.actionFailed(error)
    }
  }

  func registerNamePayloads(
    name: String,
    ownerAddress: String,
    initialRecords: [ENSRecordDraft] = [],
    duration: UInt = 31_536_000
  ) async throws -> ENSRegistrationPayloads {
    do {
      let result = try await client.registerName(
        RegisterNameRequest(
          name: name,
          ownerAddress: ownerAddress,
          duration: duration,
          initialTextRecords: initialRecords.map { InitialTextRecord(key: $0.key, value: $0.value) }
        )
      )
      return ENSRegistrationPayloads(
        commitCall: result.commitCall,
        registerCall: result.registerCall,
        minCommitmentAgeSeconds: result.minCommitmentAgeSeconds
      )
    } catch {
      throw ENSServiceError.actionFailed(error)
    }
  }

  func quoteName(
    name: String,
    duration: UInt = 31_536_000
  ) async throws -> ENSNameQuote {
    do {
      let quote = try await client.quoteRegistration(
        RegisterNameRequest(
          name: name,
          ownerAddress: "0x0000000000000000000000000000000000000000",
          duration: duration
        )
      )
      return ENSNameQuote(
        normalizedName: quote.normalizedName,
        available: quote.available,
        rentPriceWei: quote.rentPriceWei
      )
    } catch {
      throw ENSServiceError.actionFailed(error)
    }
  }

  func addRecordPayload(
    name: String,
    key: String,
    value: String
  ) async throws -> Call {
    do {
      return try await client.addRecord(
        AddRecordRequest(
          name: name,
          recordKey: key,
          recordValue: value
        )
      )
    } catch {
      throw ENSServiceError.actionFailed(error)
    }
  }

  func updateRecordPayload(
    name: String,
    key: String,
    value: String
  ) async throws -> Call {
    do {
      return try await client.updateRecord(
        UpdateRecordRequest(
          name: name,
          recordKey: key,
          recordValue: value
        )
      )
    } catch {
      throw ENSServiceError.actionFailed(error)
    }
  }

  func textRecord(
    name: String,
    key: String
  ) async throws -> String {
    do {
      return try await client.textRecord(
        TextRecordRequest(name: name, recordKey: key)
      )
    } catch {
      throw ENSServiceError.actionFailed(error)
    }
  }
}
