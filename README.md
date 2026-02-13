Hack Money

Architecture Diagram
```mermaid
flowchart LR
    U["User (Passkey / EOA)"] --> APP["iOS App"]
    APP --> UA["UnifiedTokenAccount (EIP-7702)"]
    UA --> AF["AccumulatorFactory (CREATE2)"]
    UA --> SP["Across SpokePool.deposit"]
    SP --> ACC["Accumulator (destination)"]
    ACC --> RCPT["Recipient"]
    ACC --> UA
```

Implementation Checklist
- Define UniversalIntent + ChainAction schema (chainId-scoped actions).
- Implement Simple7702Account with intent verification + chain-scoped execution.
- Implement GlobalAccumulator (deterministic address, accounting, EIP-1271 validation).
- Across V3 integration: attach intent+sig as message; recipient is accumulator.
- Emit MultiChainIntentExecuted with source chains/amounts for UI.
- Indexer/UI: hide internal transfers; display consolidated event.
