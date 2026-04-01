# Chain List V1

Chain List V1 is the public route for exposing supported chains to the app.

It should return only app-safe chain metadata.
It should not expose internal relay or funding configuration.

## Route

- `POST /v1/chains`
  - allowed methods:
    - `knot_supportedChains`

This route can use normal authenticated app access.

## Request

The request should stay minimal.

```json
{
  "jsonrpc": "2.0",
  "method": "knot_supportedChains",
  "params": {
    "environment": "testnet"
  },
  "id": "req_123"
}
```

`environment` is optional.

Allowed values:

- `testnet`
- `mainnet`

Behavior:

- omitted => return all supported chains
- `testnet` => return testnet chains only
- `mainnet` => return mainnet chains only

## Public Response Shape

The public chain descriptor should be smaller than the internal registry entry.

Suggested shape:

```ts
type PublicChainDescriptor = {
  chainId: number
  name: string
  environment: 'mainnet' | 'testnet'
  supportsRelay: boolean
  supportsFaucet: boolean
}
```

Response:

```json
{
  "jsonrpc": "2.0",
  "id": "req_123",
  "result": {
    "chains": [
      {
        "chainId": 84532,
        "name": "Base Sepolia",
        "environment": "testnet",
        "supportsRelay": true,
        "supportsFaucet": true
      }
    ]
  }
}
```

## Internal vs Public Boundary

The internal chain registry should remain richer than the public response.

Internal config may include:

- `jsonRpcUrl`
- Gelato bundler URL
- quote token
- entry point
- faucet asset definitions
- any future execution or indexing policy

The public route should map from that internal registry to a smaller app-safe descriptor.

It should not expose:

- internal RPC URLs
- bundler URLs
- quote token addresses
- faucet funding amounts
- faucet token addresses

## Public Mapper

The route should use an explicit mapper from internal config to public config.

Suggested shape:

```ts
function toPublicChainDescriptor(chain: SupportedChainConfig): PublicChainDescriptor {
  return {
    chainId: chain.chainId,
    name: chain.name,
    environment: chain.environment,
    supportsRelay: true,
    supportsFaucet: chain.environment === 'testnet',
  }
}
```

Do not return internal objects directly.

## File Organization

Suggested files:

- `src/types/chain.ts`
  - internal chain config types
- `src/types/chain-list.ts`
  - public request and response types
- `src/constants/chains.ts`
  - internal registry values
- `src/utils/chain.ts`
  - URL builders and registry helpers
- `src/utils/chain-list.ts`
  - internal-to-public mapper
- `src/routes/chain-list.ts`
  - route handler

## Internal Chain Config Note

The internal chain registry should support a set of allowed entry points per chain.

Suggested internal field:

- `supportedEntryPoints: readonly Address[]`

The public chain route does not need to expose entry points, but relay policy should validate the client's chosen `entryPoint` against that supported set.

## Filtering Rule

Filtering should happen against the internal registry before mapping.

That means:

1. load supported chain configs
2. filter by optional `environment`
3. map to public descriptors
4. return sorted output

Suggested sort:

- `mainnet` before `testnet`, or
- ascending `chainId`

Pick one stable ordering and keep it deterministic.

## Why This Route Is Useful

This route gives the app:

- one canonical backend view of supported chains
- environment-aware chain filtering
- no hard dependency on app-bundled chain support tables

It also gives the backend:

- one place to evolve chain support policy
- one public contract independent from internal execution config
