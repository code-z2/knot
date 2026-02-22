import Balance
import Compose
import Foundation
import RPC

@MainActor
final class SendFlowService {
    private let routeComposer: RouteComposer
    private let aaExecutionService: AAExecutionService
    private let accountService: AccountSetupService

    init(
        routeComposer: RouteComposer? = nil,
        aaExecutionService: AAExecutionService? = nil,
        accountService: AccountSetupService? = nil,
    ) {
        self.routeComposer = routeComposer ?? RouteComposer()
        self.aaExecutionService = aaExecutionService ?? AAExecutionService()
        self.accountService = accountService ?? AccountSetupService()
    }

    func resolveRoute(
        eoaAddress: String,
        toAddress: String,
        sourceAsset: TokenBalanceModel,
        destinationChainId: UInt64,
        destinationToken: String,
        destinationTokenSymbol: String,
        destinationTokenDecimals: Int,
        amount: Decimal,
        accumulatorAddress: String,
    ) async throws -> TransferRouteModel {
        do {
            return try await routeComposer.getRoute(
                fromAddress: eoaAddress,
                toAddress: toAddress,
                sourceAsset: sourceAsset,
                destChainId: destinationChainId,
                destToken: destinationToken,
                destTokenSymbol: destinationTokenSymbol,
                destTokenDecimals: destinationTokenDecimals,
                amount: amount,
                accumulatorAddress: accumulatorAddress,
            )
        } catch let routeError as RouteError {
            throw SendFlowServiceError.routeResolutionFailed(routeError)
        } catch {
            throw SendFlowServiceError.unknown(error)
        }
    }

    func submitRoute(eoaAddress: String, route: TransferRouteModel) async throws -> SendExecutionResultModel {
        guard !route.chainActions.isEmpty else {
            throw SendFlowServiceError.invalidRoute(reason: "Route has no executable chain actions.")
        }

        do {
            let account = try await accountService.restoreSession(eoaAddress: eoaAddress)
            let result = try await aaExecutionService.executeChainActions(
                accountService: accountService,
                account: account,
                destinationChainId: route.destinationChainId,
                chainActions: route.chainActions,
            )

            return SendExecutionResultModel(
                destinationRelayTaskID: result.destinationSubmission.id,
                immediateRelayTaskIDs: result.immediateSubmissions.map(\.id),
                backgroundRelayTaskIDs: result.backgroundSubmissions.map(\.id),
                deferredRelayTaskIDs: result.deferredSubmissions.map(\.id),
            )
        } catch let error as AAExecutionServiceError {
            throw SendFlowServiceError.submissionFailed(error)
        } catch {
            throw SendFlowServiceError.unknown(error)
        }
    }

    func executeRoute(eoaAddress: String, route: TransferRouteModel) async throws -> String {
        let result = try await submitRoute(eoaAddress: eoaAddress, route: route)
        return result.destinationRelayTaskID
    }

    func deferredStatuses(for execution: SendExecutionResultModel) async throws -> [RelayStatusModel] {
        guard execution.hasDeferredRelayTasks else { return [] }

        do {
            var statuses: [RelayStatusModel] = []
            for taskID in execution.deferredRelayTaskIDs {
                let status = try await aaExecutionService.relayStatus(relayTaskID: taskID)
                statuses.append(status)
            }
            return statuses
        } catch let error as AAExecutionServiceError {
            throw SendFlowServiceError.submissionFailed(error)
        } catch {
            throw SendFlowServiceError.unknown(error)
        }
    }
}
