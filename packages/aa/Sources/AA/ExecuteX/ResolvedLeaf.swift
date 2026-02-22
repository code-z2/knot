import Foundation
import RPC
import Transactions

struct ExecuteXResolvedLeaf {
    let execute: ExecuteXResolvedExecuteLeaf?
    let accumulator: ExecuteXResolvedAccumulatorLeaf?

    init(execute: ExecuteXResolvedExecuteLeaf) {
        self.execute = execute
        accumulator = nil
    }

    init(accumulator: ExecuteXResolvedAccumulatorLeaf) {
        execute = nil
        self.accumulator = accumulator
    }

    var leafHash: Data {
        if let execute {
            return execute.leafHash
        }
        if let accumulator {
            return accumulator.leafHash
        }
        preconditionFailure("Resolved leaf must have either execute or accumulator payload.")
    }
}

struct ExecuteXResolvedExecuteLeaf {
    let chainId: UInt64
    let mode: ExecuteXSubmissionMode
    let calls: [Call]
    let didAppendInitializeCall: Bool
    let authorizationRequired: Bool
    let authorization: RelayAuthorizationModel?
    let structHash: Data
    let leafHash: Data
}

struct ExecuteXResolvedAccumulatorLeaf {
    let chainId: UInt64
    let mode: ExecuteXSubmissionMode
    let intent: AccumulatorExecutionIntent
    let structHash: Data
    let leafHash: Data
}
