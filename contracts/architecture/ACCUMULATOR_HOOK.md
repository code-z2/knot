# AccumulatorHook — Module Type 4 (Hook)

## Purpose

Enforces the token reservation invariant: after any account execution, the account must still hold at least `reservedByToken[token]` of each token with active fills. Prevents the user from accidentally spending tokens that are reserved for in-progress cross-chain fills.

Also serves as the UX data source — the client reads `reservedByToken` from AccumulatorModule to compute available vs reserved balances.

## Interface

```solidity
contract AccumulatorHook is IERC7579Hook {
    AccumulatorModule public immutable accumulator;

    constructor(address _accumulator) {
        accumulator = AccumulatorModule(_accumulator);
    }
}
```

## Module Lifecycle

### onInstall

```solidity
function onInstall(bytes calldata data) external {
    // Optional: store AccumulatorModule address per account if not using immutable
    // For immutable pattern, no setup needed
}
```

### onUninstall

```solidity
function onUninstall(bytes calldata) external {
    // No state to clean up
}
```

## Hook Execution

OZ's `AccountERC7579Hooked` wraps `execute` and `executeFromExecutor` with a `withHook` modifier that calls `preCheck` before and `postCheck` after execution.

### preCheck

```solidity
function preCheck(
    address msgSender,
    uint256 value,
    bytes calldata data
) external returns (bytes memory hookData) {
    // No pre-check needed — postCheck handles enforcement
    return "";
}
```

### postCheck

```solidity
function postCheck(bytes calldata hookData) external {
    // Runs via delegatecall — address(this) = account
    address account = address(this);

    // Read reserved tokens from AccumulatorModule (external call)
    address[] memory tokens = accumulator.getReservedTokens(account);

    for (uint256 i; i < tokens.length; i++) {
        address token = tokens[i];
        uint256 reserved = accumulator.reservedByToken(account, token);

        if (reserved == 0) continue;

        uint256 balance;
        if (token == NATIVE) {
            balance = account.balance;
        } else {
            balance = IERC20(token).balanceOf(account);
        }

        require(balance >= reserved, "AccumulatorHook: would spend reserved fill tokens");
    }
}
```

### How It Works

1. User signs a UserOp that spends tokens (e.g., swap 25 USDC).
2. EntryPoint → MerkleValidator validates the UserOp ✓
3. Account calls `execute`:
   - `preCheck` runs (no-op)
   - Execution runs (swap 25 USDC)
   - `postCheck` runs:
     - Reads `reservedByToken[account][USDC] = 30` from AccumulatorModule
     - Checks `USDC.balanceOf(account) >= 30`
     - If balance < 30: **revert** — the swap tried to spend reserved tokens
     - If balance >= 30: pass ✓

### What Gets Caught

```
Account balance: 50 USDC
Reserved for fills: 30 USDC
Available: 20 USDC

UserOp: transfer 25 USDC to bob
  → execute runs: balance drops to 25
  → postCheck: 25 >= 30? NO → revert ✓

UserOp: transfer 15 USDC to bob
  → execute runs: balance drops to 35
  → postCheck: 35 >= 30? YES → pass ✓
```

## UX Integration

### Client reads reservation data

```swift
func computeBalance(token: Address, account: Address) -> TokenBalance {
    let onChain = rpc.call(token, "balanceOf", account)
    let reserved = rpc.call(accumulatorModule, "reservedByToken", account, token)

    return TokenBalance(
        available: onChain - reserved,
        reserved: reserved,
        total: onChain
    )
}
```

### Available balance stays stable during fills

```
Fill 1 lands (10 USDC):
  onChain:   30    (was 20, +10 from fill)
  reserved:  10    (+10 from fill)
  available: 20    (unchanged)

Fill 2 lands (20 USDC):
  onChain:   50    (+20 from fill)
  reserved:  30    (+20 from fill)
  available: 20    (unchanged)

Intent executes (50 USDC sent):
  onChain:    0
  reserved:   0
  available:  0    (one clean drop)
```

The user's available balance never shows the intermediate increase-then-decrease. Fills arrive, reservation grows in lockstep, available stays flat.

## Hook and executeIntent Interaction

When `executeIntent` runs, it decrements `reservedByToken` and transfers tokens via `executeFromExecutor`. The hook's `postCheck` sees the final state:

```
Before executeIntent:
  balance: 50, reserved: 30

executeIntent runs:
  → reserved -= 30 (now 0)
  → transfer 50 USDC to recipient (balance → 0)

postCheck:
  reserved = 0, balance = 0
  0 >= 0 → pass ✓
```

No conflict. The reservation is released before the balance check.

Note: `executeIntent` is called via the fallback handler path, not directly through `execute`. However, the account's self-call (`self.executeIntent(...)`) goes through the `execute` function, so the hook wraps the entire batch including the executeIntent call. The `executeFromExecutor` callback from AccumulatorModule also goes through the hook if `AccountERC7579Hooked.executeFromExecutor` has the `withHook` modifier.

## Gas Overhead

Per execution:
- 1 external call to `accumulator.getReservedTokens(account)` (~2600 gas cold, ~100 warm)
- N external calls to `accumulator.reservedByToken(account, token)` (~2600 each cold)
- N `balanceOf` calls (~2600 each cold)
- Total: ~5200 * N gas for N reserved tokens

In practice, N is small (1-3 tokens with active fills). The overhead is ~5-15k gas per execution — negligible compared to the execution itself.

When no fills are active, `reservedTokenList` is empty and the hook is essentially free (one external call returning an empty array).

## Security Considerations

- **Post-check only.** The hook doesn't try to predict what the execution will do. It checks the result. This is robust against any execution pattern — simple transfers, complex DeFi calls, batched operations.
- **External reads.** The hook reads from AccumulatorModule via external calls. The module's state is authoritative. The hook cannot be tricked by stale data — it reads at execution time.
- **delegatecall context.** The hook runs via `delegatecall` from the account. `address(this)` is the account. `balanceOf(address(this))` returns the account's actual balance. This is correct.
- **No state.** The hook stores nothing. It's a pure invariant checker. No storage slots to collide with, no state to corrupt.
- **Cannot be bypassed.** The hook is installed as type 4 on the account. OZ's `withHook` modifier wraps `execute` and `executeFromExecutor`. All execution paths go through the hook.

## Interaction with AccumulatorModule

The hook and module are tightly coupled but clearly separated:

| Responsibility | Module |
|---|---|
| Track fills and reservations | AccumulatorModule |
| Enforce reservation invariant | AccumulatorHook |
| Expose data for UX | AccumulatorModule (via public mappings) |

The hook is a read-only consumer of the module's state. It never writes to the module. The module never references the hook.
