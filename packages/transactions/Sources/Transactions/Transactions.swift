import Foundation

public struct Call: Sendable, Codable, Equatable {
    public let to: String
    public let dataHex: String
    public let valueWei: String

    public init(to: String, dataHex: String, valueWei: String = "0") {
        self.to = to
        self.dataHex = dataHex
        self.valueWei = valueWei
    }
}
