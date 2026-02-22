import AA
import Foundation
import Keychain
import Passkey
import Security
import SignHandler

public struct AccountProvisioningResult: Equatable, Sendable {
    public let eoaAddress: String
    public let accumulatorAddress: String
    public let passkey: PasskeyPublicKeyModel

    public init(
        eoaAddress: String,
        accumulatorAddress: String,
        passkey: PasskeyPublicKeyModel,
    ) {
        self.eoaAddress = eoaAddress
        self.accumulatorAddress = accumulatorAddress
        self.passkey = passkey
    }
}

public struct AccountSession: Equatable, Sendable {
    public let eoaAddress: String
    public let accumulatorAddress: String
    public let passkeyCredentialID: Data

    public init(eoaAddress: String, accumulatorAddress: String, passkeyCredentialID: Data) {
        self.eoaAddress = eoaAddress
        self.accumulatorAddress = accumulatorAddress
        self.passkeyCredentialID = passkeyCredentialID
    }
}

public protocol WalletMaterialStoring {
    func save(_ wallet: WalletMaterialModel, for eoaAddress: String) throws
    func read(for eoaAddress: String) throws -> WalletMaterialModel
}

public actor AccountSetupService {
    private enum KeychainAccount {
        static let accounts = "accounts.v2"
    }

    private struct StoredAccountRecord: Codable, Equatable, Sendable {
        let eoaAddress: String
        let passkey: PasskeyPublicKeyModel
        let accumulatorAddress: String?
    }

    private let walletFactory: WalletMaterialFactory
    private let passkeyService: PasskeyServiceProviding
    private let keychain: KeychainStoreProviding
    private let walletStore: WalletMaterialStoring
    private let smartAccountClient: SmartAccountClient
    private let keychainService: String
    private let relyingParty: PasskeyRelyingPartyModel

    public init(
        walletFactory: WalletMaterialFactory = .init(),
        passkeyService: PasskeyServiceProviding,
        keychain: KeychainStoreProviding = KeychainStoreService(),
        walletStore: WalletMaterialStoring = KeychainWalletMaterialStore(),
        smartAccountClient: SmartAccountClient = .init(),
        keychainService: String = "fi.knot.keychain",
        relyingParty: PasskeyRelyingPartyModel = .init(rpID: "knot.fi", rpName: "Knot"),
    ) {
        self.walletFactory = walletFactory
        self.passkeyService = passkeyService
        self.keychain = keychain
        self.walletStore = walletStore
        self.smartAccountClient = smartAccountClient
        self.keychainService = keychainService
        self.relyingParty = relyingParty
    }

    public func provisionAccount(
        delegateAddress: String,
        chainId: UInt64 = 1,
        nonce: UInt64 = 0,
    ) async throws -> AccountProvisioningResult {
        let wallet: WalletMaterialModel
        do {
            wallet = try walletFactory.createNewEOA()
        } catch {
            throw AccountSetupError.walletGenerationFailed(error)
        }
        return try await provisionAccount(
            wallet: wallet,
            delegateAddress: delegateAddress,
            chainId: chainId,
            nonce: nonce,
        )
    }

    private func provisionAccount(
        wallet: WalletMaterialModel,
        delegateAddress: String,
        chainId: UInt64,
        nonce: UInt64,
    ) async throws -> AccountProvisioningResult {
        _ = delegateAddress
        _ = nonce
        let userID = Data(UUID().uuidString.utf8)

        let passkey: PasskeyPublicKeyModel
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

        let accumulatorAddress: String
        do {
            accumulatorAddress = try await deriveAccumulatorAddress(
                eoaAddress: wallet.eoaAddress,
                chainId: chainId,
            )
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
                    eoaAddress: wallet.eoaAddress,
                    passkey: passkey,
                    accumulatorAddress: accumulatorAddress,
                ),
            )
            try persistStoredAccountRecords(accounts)
        } catch {
            throw AccountSetupError.authorizationStorageFailed(error)
        }

        return AccountProvisioningResult(
            eoaAddress: wallet.eoaAddress,
            accumulatorAddress: accumulatorAddress,
            passkey: passkey,
        )
    }

    public func authenticateAccount() async throws -> AccountSession {
        let listStoredAccounts = try loadStoredAccountRecords()
        guard !listStoredAccounts.isEmpty else {
            throw AccountSetupError.missingStoredPasskey
        }
        let allowedCredentialIDs = listStoredAccounts.map(\.passkey.credentialID)

        let signature: PasskeySignatureModel

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
            let matched = listStoredAccounts.first(where: {
                $0.passkey.credentialID == signature.credentialID
            })
        else {
            throw AccountSetupError.missingStoredPasskey
        }

        let eoaAddress = normalizedAddressKey(matched.eoaAddress)
        guard !eoaAddress.isEmpty else {
            throw AccountSetupError.missingStoredAccount(matched.eoaAddress)
        }
        guard
            let accumulatorAddress = matched.accumulatorAddress?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased(),
            !accumulatorAddress.isEmpty
        else {
            throw AccountSetupError.missingStoredAccumulator(eoaAddress)
        }

        return AccountSession(
            eoaAddress: eoaAddress,
            accumulatorAddress: accumulatorAddress,
            passkeyCredentialID: matched.passkey.credentialID,
        )
    }

    public func storedWalletMaterial(eoaAddress: String) throws -> WalletMaterialModel {
        try walletStore.read(for: eoaAddress)
    }

    public func listStoredAccounts() async throws -> [AccountSession] {
        let records = try loadStoredAccountRecords()
        return try records.map { record in
            let eoaAddress = normalizedAddressKey(record.eoaAddress)
            guard !eoaAddress.isEmpty else {
                throw AccountSetupError.missingStoredAccount(record.eoaAddress)
            }
            guard
                let accumulatorAddress = record.accumulatorAddress?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased(),
                !accumulatorAddress.isEmpty
            else {
                throw AccountSetupError.missingStoredAccumulator(eoaAddress)
            }

            return AccountSession(
                eoaAddress: eoaAddress,
                accumulatorAddress: accumulatorAddress,
                passkeyCredentialID: record.passkey.credentialID,
            )
        }
    }

    public func restoreAccount(eoaAddress: String) async throws -> AccountSession {
        let normalized = normalizedAddressKey(eoaAddress)
        let records = try loadStoredAccountRecords()

        for record in records {
            let recordAddress = normalizedAddressKey(record.eoaAddress)
            if recordAddress == normalized {
                guard
                    let accumulatorAddress = record.accumulatorAddress?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .lowercased(),
                    !accumulatorAddress.isEmpty
                else {
                    throw AccountSetupError.missingStoredAccumulator(recordAddress)
                }

                return AccountSession(
                    eoaAddress: recordAddress,
                    accumulatorAddress: accumulatorAddress,
                    passkeyCredentialID: record.passkey.credentialID,
                )
            }
        }

        throw AccountSetupError.missingStoredAccount(eoaAddress)
    }

    public func signWithStoredPasskey(
        account: AccountSession,
        payload: Data,
    ) async throws -> Data {
        let passkey = try passkeyPublicKey(for: account)
        let signature: PasskeySignatureModel
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

    public func verifyStoredPasskey(
        account: AccountSession,
        action: String,
    ) async throws {
        let passkey = try passkeyPublicKey(for: account)
        var payload = Data("knot:\(action):\(normalizedAddressKey(account.eoaAddress)):".utf8)
        payload.append(randomChallenge(length: 32))

        let signature: PasskeySignatureModel
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
    public func signEthDigestWithStoredWallet(
        account: AccountSession,
        digest32: Data,
    ) throws -> Data {
        let wallet = try walletStore.read(for: account.eoaAddress)
        let ethSignedDigest = try ECDSASignatureCodec.toEthSignedMessageHash(digest32)
        return try ECDSASignatureCodec.signDigest(ethSignedDigest, privateKeyHex: wallet.privateKeyHex)
    }

    public func passkeyPublicKey(for account: AccountSession) throws -> PasskeyPublicKeyModel {
        let records = try loadStoredAccountRecords()
        if let matched = records.first(where: { $0.passkey.credentialID == account.passkeyCredentialID }) {
            return matched.passkey
        }
        throw AccountSetupError.missingStoredAccount(account.eoaAddress)
    }

    public func signedAuthorizationForChain(
        account: AccountSession,
        chainId: UInt64,
        delegateAddress: String,
        nonce: UInt64 = 0,
    ) throws -> EIP7702AuthorizationSignedModel {
        let records = try loadStoredAccountRecords()
        guard records.contains(where: { $0.passkey.credentialID == account.passkeyCredentialID }) else {
            throw AccountSetupError.missingStoredAccount(account.eoaAddress)
        }

        // JIT Signing
        let wallet = try walletStore.read(for: account.eoaAddress)
        let unsigned = EIP7702AuthorizationUnsignedModel(
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
        } catch KeychainStoreError.invalidData {
            throw AccountSetupError.authorizationDecodeFailed(KeychainStoreError.invalidData)
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
            normalizedAddressKey(existing.eoaAddress) == normalizedAddressKey(record.eoaAddress)
        }) {
            records[addressIndex] = record
            return
        }
        records.append(record)
    }

    private func normalizedAddressKey(_ eoaAddress: String) -> String {
        eoaAddress.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func deriveAccumulatorAddress(eoaAddress: String, chainId: UInt64) async throws -> String {
        try await smartAccountClient.computeAccumulatorAddress(account: eoaAddress, chainId: chainId)
    }
}
