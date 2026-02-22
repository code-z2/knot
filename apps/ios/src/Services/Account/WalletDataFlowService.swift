import Balance
import Foundation
import Transactions

@MainActor
final class WalletDataFlowService {
    func refresh(
        walletAddress: String,
        fallbackAccumulatorAddress: String?,
        appSessionFlowService: AppSessionFlowService,
        balanceStore: BalanceStore,
        transactionStore: TransactionStore,
        useSilentRefresh: Bool = false,
    ) async -> String? {
        guard let accumulatorAddress = await appSessionFlowService.resolveAccumulatorAddress(
            eoaAddress: walletAddress,
            fallbackAccumulatorAddress: fallbackAccumulatorAddress,
        ) else {
            return nil
        }

        if useSilentRefresh {
            _ = await balanceStore.silentRefresh()
            _ = await transactionStore.silentRefresh()
        } else {
            await balanceStore.refresh(walletAddress: walletAddress)
            await transactionStore.refresh(
                walletAddress: walletAddress,
                accumulatorAddress: accumulatorAddress,
            )
        }

        return accumulatorAddress
    }
}
