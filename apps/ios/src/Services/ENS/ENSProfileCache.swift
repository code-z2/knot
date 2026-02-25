import Foundation

struct CachedENSProfileModel: Codable {
    let name: String
    let avatarURL: String
    let bio: String
    let updatedAt: Date
}

final class ENSProfileCache {
    private let defaults: UserDefaults
    private let storageKey = "ens.profile.cache.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load(for eoaAddress: String) -> CachedENSProfileModel? {
        guard
            let all = loadAll(),
            let profile = all[eoaAddress.lowercased()]
        else { return nil }
        return profile
    }

    func save(_ profile: CachedENSProfileModel, for eoaAddress: String) {
        var all = loadAll() ?? [:]
        all[eoaAddress.lowercased()] = profile
        persist(all)
    }

    func clear(for eoaAddress: String) {
        guard var all = loadAll() else { return }
        all.removeValue(forKey: eoaAddress.lowercased())
        persist(all)
    }

    private func loadAll() -> [String: CachedENSProfileModel]? {
        guard let data = defaults.data(forKey: storageKey) else { return [:] }
        return try? JSONDecoder().decode([String: CachedENSProfileModel].self, from: data)
    }

    private func persist(_ all: [String: CachedENSProfileModel]) {
        if all.isEmpty {
            defaults.removeObject(forKey: storageKey)
            return
        }
        if let data = try? JSONEncoder().encode(all) {
            defaults.set(data, forKey: storageKey)
        }
    }
}
