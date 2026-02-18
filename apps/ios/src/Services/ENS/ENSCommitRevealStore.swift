import Foundation
import Transactions

struct PendingENSRevealJob: Codable {
    let eoaAddress: String
    let name: String
    let chainId: UInt64
    let submissionHash: String
    let minCommitmentAgeSeconds: UInt64
    let revealNotBeforeUnix: TimeInterval
    let postCommitCalls: [Call]
    let preparedPayloadCount: Int
}

final class ENSCommitRevealStore {
    private let defaults: UserDefaults
    private let storageKey = "ens.pending.reveal.jobs.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func loadJob(for eoaAddress: String) -> PendingENSRevealJob? {
        guard
            let all = loadAll(),
            let job = all[eoaAddress.lowercased()]
        else { return nil }
        return job
    }

    func saveJob(_ job: PendingENSRevealJob) {
        var all = loadAll() ?? [:]
        all[job.eoaAddress.lowercased()] = job
        persist(all)
    }

    func clearJob(for eoaAddress: String) {
        guard var all = loadAll() else { return }
        all.removeValue(forKey: eoaAddress.lowercased())
        persist(all)
    }

    private func loadAll() -> [String: PendingENSRevealJob]? {
        guard let data = defaults.data(forKey: storageKey) else { return [:] }
        return try? JSONDecoder().decode([String: PendingENSRevealJob].self, from: data)
    }

    private func persist(_ all: [String: PendingENSRevealJob]) {
        if all.isEmpty {
            defaults.removeObject(forKey: storageKey)
            return
        }
        if let data = try? JSONEncoder().encode(all) {
            defaults.set(data, forKey: storageKey)
        }
    }
}
