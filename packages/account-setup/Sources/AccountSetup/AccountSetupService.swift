import AA
import Foundation
import Keychain
import Passkey
import Security
import SignHandler

public struct CreatedAccount: Equatable, Sendable {
    public let eoaAddress: String
    public let accumulatorAddress: String
    public let passkey: PasskeyPublicKey
    public let signedAuthorization: EIP7702AuthorizationSigned

    public init(
        eoaAddress: String,
        accumulatorAddress: String,
        passkey: PasskeyPublicKey,
        signedAuthorization: EIP7702AuthorizationSigned,
    ) {
        self.eoaAddress = eoaAddress
        self.accumulatorAddress = accumulatorAddress
        self.passkey = passkey
        self.signedAuthorization = signedAuthorization
    }
}

public struct AccountIdentity: Equatable, Sendable {
    public let eoaAddress: String
    public let accumulatorAddress: String
    public let passkeyCredentialID: Data

    public init(eoaAddress: String, accumulatorAddress: String, passkeyCredentialID: Data) {
        self.eoaAddress = eoaAddress
        self.accumulatorAddress = accumulatorAddress
        self.passkeyCredentialID = passkeyCredentialID
    }
}

public enum AccountSetupError: Error {
    case missingStoredPasskey
    case walletGenerationFailed(Error)
    case passkeyRegistrationFailed(Error)
    case authorizationSigningFailed(Error)
    case walletStorageFailed(Error)
    case authorizationStorageFailed(Error)
    case passkeyAssertionFailed(Error)
    case authorizationRecoveryFailed(Error)
    case authorizationDecodeFailed(Error)
    case accumulatorDerivationFailed(Error)
    case missingStoredAccount(String)
}

extension AccountSetupError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .missingStoredPasskey:
            "No stored passkey public data found."
        case let .walletGenerationFailed(error):
            "Failed to generate wallet material: \(error.localizedDescription)"
        case let .passkeyRegistrationFailed(error):
            "Passkey registration failed: \(error.localizedDescription)"
        case let .authorizationSigningFailed(error):
            "Failed to sign EIP-7702 authorization: \(error.localizedDescription)"
        case let .walletStorageFailed(error):
            "Failed to persist wallet material locally: \(error.localizedDescription)"
        case let .authorizationStorageFailed(error):
            "Failed to save signed authorization: \(error.localizedDescription)"
        case let .passkeyAssertionFailed(error):
            "Passkey assertion failed during sign-in: \(error.localizedDescription)"
        case let .authorizationRecoveryFailed(error):
            "Failed to recover signer from signed authorization: \(error.localizedDescription)"
        case let .authorizationDecodeFailed(error):
            "Stored authorization data could not be decoded: \(error.localizedDescription)"
        case let .accumulatorDerivationFailed(error):
            "Failed to derive accumulator address: \(error.localizedDescription)"
        case let .missingStoredAccount(eoaAddress):
            "No stored account found for EOA \(eoaAddress)."
        }
    }
}

public protocol WalletMaterialStoring {
    func save(_ wallet: WalletMaterial, for eoaAddress: String) throws
    func read(for eoaAddress: String) throws -> WalletMaterial
    func readAll() throws -> [String: WalletMaterial]
}

public struct LocalWalletMaterialStore: WalletMaterialStoring {
    private let fileURL: URL

    public init(filename: String = "wallet-materials.json") {
        let baseDirectory =
            FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? FileManager.default.temporaryDirectory
        fileURL = baseDirectory.appendingPathComponent(filename)
    }

