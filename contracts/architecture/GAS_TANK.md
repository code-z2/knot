# Gas Tank

Per-user USDC escrow for gas sponsorship. Each user gets a deterministic GasTank contract on Base, deployed via CreateX. The user is the owner; the protocol is the cosigner.

## Contracts

| File | Lines | Role |
|------|-------|------|
| `src/gas-tank/GasTank.sol` | ~120 | Per-user escrow: deposit, withdraw, forced withdrawal, debit, sweep |
| `src/gas-tank/IGasTank.sol` | ~90 | Interface, events, errors, structs |

## Design

### Per-user, not singleton

Each user has their own GasTank. Balance = `USDC.balanceOf(gasTank)` — no internal ledger. The GasTank CREATE2 address IS the deposit address. USDC sent there accumulates even before deployment.

### Decoupled from cross-chain

The GasTank knows nothing about Across, SpokePool, or cross-chain orders. All bridging and orchestration is handled at the account level. The GasTank is simply the `recipient` in an `ExecutionParams` — it receives USDC via normal ERC-20 transfer.

### No factory

CreateX deploys GasTanks. Constructor args are deterministic (owner, cosigner, usdc), so anyone can deploy for any user. No custom factory contract.

## State

```
address immutable OWNER        // user's smart account
address immutable COSIGNER     // protocol operator
IERC20  immutable USDC         // USDC token

uint256 withdrawNonce           // replay protection for instant withdrawals
PendingWithdrawal {
    uint128 amount              // requested amount (packed with unlockTime in one slot)
    uint64  unlockTime          // block.timestamp + 4 hours
}
```

## Functions

| Function | Access | Description |
|----------|--------|-------------|
| `deposit(amount)` | Anyone | Pull USDC from msg.sender. Emits `Deposited`. |
| `withdraw(amount, to, deadline, cosignerSig)` | Owner | Instant withdrawal. Cosigner co-signs via EIP-712. |
| `initiateForced(amount)` | Owner | Start 4-hour timelock. One pending per GasTank. |
| `claimForced(to)` | Owner | Claim after timelock. Gets `min(requested, balance)`. |
| `cancelForced()` | Owner | Cancel pending forced withdrawal. |
| `debit(amount, to)` | Cosigner | Charge gas fees. Transfers USDC to `to` (paymaster, billing pool). |
| `sweep(token, to)` | Owner | Recover non-USDC tokens sent by mistake. |

## EIP-712

```
Domain:
  name: "KnotGasTank"
  version: "1"
  chainId: 8453 (Base)
  verifyingContract: <per-user GasTank address>

Withdraw(uint256 amount, address to, uint256 nonce, uint256 deadline)
```

The cosigner signs `Withdraw` off-chain. The owner submits the transaction with the signature. Nonce increments on each use.

## Deposit Flows

### Same-chain (Base)

```
account.execute → usdc.transfer(gasTank, amount)
```

### Cross-chain (any chain → Base)

```
Account on Chain A dispatches cross-chain order
  → Across bridges to user's account on Base
  → executeIntent: recipient = gasTank, finalOutputToken = USDC
  → GasTank receives USDC as a normal transfer
```

### External (CEX → Base)

```
User withdraws USDC from CEX to GasTank CREATE2 address on Base
  → USDC balance at address (GasTank may not be deployed yet)
```

## Withdrawal Flows

### Instant (co-signed)

```
User requests withdrawal → app calls protocol API
  → protocol validates balance, signs Withdraw EIP-712
  → user submits gasTank.withdraw(amount, to, deadline, cosignerSig)
  → USDC transferred immediately
```

### Forced (4-hour timelock)

```
User calls gasTank.initiateForced(amount)
  → 4h timer starts
  [Cosigner can debit outstanding gas fees during window]
After 4h:
  User calls gasTank.claimForced(to)
  → receives min(requestedAmount, currentBalance)
```

## Billing

```
Protocol aggregates gas costs per user (off-chain)
  → gasTank.debit(amount, paymasterAddress)
  → USDC goes to Pimlico/Gelato
```

## Deployment

Via CreateX. Permissionless.

```solidity
salt = keccak256(abi.encode("knot-gas-tank-v1", owner));
initCode = abi.encodePacked(
    type(GasTank).creationCode,
    abi.encode(owner, cosigner, usdc)
);

// Predict
createX.computeCreate2Address(salt, keccak256(initCode));

// Deploy (anyone can call)
createX.deployCreate2(salt, initCode);
```

## Security

| Risk | Mitigation |
|------|------------|
| Cosigner drains via debit | Trusted for billing. Forced withdrawal is user's escape hatch. |
| Cosigner blocks instant withdrawal | User falls back to forced (4h). Cosigner cannot cancel forced path. |
| Signature replay | Nonce per GasTank + deadline expiry. |
| Balance underflow on forced claim | `min(requested, balance)` — debits during window reduce claimable. |
| Non-USDC sent to GasTank | `sweep()` recovers any non-USDC token. |
| CREATE2 front-running | Constructor args are deterministic. Deploying "for" someone gives them ownership. |
