# Relay Proxy Architecture

Fresh architecture workspace for the relay proxy rewrite.

Previous implementation files were moved to [`../_old`](/Users/peter/Developer/knot/packages/relay-proxy/_old).

Current direction:
- `Hono + Cloudflare Workers`
- route-scoped RPC envelopes
- one uniform app-facing auth contract
- passkeys plus App Attest

## Documents

- [00-overview.md](/Users/peter/Developer/knot/packages/relay-proxy/architecture/00-overview.md)
- [01-auth.md](/Users/peter/Developer/knot/packages/relay-proxy/architecture/01-auth.md)
- [02-route-model.md](/Users/peter/Developer/knot/packages/relay-proxy/architecture/02-route-model.md)
- [03-session-model.md](/Users/peter/Developer/knot/packages/relay-proxy/architecture/03-session-model.md)
- [04-upload-v1.md](/Users/peter/Developer/knot/packages/relay-proxy/architecture/04-upload-v1.md)
- [05-relay-v1.md](/Users/peter/Developer/knot/packages/relay-proxy/architecture/05-relay-v1.md)
- [06-gas-tank-v1.md](/Users/peter/Developer/knot/packages/relay-proxy/architecture/06-gas-tank-v1.md)
- [07-queues-anomalies.md](/Users/peter/Developer/knot/packages/relay-proxy/architecture/07-queues-anomalies.md)
- [08-storage-model.md](/Users/peter/Developer/knot/packages/relay-proxy/architecture/08-storage-model.md)
- [09-faucet-v1.md](/Users/peter/Developer/knot/packages/relay-proxy/architecture/09-faucet-v1.md)
- [10-chain-list-v1.md](/Users/peter/Developer/knot/packages/relay-proxy/architecture/10-chain-list-v1.md)
