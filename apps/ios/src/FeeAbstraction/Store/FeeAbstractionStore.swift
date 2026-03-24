import Foundation
import Observation
import RPC

@MainActor
@Observable
final class FeeAbstractionStore {
    private enum Key {
        static let snapshotPrefix = "feeAbstraction.snapshot"
    }

    @ObservationIgnored
    private let defaults: UserDefaults

    @ObservationIgnored
    private var currentSnapshotKey: String?

    private(set) var payAsYouGoEnabled = false
    private(set) var overdraftEnabled = false
    private(set) var balanceNative: String?
    private(set) var initialized = false
    private(set) var minimumAllowedNative: String?
    private(set) var requiredTopUpNative: String?
    private(set) var suggestedTopUpNative: String?
    private(set) var lastUpdatedAt: Date?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var isOverdraftEligible: Bool {
        currentSnapshot.isOverdraftEligible
    }

    var hasKnownBalance: Bool {
        balanceNative != nil
    }

    func load(
        eoaAddress: String,
        mode: ChainSupportMode,
    ) {
        let snapshotKey = makeSnapshotKey(
            eoaAddress: eoaAddress,
            mode: mode,
        )
        currentSnapshotKey = snapshotKey

        guard
            let data = defaults.data(forKey: snapshotKey),
            let snapshot = try? JSONDecoder().decode(FeeAbstractionSnapshotModel.self, from: data)
        else {
            resetState()
            return
        }

        apply(snapshot)
    }

    func setPayAsYouGoEnabled(_ value: Bool) {
        payAsYouGoEnabled = value
        persistCurrentSnapshot()
    }

    func setOverdraftEnabled(_ value: Bool) {
        guard isOverdraftEligible else {
            overdraftEnabled = false
            persistCurrentSnapshot()
            return
        }

        overdraftEnabled = value
        persistCurrentSnapshot()
    }

    func updateCredit(
        balanceNative: String,
        initialized: Bool,
    ) {
        self.balanceNative = balanceNative
        self.initialized = initialized
        lastUpdatedAt = Date()
        persistCurrentSnapshot()
    }

    func capturePaymentRequired(_ payload: RelayPaymentRequiredModel) {
        minimumAllowedNative = payload.minimumAllowedNative
        requiredTopUpNative = payload.requiredTopUpNative
        suggestedTopUpNative = payload.suggestedTopUpNative

        if !isOverdraftEligible {
            overdraftEnabled = false
        }

        lastUpdatedAt = Date()
        persistCurrentSnapshot()
    }

    private var currentSnapshot: FeeAbstractionSnapshotModel {
        FeeAbstractionSnapshotModel(
            payAsYouGoEnabled: payAsYouGoEnabled,
            overdraftEnabled: overdraftEnabled,
            balanceNative: balanceNative,
            initialized: initialized,
            minimumAllowedNative: minimumAllowedNative,
            requiredTopUpNative: requiredTopUpNative,
            suggestedTopUpNative: suggestedTopUpNative,
            lastUpdatedAt: lastUpdatedAt,
        )
    }

    private func apply(_ snapshot: FeeAbstractionSnapshotModel) {
        payAsYouGoEnabled = snapshot.payAsYouGoEnabled
        overdraftEnabled = snapshot.overdraftEnabled && snapshot.isOverdraftEligible
        balanceNative = snapshot.balanceNative
        initialized = snapshot.initialized
        minimumAllowedNative = snapshot.minimumAllowedNative
        requiredTopUpNative = snapshot.requiredTopUpNative
        suggestedTopUpNative = snapshot.suggestedTopUpNative
        lastUpdatedAt = snapshot.lastUpdatedAt
    }

    private func resetState() {
        payAsYouGoEnabled = false
        overdraftEnabled = false
        balanceNative = nil
        initialized = false
        minimumAllowedNative = nil
        requiredTopUpNative = nil
        suggestedTopUpNative = nil
        lastUpdatedAt = nil
    }

    private func persistCurrentSnapshot() {
        guard let currentSnapshotKey else { return }
        guard let data = try? JSONEncoder().encode(currentSnapshot) else { return }
        defaults.set(data, forKey: currentSnapshotKey)
    }

    private func makeSnapshotKey(
        eoaAddress: String,
        mode: ChainSupportMode,
    ) -> String {
        "\(Key.snapshotPrefix).\(mode.rawValue.lowercased()).\(eoaAddress.lowercased())"
    }
}
