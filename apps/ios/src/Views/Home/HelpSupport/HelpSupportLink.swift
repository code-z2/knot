import Foundation

enum HelpSupportLink {
    static let emailAddress = "hello@knot.fi"

    static let phoneNumber = "+1-713 (435) 2334"

    static let supportURL = URL(string: "https://knot.fi/support")!

    static let privacyURL = URL(string: "https://knot.fi/privacy")!

    static let termsURL = URL(string: "https://knot.fi/terms")!

    static let availabilityURL = URL(string: "https://docs.knot.fi/jurisdictions")!

    static let communityURL = URL(string: "https://x.com/knotdotfi")!

    static var mailURL: URL? {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = emailAddress
        return components.url
    }
}
