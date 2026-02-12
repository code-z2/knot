import AA
import Balance
import BigInt
import Foundation
import RPC
import Transactions

/// Main entry point for multi-chain transfer route resolution.
///
/// Given a source asset, destination chain/token, and amount, the RouteComposer
/// determines the optimal sequence of on-chain calls (transfers, approvals,
/// swaps, bridges) and returns ready-to-sign `[ChainCalls]` + an optional `jobId`.
///
/// Routes are resolved across 5 cases:
/// 1. Same-chain direct transfer
/// 2. Same-chain swap + transfer
/// 3. Cross-chain bridge (same bridgeable token)
/// 4. Cross-chain bridge + swap (different tokens)
/// 5. Multi-chain accumulate (scatter-gather from multiple chains)
public actor RouteComposer {
  private let bridgeProvider: BridgeProvider
  private let swapProvider: SwapProvider
  private let rpcClient: RPCClient

  public init(
    bridgeProvider: BridgeProvider = AcrossBridgeProvider(),
    swapProvider: SwapProvider = LiFiSwapProvider(),
    rpcClient: RPCClient = RPCClient()
  ) {
    self.bridgeProvider = bridgeProvider
    self.swapProvider = swapProvider
    self.rpcClient = rpcClient
  }

  /// Resolve the optimal transfer route.
  ///
  /// - Parameters:
  ///   - fromAddress: User's smart account address.
  ///   - toAddress: Recipient address.
  ///   - sourceAsset: The asset the user wants to spend (from BalanceStore).
  ///   - destChainId: Destination chain ID.
  ///   - destToken: Destination token contract address.
  ///   - destTokenSymbol: Display symbol for the destination token.
  ///   - destTokenDecimals: Decimal places for the destination token.
  ///   - amount: Amount in human-readable decimal (source asset units).
  ///   - accumulatorAddress: Precomputed accumulator address for this user (from SmartAccountClient).
  /// - Returns: A `TransferRoute` with calldata and visualization steps.
  public func getRoute(
    fromAddress: String,
    toAddress: String,
    sourceAsset: TokenBalance,
    destChainId: UInt64,
    destToken: String,
    destTokenSymbol: String,
    destTokenDecimals: Int,
    amount: Decimal,
    accumulatorAddress: String?
  ) async throws -> TransferRoute {
    // Validate inputs
    guard amount > 0 else {
      throw RouteError.insufficientBalance
    }

    // Convert amount to wei for the source asset
    let sourceAmountWei = amountToWei(amount, decimals: sourceAsset.decimals)

    // Find chain balances for the source asset
    let chainBalances = sourceAsset.chainBalances

    // Check if sufficient balance on dest chain (Cases 1 & 2)
    let destChainBalance = chainBalances.first { $0.chainID == destChainId }
    let isSameToken = isSameTokenAddress(
      sourceAsset.contractAddress, destToken, sourceChainId: destChainId, destChainId: destChainId
    )

    if let destBalance = destChainBalance, destBalance.balance >= amount {
      if isSameToken {
        // Case 1: Same-chain direct transfer
        return try buildDirectTransferRoute(
          fromAddress: fromAddress,
          toAddress: toAddress,
          sourceAsset: sourceAsset,
          destChainId: destChainId,
          amount: amount,
          amountWei: sourceAmountWei,
          chainName: destBalance.chainName
        )
      } else {
        // Case 2: Same-chain swap + transfer
        return try await buildSwapTransferRoute(
          fromAddress: fromAddress,
          toAddress: toAddress,
          sourceAsset: sourceAsset,
          destChainId: destChainId,
          destToken: destToken,
          destTokenSymbol: destTokenSymbol,
          destTokenDecimals: destTokenDecimals,
          amount: amount,
          amountWei: sourceAmountWei,
          chainName: destBalance.chainName
        )
      }
    }

    // Find source chains with balance (excluding dest chain if not enough)
    let sourceChainsWithBalance = chainBalances
      .filter { $0.balance > 0 }
      .sorted { $0.balance > $1.balance }  // Largest first

    guard !sourceChainsWithBalance.isEmpty else {
      throw RouteError.insufficientBalance
    }

    // Check total balance across all chains
    let totalBalance = sourceChainsWithBalance.reduce(Decimal.zero) { $0 + $1.balance }
    guard totalBalance >= amount else {
      throw RouteError.insufficientBalance
    }

    // Try single source chain first (Cases 3 & 4)
    if let singleSource = sourceChainsWithBalance.first(where: { $0.balance >= amount && $0.chainID != destChainId }) {
      let sourceTokenAddress = singleSource.contractAddress
      let isSourceFlightAsset = FlightAssets.isFlightAsset(
        contractAddress: sourceTokenAddress, chainId: singleSource.chainID
      )

      if isSourceFlightAsset && isSameToken {
        // Case 3: Simple cross-chain bridge
        return try await buildSimpleBridgeRoute(
          fromAddress: fromAddress,
          toAddress: toAddress,
          sourceAsset: sourceAsset,
          sourceChainId: singleSource.chainID,
          sourceChainName: singleSource.chainName,
          destChainId: destChainId,
          destToken: destToken,
          destTokenSymbol: destTokenSymbol,
          amount: amount,
          amountWei: sourceAmountWei
        )
      } else {
        // Case 4: Cross-chain bridge + swap
        guard let accAddress = accumulatorAddress else {
          throw RouteError.noRouteFound(reason: "Accumulator address required for cross-chain swap")
        }
        return try await buildBridgeSwapRoute(
          fromAddress: fromAddress,
          toAddress: toAddress,
          sourceAsset: sourceAsset,
          sourceChainId: singleSource.chainID,
          sourceChainName: singleSource.chainName,
          destChainId: destChainId,
          destToken: destToken,
          destTokenSymbol: destTokenSymbol,
          destTokenDecimals: destTokenDecimals,
          amount: amount,
          amountWei: sourceAmountWei,
          accumulatorAddress: accAddress
        )
      }
    }

    // Case 5: Multi-chain accumulate
    guard let accAddress = accumulatorAddress else {
      throw RouteError.noRouteFound(reason: "Accumulator address required for multi-chain transfer")
    }
    return try await buildAccumulateRoute(
      fromAddress: fromAddress,
      toAddress: toAddress,
      sourceAsset: sourceAsset,
      sourceChainsWithBalance: sourceChainsWithBalance,
      destChainId: destChainId,
      destToken: destToken,
      destTokenSymbol: destTokenSymbol,
      destTokenDecimals: destTokenDecimals,
      totalAmount: amount,
      accumulatorAddress: accAddress
    )
  }

  // MARK: - Case 1: Direct Transfer

  private func buildDirectTransferRoute(
    fromAddress: String,
    toAddress: String,
    sourceAsset: TokenBalance,
    destChainId: UInt64,
    amount: Decimal,
    amountWei: String,
    chainName: String
  ) throws -> TransferRoute {
    let call: Call
    if sourceAsset.isNative {
      call = ERC20Encoder.nativeTransferCall(to: toAddress, amountWei: amountWei)
    } else {
      call = try ERC20Encoder.transferCall(
        token: sourceAsset.contractAddress,
        to: toAddress,
        amountWei: amountWei
      )
    }

    let step = RouteStep(
      chainId: destChainId,
      chainName: chainName,
      action: .transfer,
      inputAmount: amount,
      inputSymbol: sourceAsset.symbol,
      outputAmount: amount,
      outputSymbol: sourceAsset.symbol
    )

    return TransferRoute(
      steps: [step],
      chainCalls: [ChainCalls(chainId: destChainId, calls: [call])],
      jobId: nil,
      destinationChainId: destChainId,
      estimatedAmountOut: amount,
      estimatedAmountOutSymbol: sourceAsset.symbol
    )
  }

  // MARK: - Case 2: Swap + Transfer

  private func buildSwapTransferRoute(
    fromAddress: String,
    toAddress: String,
    sourceAsset: TokenBalance,
    destChainId: UInt64,
    destToken: String,
    destTokenSymbol: String,
    destTokenDecimals: Int,
    amount: Decimal,
    amountWei: String,
    chainName: String
  ) async throws -> TransferRoute {
    let quote = try await swapProvider.getQuote(
      inputToken: sourceAsset.contractAddress,
      outputToken: destToken,
      inputAmountWei: amountWei,
      chainId: destChainId,
      fromAddress: fromAddress
    )

    var calls: [Call] = []

    // Approve swap target if ERC20
    if !sourceAsset.isNative {
      let approveCall = try ERC20Encoder.approveCall(
        token: sourceAsset.contractAddress,
        spender: quote.approvalTarget,
        amountWei: amountWei
      )
      calls.append(approveCall)
    }

    // Swap call
    let swapCall = Call(
      to: quote.swapTarget,
      dataHex: "0x" + quote.swapCalldata.map { String(format: "%02x", $0) }.joined(),
      valueWei: quote.swapValue
    )
    calls.append(swapCall)

    let outputAmount = weiToAmount(quote.outputAmountWei, decimals: destTokenDecimals)

    let step = RouteStep(
      chainId: destChainId,
      chainName: chainName,
      action: .swap,
      inputAmount: amount,
      inputSymbol: sourceAsset.symbol,
      outputAmount: outputAmount,
      outputSymbol: destTokenSymbol
    )

    return TransferRoute(
      steps: [step],
      chainCalls: [ChainCalls(chainId: destChainId, calls: calls)],
      jobId: nil,
      destinationChainId: destChainId,
      estimatedAmountOut: outputAmount,
      estimatedAmountOutSymbol: destTokenSymbol
    )
  }

  // MARK: - Case 3: Simple Bridge

  private func buildSimpleBridgeRoute(
    fromAddress: String,
    toAddress: String,
    sourceAsset: TokenBalance,
    sourceChainId: UInt64,
    sourceChainName: String,
    destChainId: UInt64,
    destToken: String,
    destTokenSymbol: String,
    amount: Decimal,
    amountWei: String
  ) async throws -> TransferRoute {
    let quote = try await bridgeProvider.getQuote(
      inputToken: sourceAsset.contractAddress,
      outputToken: destToken,
      inputAmountWei: amountWei,
      sourceChainId: sourceChainId,
      destinationChainId: destChainId,
      recipient: toAddress,
      message: Data()
    )

    var calls: [Call] = []

    // Approve SpokePool if ERC20
    if !sourceAsset.isNative {
      let spokePool = try AAConstants.messengerAddress(chainId: sourceChainId)
      let approveCall = try ERC20Encoder.approveCall(
        token: sourceAsset.contractAddress,
        spender: spokePool,
        amountWei: amountWei
      )
      calls.append(approveCall)
    }

    // Deposit call
    let depositCall = try bridgeProvider.encodeDeposit(
      quote: quote,
      depositor: fromAddress,
      recipient: toAddress,
      sourceChainId: sourceChainId,
      destinationChainId: destChainId
    )
    calls.append(depositCall)

    let outputAmount = weiToAmount(quote.outputAmountWei, decimals: sourceAsset.decimals)

    let step = RouteStep(
      chainId: sourceChainId,
      chainName: sourceChainName,
      action: .bridge,
      inputAmount: amount,
      inputSymbol: sourceAsset.symbol,
      outputAmount: outputAmount,
      outputSymbol: destTokenSymbol
    )

    return TransferRoute(
      steps: [step],
      chainCalls: [ChainCalls(chainId: sourceChainId, calls: calls)],
      jobId: nil,
      destinationChainId: destChainId,
      estimatedAmountOut: outputAmount,
      estimatedAmountOutSymbol: destTokenSymbol
    )
  }

  // MARK: - Case 4: Bridge + Swap

  private func buildBridgeSwapRoute(
    fromAddress: String,
    toAddress: String,
    sourceAsset: TokenBalance,
    sourceChainId: UInt64,
    sourceChainName: String,
    destChainId: UInt64,
    destToken: String,
    destTokenSymbol: String,
    destTokenDecimals: Int,
    amount: Decimal,
    amountWei: String,
    accumulatorAddress: String
  ) async throws -> TransferRoute {
    // Find flight asset (bridge intermediary)
    guard let flight = FlightAssets.bestFlightAsset(
      sourceChain: sourceChainId, destChain: destChainId
    ) else {
      throw RouteError.noRouteFound(
        reason: "No common bridge asset between chain \(sourceChainId) and \(destChainId)"
      )
    }

    var sourceCalls: [Call] = []
    var steps: [RouteStep] = []
    var bridgeInputAmountWei = amountWei
    var bridgeInputToken = sourceAsset.contractAddress

    // Step 1: Swap to flight asset on source chain if needed
    let sourceIsFlightAsset = sourceAsset.contractAddress.lowercased() == flight.source.contractAddress.lowercased()

    if !sourceIsFlightAsset {
      // Swap source token → flight asset on source chain
      let swapQuote = try await swapProvider.getQuote(
        inputToken: sourceAsset.contractAddress,
        outputToken: flight.source.contractAddress,
        inputAmountWei: amountWei,
        chainId: sourceChainId,
        fromAddress: fromAddress
      )

      // Approve swap target
      if !sourceAsset.isNative {
        sourceCalls.append(try ERC20Encoder.approveCall(
          token: sourceAsset.contractAddress,
          spender: swapQuote.approvalTarget,
          amountWei: amountWei
        ))
      }

      // Swap call
      sourceCalls.append(Call(
        to: swapQuote.swapTarget,
        dataHex: "0x" + swapQuote.swapCalldata.map { String(format: "%02x", $0) }.joined(),
        valueWei: swapQuote.swapValue
      ))

      let swapOutput = weiToAmount(swapQuote.outputAmountWei, decimals: flight.source.decimals)
      steps.append(RouteStep(
        chainId: sourceChainId,
        chainName: sourceChainName,
        action: .swap,
        inputAmount: amount,
        inputSymbol: sourceAsset.symbol,
        outputAmount: swapOutput,
        outputSymbol: flight.source.symbol
      ))

      bridgeInputAmountWei = swapQuote.outputAmountWei
      bridgeInputToken = flight.source.contractAddress
    }

    // Step 2: Build destination swap calls for Accumulator message
    // The Accumulator will swap the bridged flight asset → dest token on dest chain
    let destSwapQuote = try await swapProvider.getQuote(
      inputToken: flight.dest.contractAddress,
      outputToken: destToken,
      inputAmountWei: bridgeInputAmountWei,
      chainId: destChainId,
      fromAddress: accumulatorAddress
    )

    // Dest swap calls: [approve, swap]
    var destSwapCalls: [Call] = []
    destSwapCalls.append(try ERC20Encoder.approveCall(
      token: flight.dest.contractAddress,
      spender: destSwapQuote.approvalTarget,
      amountWei: bridgeInputAmountWei
    ))
    destSwapCalls.append(Call(
      to: destSwapQuote.swapTarget,
      dataHex: "0x" + destSwapQuote.swapCalldata.map { String(format: "%02x", $0) }.joined(),
      valueWei: destSwapQuote.swapValue
    ))

    let nonce = UInt64(Date().timeIntervalSince1970)

    // Encode Accumulator message
    let message = try AccumulatorEncoder.encodeMessage(
      inputToken: flight.dest.contractAddress,
      outputToken: destToken,
      recipient: toAddress,
      minInputWei: bridgeInputAmountWei,
      minOutputWei: destSwapQuote.outputAmountWei,
      swapCalls: destSwapCalls,
      nonce: nonce
    )

    // Compute jobId
    let jobId = try AccumulatorEncoder.computeJobId(
      owner: fromAddress,
      inputToken: flight.dest.contractAddress,
      outputToken: destToken,
      recipient: toAddress,
      minInputWei: bridgeInputAmountWei,
      minOutputWei: destSwapQuote.outputAmountWei,
      swapCalls: destSwapCalls
    )

    // Step 3: Bridge flight asset → Accumulator with message
    let bridgeQuote = try await bridgeProvider.getQuote(
      inputToken: bridgeInputToken,
      outputToken: flight.dest.contractAddress,
      inputAmountWei: bridgeInputAmountWei,
      sourceChainId: sourceChainId,
      destinationChainId: destChainId,
      recipient: accumulatorAddress,
      message: message
    )

    // Approve SpokePool for flight asset
    if !ERC20Encoder.isNative(bridgeInputToken) {
      let spokePool = try AAConstants.messengerAddress(chainId: sourceChainId)
      sourceCalls.append(try ERC20Encoder.approveCall(
        token: bridgeInputToken,
        spender: spokePool,
        amountWei: bridgeInputAmountWei
      ))
    }

    // Deposit call
    let depositCall = try bridgeProvider.encodeDeposit(
      quote: bridgeQuote,
      depositor: fromAddress,
      recipient: accumulatorAddress,
      sourceChainId: sourceChainId,
      destinationChainId: destChainId
    )
    sourceCalls.append(depositCall)

    let bridgeOutput = weiToAmount(bridgeQuote.outputAmountWei, decimals: flight.dest.decimals)
    steps.append(RouteStep(
      chainId: sourceChainId,
      chainName: sourceChainName,
      action: .accumulate,
      inputAmount: weiToAmount(bridgeInputAmountWei, decimals: flight.source.decimals),
      inputSymbol: flight.source.symbol,
      outputAmount: bridgeOutput,
      outputSymbol: flight.dest.symbol
    ))

    let finalOutput = weiToAmount(destSwapQuote.outputAmountWei, decimals: destTokenDecimals)

    return TransferRoute(
      steps: steps,
      chainCalls: [
        ChainCalls(chainId: sourceChainId, calls: sourceCalls),
        ChainCalls(chainId: destChainId, calls: []),  // registerJob injected by prelude
      ],
      jobId: jobId,
      destinationChainId: destChainId,
      estimatedAmountOut: finalOutput,
      estimatedAmountOutSymbol: destTokenSymbol
    )
  }

  // MARK: - Case 5: Multi-Chain Accumulate

  private func buildAccumulateRoute(
    fromAddress: String,
    toAddress: String,
    sourceAsset: TokenBalance,
    sourceChainsWithBalance: [ChainBalance],
    destChainId: UInt64,
    destToken: String,
    destTokenSymbol: String,
    destTokenDecimals: Int,
    totalAmount: Decimal,
    accumulatorAddress: String
  ) async throws -> TransferRoute {
    // Find flight asset for each source chain → dest chain
    guard let destFlight = FlightAssets.byChain[destChainId]?.first else {
      throw RouteError.noRouteFound(reason: "No flight asset on destination chain \(destChainId)")
    }

    // Determine how much to pull from each source chain
    var remaining = totalAmount
    var allocations: [(chain: ChainBalance, amount: Decimal)] = []

    for chain in sourceChainsWithBalance {
      guard remaining > 0 else { break }
      let contribution = min(chain.balance, remaining)
      allocations.append((chain: chain, amount: contribution))
      remaining -= contribution
    }

    guard remaining <= 0 else {
      throw RouteError.insufficientBalance
    }

    // Compute total bridge input in wei
    let totalBridgeInputWei = amountToWei(totalAmount, decimals: sourceAsset.decimals)

    // Build destination swap calls if token mismatch
    let isSameToken = isSameTokenAddress(
      destFlight.contractAddress, destToken,
      sourceChainId: destChainId, destChainId: destChainId
    )

    var destSwapCalls: [Call] = []
    var destMinOutputWei = totalBridgeInputWei
    var finalOutputSymbol = destTokenSymbol

    if !isSameToken {
      let destSwapQuote = try await swapProvider.getQuote(
        inputToken: destFlight.contractAddress,
        outputToken: destToken,
        inputAmountWei: totalBridgeInputWei,
        chainId: destChainId,
        fromAddress: accumulatorAddress
      )

      destSwapCalls.append(try ERC20Encoder.approveCall(
        token: destFlight.contractAddress,
        spender: destSwapQuote.approvalTarget,
        amountWei: totalBridgeInputWei
      ))
      destSwapCalls.append(Call(
        to: destSwapQuote.swapTarget,
        dataHex: "0x" + destSwapQuote.swapCalldata.map { String(format: "%02x", $0) }.joined(),
        valueWei: destSwapQuote.swapValue
      ))

      destMinOutputWei = destSwapQuote.outputAmountWei
      finalOutputSymbol = destTokenSymbol
    }

    let nonce = UInt64(Date().timeIntervalSince1970)

    let message = try AccumulatorEncoder.encodeMessage(
      inputToken: destFlight.contractAddress,
      outputToken: destToken,
      recipient: toAddress,
      minInputWei: totalBridgeInputWei,
      minOutputWei: destMinOutputWei,
      swapCalls: destSwapCalls,
      nonce: nonce
    )

    let jobId = try AccumulatorEncoder.computeJobId(
      owner: fromAddress,
      inputToken: destFlight.contractAddress,
      outputToken: destToken,
      recipient: toAddress,
      minInputWei: totalBridgeInputWei,
      minOutputWei: destMinOutputWei,
      swapCalls: destSwapCalls
    )

    // Build bridge calls for each source chain
    var allChainCalls: [ChainCalls] = []
    var steps: [RouteStep] = []

    for (chain, allocationAmount) in allocations {
      let allocationWei = amountToWei(allocationAmount, decimals: sourceAsset.decimals)

      guard let sourceFlight = FlightAssets.bestFlightAsset(
        sourceChain: chain.chainID, destChain: destChainId
      ) else {
        throw RouteError.noRouteFound(
          reason: "No bridge route from chain \(chain.chainID) to \(destChainId)"
        )
      }

      var chainCallsList: [Call] = []
      var bridgeAmountWei = allocationWei
      var bridgeToken = sourceAsset.contractAddress

      // Swap to flight asset on source chain if needed
      let isFlightOnSource = sourceAsset.contractAddress.lowercased()
        == sourceFlight.source.contractAddress.lowercased()

      if !isFlightOnSource {
        let swapQuote = try await swapProvider.getQuote(
          inputToken: sourceAsset.contractAddress,
          outputToken: sourceFlight.source.contractAddress,
          inputAmountWei: allocationWei,
          chainId: chain.chainID,
          fromAddress: fromAddress
        )

        if !sourceAsset.isNative {
          chainCallsList.append(try ERC20Encoder.approveCall(
            token: sourceAsset.contractAddress,
            spender: swapQuote.approvalTarget,
            amountWei: allocationWei
          ))
        }

        chainCallsList.append(Call(
          to: swapQuote.swapTarget,
          dataHex: "0x" + swapQuote.swapCalldata.map { String(format: "%02x", $0) }.joined(),
          valueWei: swapQuote.swapValue
        ))

        bridgeAmountWei = swapQuote.outputAmountWei
        bridgeToken = sourceFlight.source.contractAddress

        steps.append(RouteStep(
          chainId: chain.chainID,
          chainName: chain.chainName,
          action: .swap,
          inputAmount: allocationAmount,
          inputSymbol: sourceAsset.symbol,
          outputAmount: weiToAmount(bridgeAmountWei, decimals: sourceFlight.source.decimals),
          outputSymbol: sourceFlight.source.symbol
        ))
      }

      // Bridge to Accumulator
      let bridgeQuote = try await bridgeProvider.getQuote(
        inputToken: bridgeToken,
        outputToken: sourceFlight.dest.contractAddress,
        inputAmountWei: bridgeAmountWei,
        sourceChainId: chain.chainID,
        destinationChainId: destChainId,
        recipient: accumulatorAddress,
        message: message
      )

      // Approve SpokePool
      if !ERC20Encoder.isNative(bridgeToken) {
        let spokePool = try AAConstants.messengerAddress(chainId: chain.chainID)
        chainCallsList.append(try ERC20Encoder.approveCall(
          token: bridgeToken,
          spender: spokePool,
          amountWei: bridgeAmountWei
        ))
      }

      // Deposit call
      let depositCall = try bridgeProvider.encodeDeposit(
        quote: bridgeQuote,
        depositor: fromAddress,
        recipient: accumulatorAddress,
        sourceChainId: chain.chainID,
        destinationChainId: destChainId
      )
      chainCallsList.append(depositCall)

      let bridgeOutput = weiToAmount(bridgeQuote.outputAmountWei, decimals: sourceFlight.dest.decimals)
      steps.append(RouteStep(
        chainId: chain.chainID,
        chainName: chain.chainName,
        action: .accumulate,
        inputAmount: weiToAmount(bridgeAmountWei, decimals: sourceFlight.source.decimals),
        inputSymbol: sourceFlight.source.symbol,
        outputAmount: bridgeOutput,
        outputSymbol: sourceFlight.dest.symbol
      ))

      allChainCalls.append(ChainCalls(chainId: chain.chainID, calls: chainCallsList))
    }

    // Add destination chain entry so relay execution can prioritize destination init/validation.
    allChainCalls.append(ChainCalls(chainId: destChainId, calls: []))

    let finalOutput = weiToAmount(destMinOutputWei, decimals: destTokenDecimals)

    return TransferRoute(
      steps: steps,
      chainCalls: allChainCalls,
      jobId: jobId,
      destinationChainId: destChainId,
      estimatedAmountOut: finalOutput,
      estimatedAmountOutSymbol: finalOutputSymbol
    )
  }

  // MARK: - Helpers

  private func isSameTokenAddress(
    _ a: String,
    _ b: String,
    sourceChainId: UInt64,
    destChainId: UInt64
  ) -> Bool {
    // If same chain, compare addresses directly
    if sourceChainId == destChainId {
      return a.lowercased() == b.lowercased()
    }
    // Cross-chain: tokens with same address on different chains are considered "same"
    // (e.g. USDC bridged natively, WETH on L2s)
    return a.lowercased() == b.lowercased()
  }

  private func amountToWei(_ amount: Decimal, decimals: Int) -> String {
    var result = amount
    for _ in 0..<decimals {
      result *= 10
    }
    // Truncate to integer
    var rounded = Decimal()
    NSDecimalRound(&rounded, &result, 0, .down)
    return NSDecimalNumber(decimal: rounded).stringValue
  }

  private func weiToAmount(_ wei: String, decimals: Int) -> Decimal {
    guard let weiDecimal = Decimal(string: wei) else { return .zero }
    var result = weiDecimal
    for _ in 0..<decimals {
      result /= 10
    }
    return result
  }
}