    public func save(_ wallet: WalletMaterial, for eoaAddress: String) throws {
        let key = Self.normalizedAddressKey(eoaAddress)
        var all = (try? readAll()) ?? [:]
        all[key] = wallet
        let data = try JSONEncoder().encode(all)
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: nil,
        )
        try data.write(to: fileURL, options: .atomic)

        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = true
        var writableURL = fileURL
        try? writableURL.setResourceValues(resourceValues)
        try? FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.complete],
            ofItemAtPath: fileURL.path,
        )
    }

    public func read(for eoaAddress: String) throws -> WalletMaterial {
        let key = Self.normalizedAddressKey(eoaAddress)
        let all = try readAll()
        guard let wallet = all[key] else {
            throw CocoaError(.fileReadNoSuchFile)
        }
        return wallet
    }

    public func readAll() throws -> [String: WalletMaterial] {
        let data = try Data(contentsOf: fileURL)
        return try JSONDecoder().decode([String: WalletMaterial].self, from: data)
    }

    private static func normalizedAddressKey(_ eoaAddress: String) -> String {
        eoaAddress.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

public actor AccountSetupService {
    private enum KeychainAccount {
        static let accounts = "accounts.v1"
    }

    private struct StoredAccountRecord: Codable, Equatable, Sendable {
        let passkey: PasskeyPublicKey
        let signedAuthorization: EIP7702AuthorizationSigned
        let accumulatorAddress: String?
    }

    private let walletFactory: WalletMaterialFactory
    private let passkeyService: PasskeyServicing
    private let keychain: KeychainStoring
    private let walletStore: WalletMaterialStoring
    private let keychainService: String
    private let relyingParty: PasskeyRelyingParty

    public init(
        walletFactory: WalletMaterialFactory = .init(),
        passkeyService: PasskeyServicing,
        keychain: KeychainStoring = KeychainStore(),
        walletStore: WalletMaterialStoring = LocalWalletMaterialStore(),
        keychainService: String = "fi.knot.keychain",
        relyingParty: PasskeyRelyingParty = .init(rpID: "knot.fi", rpName: "Knot"),
    ) {
        self.walletFactory = walletFactory
        self.passkeyService = passkeyService
        self.keychain = keychain
        self.walletStore = walletStore
        self.keychainService = keychainService
        self.relyingParty = relyingParty
    }

    public func createEOAAndPasskey(
        delegateAddress: String,
        chainId: UInt64 = 1,
        nonce: UInt64 = 0,
    ) async throws -> CreatedAccount {
        let wallet: WalletMaterial
        do {
            wallet = try walletFactory.createNewEOA()
        } catch {
            throw AccountSetupError.walletGenerationFailed(error)
        }
        return try await createEOAAndPasskey(
            wallet: wallet,
            delegateAddress: delegateAddress,
            chainId: chainId,
            nonce: nonce,
        )
    }

    private func createEOAAndPasskey(
        wallet: WalletMaterial,
        delegateAddress: String,
        chainId: UInt64,
        nonce: UInt64,
    ) async throws -> CreatedAccount {
        let userID = Data(UUID().uuidString.utf8)

        let passkey: PasskeyPublicKey
        do {
            passkey = try await passkeyService.register(
                rpId: relyingParty.rpID,
                rpName: relyingParty.rpName,
                challenge: randomChallenge(),
                userName: wallet.eoaAddress,
                userID: userID,
            )
        } catch {
            throw AccountSetupError.passkeyRegistrationFailed(error)
        }

        let unsigned = EIP7702AuthorizationUnsigned(
            chainId: chainId,
            delegateAddress: delegateAddress,
            nonce: nonce,
        )
        let signedAuthorization: EIP7702AuthorizationSigned
        do {
            signedAuthorization = try EIP7702AuthorizationCodec.signAuthorization(
                unsigned,
                privateKeyHex: wallet.privateKeyHex,
            )
        } catch {
            throw AccountSetupError.authorizationSigningFailed(error)
        }

        let accumulatorAddress: String
        do {
            accumulatorAddress = try deriveAccumulatorAddress(eoaAddress: wallet.eoaAddress)
        } catch {
            throw AccountSetupError.accumulatorDerivationFailed(error)
        }

        do {
            try walletStore.save(wallet, for: wallet.eoaAddress)
        } catch {
            throw AccountSetupError.walletStorageFailed(error)
        }

        do {
            var accounts = try loadStoredAccountRecords()
            upsertStoredAccount(
                &accounts,
                record: StoredAccountRecord(
                    passkey: passkey,
                    signedAuthorization: signedAuthorization,
                    accumulatorAddress: accumulatorAddress,
                ),
            )
            try persistStoredAccountRecords(accounts)
        } catch {
            throw AccountSetupError.authorizationStorageFailed(error)
        }

        return CreatedAccount(
            eoaAddress: wallet.eoaAddress,
            accumulatorAddress: accumulatorAddress,
            passkey: passkey,
            signedAuthorization: signedAuthorization,
        )
    }

    public func signInWithPasskey() async throws -> AccountIdentity {
        let storedAccounts = try ensureAccumulatorAddresses(loadStoredAccountRecords())
        guard !storedAccounts.isEmpty else {
            throw AccountSetupError.missingStoredPasskey
        }
        let allowedCredentialIDs = storedAccounts.map(\.passkey.credentialID)

        let signature: PasskeySignature

        do {
            signature = try await passkeyService.sign(
                rpId: relyingParty.rpID,
                payload: randomChallenge(),
                allowedCredentialIDs: allowedCredentialIDs,
            )
        } catch {
            throw AccountSetupError.passkeyAssertionFailed(error)
        }

        guard
            let matched = storedAccounts.first(where: {
                $0.passkey.credentialID == signature.credentialID
            })
        else {
            throw AccountSetupError.missingStoredPasskey
        }

        let recoveredAddress: String
        do {
            recoveredAddress = try EIP7702AuthorizationCodec.recoverAuthorityAddress(
                matched.signedAuthorization,
            )
        } catch {
            throw AccountSetupError.authorizationRecoveryFailed(error)
        }
        let accumulatorAddress =
            if let storedAccumulator = matched.accumulatorAddress {
                storedAccumulator
            } else {
                try deriveAccumulatorAddress(eoaAddress: recoveredAddress)
            }

        return AccountIdentity(
            eoaAddress: recoveredAddress,
            accumulatorAddress: accumulatorAddress,
            passkeyCredentialID: matched.passkey.credentialID,
        )
    }

    public func storedWalletMaterial(eoaAddress: String) throws -> WalletMaterial {
        try walletStore.read(for: eoaAddress)
    }

    public func storedWalletMaterials() throws -> [String: WalletMaterial] {
        (try? walletStore.readAll()) ?? [:]
    }

    public func storedAccounts() throws -> [AccountIdentity] {
        try ensureAccumulatorAddresses(loadStoredAccountRecords()).map { record in
            let recoveredAddress: String
            do {
                recoveredAddress = try EIP7702AuthorizationCodec.recoverAuthorityAddress(
                    record.signedAuthorization,
                )
            } catch {
                throw AccountSetupError.authorizationRecoveryFailed(error)
            }
            let accumulatorAddress =
                if let storedAccumulator = record.accumulatorAddress {
                    storedAccumulator
                } else {
                    try deriveAccumulatorAddress(eoaAddress: recoveredAddress)
                }

            return AccountIdentity(
                eoaAddress: recoveredAddress,
                accumulatorAddress: accumulatorAddress,
                passkeyCredentialID: record.passkey.credentialID,
            )
        }
    }

    public func restoreStoredSession(eoaAddress: String) throws -> AccountIdentity {
        let normalized = normalizedAddressKey(eoaAddress)
        let records = try ensureAccumulatorAddresses(loadStoredAccountRecords())

        for record in records {
            let recoveredAddress: String
            do {
                recoveredAddress = try EIP7702AuthorizationCodec.recoverAuthorityAddress(
                    record.signedAuthorization,
                )
            } catch {
                throw AccountSetupError.authorizationRecoveryFailed(error)
            }

            if normalizedAddressKey(recoveredAddress) == normalized {
                let accumulatorAddress =
                    if let storedAccumulator = record.accumulatorAddress {
                        storedAccumulator
                    } else {
                        try deriveAccumulatorAddress(eoaAddress: recoveredAddress)
                    }

                return AccountIdentity(
                    eoaAddress: recoveredAddress,
                    accumulatorAddress: accumulatorAddress,
                    passkeyCredentialID: record.passkey.credentialID,
                )
            }
        }

        throw AccountSetupError.missingStoredAccount(eoaAddress)
    }

    public func signPayloadWithStoredPasskey(
        account: AccountIdentity,
        payload: Data,
    ) async throws -> Data {
        let passkey = try passkeyPublicKey(account: account)
        let signature: PasskeySignature
        do {
            signature = try await passkeyService.sign(
                rpId: relyingParty.rpID,
                payload: payload,
                allowedCredentialIDs: [passkey.credentialID],
            )
        } catch {
            throw AccountSetupError.passkeyAssertionFailed(error)
        }

        do {
            return try signature.webAuthnAuthBytes(payload: payload)
        } catch {
            throw AccountSetupError.passkeyAssertionFailed(error)
        }
    }

    public func verifyStoredPasskeyForSensitiveAction(
        account: AccountIdentity,
        action: String,
    ) async throws {
        let passkey = try passkeyPublicKey(account: account)
        var payload = Data("knot:\(action):\(normalizedAddressKey(account.eoaAddress)):".utf8)
        payload.append(randomChallenge(length: 32))

        let signature: PasskeySignature
        do {
            signature = try await passkeyService.sign(
                rpId: relyingParty.rpID,
                payload: payload,
                allowedCredentialIDs: [passkey.credentialID],
            )
        } catch {
            throw AccountSetupError.passkeyAssertionFailed(error)
        }

        do {
            try PasskeyAssertionVerifier.verify(
                signature: signature,
                payload: payload,
                expectedPasskey: passkey,
                rpId: relyingParty.rpID,
            )
        } catch {
            throw AccountSetupError.passkeyAssertionFailed(error)
        }
    }

    /// Signs a 32-byte digest using the stored EOA private key as an Ethereum signed message.
    /// Signature format is 65-byte recoverable `[r || s || v]` with `v` in 27/28 domain.
    public func signEthMessageDigestWithStoredWallet(
        account: AccountIdentity,
        digest32: Data,
    ) throws -> Data {
        let wallet = try walletStore.read(for: account.eoaAddress)
        let ethSignedDigest = try ECDSASignatureCodec.toEthSignedMessageHash(digest32)
        return try ECDSASignatureCodec.signDigest(ethSignedDigest, privateKeyHex: wallet.privateKeyHex)
    }

    public func passkeyPublicKey(account: AccountIdentity) throws -> PasskeyPublicKey {
        let records = try loadStoredAccountRecords()
        if let matched = records.first(where: { $0.passkey.credentialID == account.passkeyCredentialID }) {
            return matched.passkey
        }
        throw AccountSetupError.missingStoredAccount(account.eoaAddress)
    }

    public func signedAuthorization(
        account: AccountIdentity,
        chainId: UInt64,
        delegateAddress: String,
        nonce: UInt64 = 0,
    ) throws -> EIP7702AuthorizationSigned {
        let records = try loadStoredAccountRecords()
        guard
            let matched = records.first(where: {
                $0.passkey.credentialID == account.passkeyCredentialID
            })
        else {
            throw AccountSetupError.missingStoredAccount(account.eoaAddress)
        }

        if matched.signedAuthorization.chainId == chainId {
            return matched.signedAuthorization
        }

        // JIT Signing
        let wallet = try walletStore.read(for: account.eoaAddress)
        let unsigned = EIP7702AuthorizationUnsigned(
            chainId: chainId,
            delegateAddress: delegateAddress,
            nonce: nonce,
        )
        return try EIP7702AuthorizationCodec.signAuthorization(
            unsigned,
            privateKeyHex: wallet.privateKeyHex,
        )
    }

    private func randomChallenge(length: Int = 32) -> Data {
        var bytes = [UInt8](repeating: 0, count: length)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes)
    }

    private func loadStoredAccountRecords() throws -> [StoredAccountRecord] {
        do {
            let data = try keychain.read(account: KeychainAccount.accounts, service: keychainService)
            return try JSONDecoder().decode([StoredAccountRecord].self, from: data)
        } catch KeychainStoreError.dataNotFound {
            return []
        } catch let decodingError as DecodingError {
            throw AccountSetupError.authorizationDecodeFailed(decodingError)
        } catch {
            throw error
        }
    }

    private func persistStoredAccountRecords(_ records: [StoredAccountRecord]) throws {
        try keychain.save(
            JSONEncoder().encode(records),
            account: KeychainAccount.accounts,
            service: keychainService,
        )
    }

    private func upsertStoredAccount(
        _ records: inout [StoredAccountRecord],
        record: StoredAccountRecord,
    ) {
        if let credentialIndex = records.firstIndex(where: {
            $0.passkey.credentialID == record.passkey.credentialID
        }) {
            records[credentialIndex] = record
            return
        }
        if let addressIndex = records.firstIndex(where: { existing in
            let lhs = try? EIP7702AuthorizationCodec.recoverAuthorityAddress(existing.signedAuthorization)
            let rhs = try? EIP7702AuthorizationCodec.recoverAuthorityAddress(record.signedAuthorization)
            guard let lhs, let rhs else { return false }
            return normalizedAddressKey(lhs) == normalizedAddressKey(rhs)
        }) {
            records[addressIndex] = record
            return
        }
        records.append(record)
    }

    private func normalizedAddressKey(_ eoaAddress: String) -> String {
        eoaAddress.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func deriveAccumulatorAddress(eoaAddress: String) throws -> String {
        try SmartAccount.AccumulatorFactory.deriveAddress(userAccount: eoaAddress).lowercased()
    }

    private func ensureAccumulatorAddresses(_ records: [StoredAccountRecord]) throws
        -> [StoredAccountRecord]
    {
        var updatedRecords: [StoredAccountRecord] = []
        updatedRecords.reserveCapacity(records.count)
        var hasChanges = false

        for record in records {
            let rawStored = record.accumulatorAddress
            let normalizedStored = rawStored?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()

            if let normalizedStored, !normalizedStored.isEmpty {
                if rawStored != .some(normalizedStored) {
                    hasChanges = true
                }
                updatedRecords.append(
                    StoredAccountRecord(
                        passkey: record.passkey,
                        signedAuthorization: record.signedAuthorization,
                        accumulatorAddress: normalizedStored,
                    ),
                )
                continue
            }

            let recoveredAddress: String
            do {
                recoveredAddress = try EIP7702AuthorizationCodec.recoverAuthorityAddress(
                    record.signedAuthorization,
                )
            } catch {
                throw AccountSetupError.authorizationRecoveryFailed(error)
            }
            let derivedAddress = try deriveAccumulatorAddress(eoaAddress: recoveredAddress)
            hasChanges = true
            updatedRecords.append(
                StoredAccountRecord(
                    passkey: record.passkey,
                    signedAuthorization: record.signedAuthorization,
                    accumulatorAddress: derivedAddress,
                ),
            )
        }

        if hasChanges {
            try persistStoredAccountRecords(updatedRecords)
        }

        return updatedRecords
    }
}
