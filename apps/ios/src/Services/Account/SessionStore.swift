import Foundation

final class SessionStore {
    private enum Key {
        static let activeEOAAddress = "session.active.eoa"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var activeEOAAddress: String? {
        defaults.string(forKey: Key.activeEOAAddress)
    }

    func setActiveSession(eoaAddress: String) {
        defaults.set(eoaAddress, forKey: Key.activeEOAAddress)
    }

    func clearActiveSession() {
        defaults.removeObject(forKey: Key.activeEOAAddress)
    }
}
