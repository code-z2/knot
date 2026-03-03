// WalletDataFlowService.swift
// Created by Peter Anyaogu on 03/03/2026.

import Balance
import Foundation
import Transactions

@MainActor
final class WalletDataFlowService {
    func refresh(
        walletAddress: String,
        accumulatorAddress: String?,
        balanceStore: BalanceStore,
        transactionStore: TransactionStore,
        useSilentRefresh: Bool = false,
    ) async {
        if useSilentRefresh {
            _ = await balanceStore.silentRefresh()
            _ = await transactionStore.silentRefresh()
            return
        }

        await balanceStore.refresh(walletAddress: walletAddress)

        if let accumulatorAddress {
            await transactionStore.refresh(
                walletAddress: walletAddress,
                accumulatorAddress: accumulatorAddress,
            )
        }
    }
}
