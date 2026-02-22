import Foundation

public enum ExecuteXLeafPlanContent: Sendable, Equatable {
    case execute(PlannedExecuteXCall)

    case accumulator(PlannedAccumulatorExecution)
}
