# CrossChainExecutor — Module Type 2 (Executor)

## Purpose

Source-chain dispatch orchestrator. Replaces V1's `Dispatcher` abstract and `UnifiedAccount.dispatch`. Handles Across SpokePool interaction, salt replay protection, and deposit construction.

## Interface

```solidity
contract CrossChainExecutor is IERC7579Module {
    // Per-account config
    mapping(address account => ExecutorConfig) internal _configs;

    // Per-account salt replay
    mapping(address account => mapping(bytes32 salt => bool used)) internal _usedSalts;

    struct ExecutorConfig {
        address spokePool;
        address accumulatorModule;  // for computing destination recipient (account address)
    }
}
```

## Module Lifecycle

### onInstall

```solidity
function onInstall(bytes calldata data) external {
    (address spokePool) = abi.decode(data, (address));
    require(spokePool != address(0), "invalid spokePool");
    _configs[msg.sender] = ExecutorConfig({
        spokePool: spokePool,
        accumulatorModule: address(0)  // not needed — recipient is the account itself
    });
}
```

### onUninstall

```solidity
function onUninstall(bytes calldata) external {
    delete _configs[msg.sender];
}
```

## Core: `dispatch`

Called by the account during UserOp execution. The account's `execute` calls `crossChainExecutor.dispatch(order)`, which calls back via `executeFromExecutor` to approve tokens and deposit on the SpokePool.

```solidity
function dispatch(OnchainCrossChainOrder calldata envelope) external {
    address account = msg.sender;
    ExecutorConfig memory config = _configs[account];

    DispatchOrder memory order = abi.decode(envelope.orderData, (DispatchOrder));

    // Salt replay protection (per account)
    bytes32 saltKey = keccak256(abi.encode(account, order.salt));
    require(!_usedSalts[account][order.salt], "salt reused");
    _usedSalts[account][order.salt] = true;

    // Validate fill deadline bounds
    _validateFillDeadline(envelope.fillDeadline);

    // Build destination message (for Accumulator routing)
    bytes memory message;
    if (order.recipient == account) {
        // Accumulator flow: account IS the recipient
        message = abi.encode(
            order.salt,
            block.chainid,
            envelope.fillDeadline,
            account,            // depositor
            order.sumOutput,
            order.outputToken
        );
    }
    // else: direct bridge, empty message

    // Approve input token to SpokePool (via account)
    IERC7579Execution(account).executeFromExecutor(
        SINGLE_DEFAULT_MODE,
        _encodeSingle(
            order.inputToken,
            0,
            abi.encodeCall(IERC20.forceApprove, (config.spokePool, order.inputAmount))
        )
    );

    // Deposit on SpokePool (via account)
    IERC7579Execution(account).executeFromExecutor(
        SINGLE_DEFAULT_MODE,
        _encodeSingle(
            config.spokePool,
            0,  // or msg.value for native deposits
            abi.encodeCall(ISpokePool.deposit, (
                _toBytes32(account),           // depositor
                _toBytes32(order.recipient),   // recipient (account for accumulator flow)
                _toBytes32(order.inputToken),
                _toBytes32(order.outputToken),
                order.inputAmount,
                order.minOutput,
                order.destChainId,
                bytes32(0),                    // exclusiveRelayer
                uint32(block.timestamp),       // quoteTimestamp
                envelope.fillDeadline,
                uint32(0),                     // exclusivityParameter
                message
            ))
        )
    );

    emit CrossChainOrderDispatched(account, order.salt, order.destChainId);
}
```

## Call Flow

```
UserOp → EntryPoint
  → MerkleValidator validates ✓
  → account.execute(BATCH, [
      Execution(crossChainExecutor, 0, dispatch(order))
    ])
  → CrossChainExecutor.dispatch(order)
    → check salt replay
    → account.executeFromExecutor → approve inputToken to SpokePool
    → account.executeFromExecutor → SpokePool.deposit(...)
```

The executor pattern: the account calls the executor, the executor calls back via `executeFromExecutor`. The account is always the `msg.sender` for the SpokePool — the depositor.

## Recipient Change from V1

| V1 | V2 |
|---|---|
| `recipient = accumulator` (separate contract) | `recipient = account` (account itself) |

In V2, the Across deposit recipient is the account address. The SpokePool delivers tokens to the account and calls `handleV3AcrossMessage` on the account. The fallback routes to AccumulatorModule for fill tracking.

## Salt Replay Protection

- Per-account: `_usedSalts[account][salt]`
- The salt is in the `DispatchOrder`, which is in the UserOp's `callData`, which is bound in the `userOpHash` leaf. Double protection — the salt can't be replayed (module tracks it) AND the UserOp can't be replayed (EntryPoint nonce).
- V1's `usedSalts` mapping on the account is replaced by the module's per-account tracking.

## Fill Deadline Validation

Same bounds as V1:

```solidity
uint256 public constant MIN_FILL_DEADLINE_WINDOW = 5 minutes;
uint256 public constant MAX_FILL_DEADLINE_WINDOW = 1 days;

function _validateFillDeadline(uint32 fillDeadline) internal view {
    require(fillDeadline >= block.timestamp + MIN_FILL_DEADLINE_WINDOW, "too soon");
    require(fillDeadline <= block.timestamp + MAX_FILL_DEADLINE_WINDOW, "too far");
}
```

## Native Token Handling

Same as V1: the Dispatcher does not wrap/unwrap native tokens. If wrapping is needed, it must be a preceding call in the UserOp's execution batch. Native deposits forward `msg.value` to the SpokePool via the `executeFromExecutor` call.

## ERC-7683 Compatibility

Preserves the `OnchainCrossChainOrder` envelope and `DispatchOrder` data format from V1. The `orderDataType` must match `DISPATCH_ORDER_TYPEHASH`.

## Encoding Helpers

```solidity
/// @dev Encodes a single execution for executeFromExecutor (ERC-7579 packed format).
function _encodeSingle(address target, uint256 value, bytes memory data)
    internal pure returns (bytes memory)
{
    return abi.encodePacked(target, value, data);
}

/// @dev Left-pads an address into bytes32 (Across V3 deposit format).
function _toBytes32(address addr) internal pure returns (bytes32) {
    return bytes32(uint256(uint160(addr)));
}
```

## Security Considerations

- **No signature handling.** The executor never touches signatures. Validation is entirely upstream (MerkleValidator via EntryPoint).
- **Salt is double-bound.** In the module's storage AND in the userOpHash. Even if the module's salt check were bypassed, the EntryPoint nonce prevents replay.
- **executeFromExecutor access.** Only installed executors can call this. The account checks `_isModuleInstalled(MODULE_TYPE_EXECUTOR, msg.sender)`.
- **Re-entrancy.** The dispatch function makes two external calls via `executeFromExecutor`. Each call re-enters the account. The account's execution logic handles this safely. Consider adding `nonReentrant` to `dispatch` for defense-in-depth.
