AGENTS.md

Project Expectations (from hack-money-project-research.md)

Purpose
- Build a chain-abstracted consumer wallet that consolidates same-asset balances across chains and optionally executes a final action, with a single user signature and a clean UX.

Final Agreements (Do not change unless the user requests)
1) Bridge / Intent Engine
   - Use Across V3 as the primary intent engine.
   - Do NOT rely on Everclear or a native many-to-one API (assumed unavailable).
   - Do NOT attempt true cross-chain atomicity. Use parallel intents or an accumulator-driven scatter-gather flow.

2) Account Model
   - Use EIP-7702 for the user account (the EOA becomes the proxy via authorization).
   - No separate smart account proxy deployment for users.
   - Upgrades are done by swapping 7702 authorization to a new implementation (no UUPS/transparent proxy).

3) Signature Model
   - Use a "UniversalIntent" payload signed once (passkey) and replayed across chains.
   - Each chain executes only its own ChainAction, validated by the same signature.
   - Accumulator must validate the intent via EIP-1271 against the user account.

4) Accumulator Pattern
   - Use a deterministic accumulator per user (CREATE2-derived address; no registry required).
   - Accumulator is the Across V3 message recipient (recipient == handler).
   - Accumulator is a pass-through router: it must end transactions with zero balance.
   - Accumulator executes the final action (swap/yield) directly after total is reached.
   - Do not use a separate sub-account unless explicitly reintroduced by the user.

5) UX / Event Parsing
   - Hide internal plumbing transfers (User -> Across, Across -> Accumulator, Accumulator internal hops).
   - Emit a single "MultiChainIntentExecuted" event from the accumulator for UI rendering.
   - The UI should render one consolidated activity item using event data.

6) Initialization / Cost Control
   - Lazy initialization: store the 7702 authorization off-chain and only broadcast on first action.
   - Avoid paymaster costs for non-transacting users.

Non-Goals (unless requested)
- No deep AI/agent scheduling architecture beyond describing the intent flow.
- No alternative bridge providers or multi-chain atomic primitives.
- No proxy upgrade patterns (UUPS/transparent).
- No wallet deployment flows (counterfactual wallets, Safe/KERNEL) unless asked.

Implementation Notes (directional)
- Across V3 messages must be handled by the accumulator (recipient is the handler).
- If accumulator logic reverts, the Across fill must revert (safety guarantee).
- The universal intent must include chainId-specific actions and be signed once.
- Chain abstraction uses parallel Across V3 intents or accumulator-driven scatter-gather.
- User account is EIP-7702: EOA acts as proxy via authorization; no wallet deployment.
- Single-passkey signature over UniversalIntent, replayed across chains.
- Deterministic per-user accumulator (CREATE2) is Across message recipient and executor.
- Accumulator validates intent via EIP-1271 and ends each tx with zero balance.
- UI hides plumbing transfers and renders one MultiChainIntentExecuted event.
- Lazy initialization: store 7702 auth off-chain until first action.
- Store signed 7702 authorization locally in the device Keychain (secure, non-exportable storage).
- Treat the passkey as the portable credential (syncs via platform passkey sync).
- On a new device, re-derive authorization by prompting the user to sign again with the EOA key.
- If no authorization is present, the app remains in “ready” state and defers all on-chain cost.
- First run: create/sync passkey, request a one-time EOA signature for 7702 authorization, store in Keychain only.
- No chain interaction until the user initiates the first action.
- First action: collect passkey signature for UniversalIntent, bundle with stored 7702 authorization, broadcast.
- Subsequent actions: reuse stored authorization, require only passkey signature.

When editing code or docs
- Preserve the architecture above unless the user explicitly changes direction.
