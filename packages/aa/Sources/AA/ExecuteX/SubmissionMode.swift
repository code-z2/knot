import Foundation

public enum ExecuteXSubmissionMode: String, Sendable, Codable {
    case immediate

    case background

    case deferred
}
