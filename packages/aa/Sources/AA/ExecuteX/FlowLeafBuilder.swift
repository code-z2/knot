import Foundation
import Transactions

struct ExecuteXFlowLeafBuilder {
    func buildLeafRequests(from request: ExecuteXFlowPlanRequest) -> [ExecuteXLeafRequest] {
        let mergedActions = mergeChainActions(request.chainActions)
        var leaves = mergedActions.map { action in
            ExecuteXLeafRequest(
                chainId: action.chainId,
                mode: action.chainId == request.destinationChainId ? .immediate : .background,
                payload: .executeCalls(action.calls),
            )
        }

        if let destinationAccumulatorIntent = request.destinationAccumulatorIntent {
            leaves.append(
                ExecuteXLeafRequest(
                    chainId: request.destinationChainId,
                    mode: request.destinationAccumulatorMode,
                    payload: .accumulatorIntent(destinationAccumulatorIntent),
                ),
            )
        }

        return leaves
    }

    private func mergeChainActions(_ chainActions: [ExecuteXChainAction]) -> [ExecuteXChainAction] {
        var groupedCallsByChain: [UInt64: [Call]] = [:]
        var chainOrder: [UInt64] = []

        for action in chainActions {
            if groupedCallsByChain[action.chainId] == nil {
                chainOrder.append(action.chainId)
            }
            groupedCallsByChain[action.chainId, default: []].append(contentsOf: action.calls)
        }

        return chainOrder.map { chainId in
            ExecuteXChainAction(chainId: chainId, calls: groupedCallsByChain[chainId] ?? [])
        }
    }
}
