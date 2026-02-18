import Foundation

enum DecimalTruncation {
    static func truncate(_ value: Decimal, fractionDigits: Int) -> Decimal {
        var source = value
        var result = Decimal()
        if source >= 0 {
            NSDecimalRound(&result, &source, fractionDigits, .down)
        } else {
            NSDecimalRound(&result, &source, fractionDigits, .up)
        }
        return result
    }
}
