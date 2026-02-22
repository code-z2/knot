import Foundation
import Transactions

public enum ExecuteXLeafRequestPayload: Sendable, Equatable {
    case executeCalls([Call])

    case accumulatorIntent(AccumulatorExecutionIntent)
}
