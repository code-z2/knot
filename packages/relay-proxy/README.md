# Relay Proxy (Cloudflare Worker)

Gelato relay proxy with KV-backed gas tank accounting for iOS clients.

## API

### `POST /v1/relay/submit`

Request:

```json
{
  "account": "0x...",
  "supportMode": "LIMITED_TESTNET",
  "priorityTxs": [
    { "chainId": 8453, "request": { "from": "0x...", "to": "0x...", "data": "0x..." } }
  ],
  "txs": [
    { "chainId": 42161, "request": { "from": "0x...", "to": "0x...", "data": "0x..." } }
  ],
  "paymentOptions": [
    { "chainId": 8453, "tokenAddress": "0x...", "symbol": "USDC", "amount": "10" }
  ]
}
```

Behavior:
- Quotes all txs via `relayer_getFeeQuote`
- Debits gas tank in USDC units
- Sends `priorityTxs` with `relayer_sendTransactionSync`
- Sends `txs` with `relayer_sendTransaction`

On insufficient credit/floor breach, returns `402 payment_required`.

### `POST /v1/images/direct-upload`

Creates a Pinata signed upload URL for client-side avatar uploads.

Request:

```json
{
  "eoaAddress": "0x...",
  "fileName": "avatar-uuid.jpg",
  "contentType": "image/jpeg"
}
```

Response:

```json
{
  "ok": true,
  "uploadURL": "https://uploads.pinata.cloud/v3/files?...",
  "imageID": "avatars/0x.../20260212T....-avatar-uuid.jpg",
  "gatewayBaseURL": "https://<your-pinata-gateway-host>/ipfs/"
}
```

### `GET /v1/relay/status?chainId=...&id=...`

Proxies `relayer_getStatus`.

### `GET /v1/relay/credit?account=...&supportMode=...`

Returns current gas tank balance for the account/mode bucket.

### `POST /v1/faucet/fund`

Best-effort testnet faucet trigger for a wallet address.

Request:

```json
{
  "eoaAddress": "0x..."
}
```

Response: `202 Accepted` with `{ "ok": true, "status": "funding_initiated" }`.

## Auth

Headers:
- `Authorization: Bearer <token>`
- `X-Relay-Timestamp: <unix-seconds>`
- `X-Relay-Signature: <hex(hmac_sha256(secret, timestamp + "." + rawBody))>`

If `RELAY_AUTH_HMAC_SECRET` is empty, only Bearer auth is enforced.

## KV Accounting Model

Balance key format:
- `gas-tank:<SUPPORT_MODE>:<lowercased_account>`

Each support mode has separate accounting bucket:
- `LIMITED_TESTNET`
- `LIMITED_MAINNET`
- `FULL_MAINNET`

Defaults:
- Initial credit: `2 USDC`
- Floors:
  - limited testnet: `-10`
  - limited mainnet: `-2`
  - full mainnet: `0`

## Env Vars

Required:
- `RELAY_AUTH_TOKEN`
- `GELATO_API_KEY`
- `GAS_TANK_KV` (Wrangler KV binding)
- `PINATA_JWT`
- `PINATA_GATEWAY_BASE_URL`
- `PINATA_GROUP_ID`

Optional:
- `RELAY_AUTH_HMAC_SECRET`
- `GELATO_RPC_TEMPLATE`
- `PINATA_SIGN_EXPIRES_SECONDS`
- `PINATA_MAX_FILE_SIZE_BYTES`
- `PINATA_GROUP_FIELD` (`group_id` or `group`, default: `group_id`)
- `FAUCET_PRIVATE_KEY`
- `FAUCET_RPC_SEPOLIA`
- `FAUCET_RPC_BASE_SEPOLIA`
- `FAUCET_RPC_ARB_SEPOLIA`
- `INITIAL_CREDIT_USDC`
- `FLOOR_LIMITED_TESTNET_USDC`
- `FLOOR_LIMITED_MAINNET_USDC`
- `FLOOR_FULL_MAINNET_USDC`
- `USDC_DECIMALS`

## Deploy (Cloudflare Workers)

1. Create KV namespace:
```bash
wrangler kv namespace create GAS_TANK_KV
```
2. Set the returned namespace id in `wrangler.toml` under `[[kv_namespaces]]`.
3. Set required secrets:
```bash
wrangler secret put RELAY_AUTH_TOKEN
wrangler secret put GELATO_API_KEY
wrangler secret put PINATA_JWT
wrangler secret put FAUCET_PRIVATE_KEY
```
4. Optional hardening secrets:
```bash
wrangler secret put RELAY_AUTH_HMAC_SECRET
```
5. Deploy:
```bash
wrangler deploy
```

## Request Flow

`POST /v1/relay/submit` processing order:
1. Verify bearer token (+ optional HMAC header).
2. Validate payload shape (`account`, `supportMode`, `priorityTxs`, `txs`).
3. Detect per-chain initialization requirement (`eth_getCode`) and mark exactly one valid initialize tx as free when needed.
4. Quote only billable txs through Gelato `relayer_getFeeQuote`.
   On already-initialized chains, auth-bearing transactions are allowed and billed normally.
5. Read KV gas-tank balance for `gas-tank:<mode>:<account>`.
6. Enforce mode floor (`LIMITED_*` can go negative by configured floor).
7. Debit estimated total from KV.
8. Submit all `priorityTxs` with `relayer_sendTransactionSync`.
9. Submit all remaining `txs` with `relayer_sendTransaction`.
10. Return relay task IDs + accounting summary.

`POST /v1/images/direct-upload` processing order:
1. Verify bearer token (+ optional HMAC header).
2. Validate upload request (`eoaAddress`, `fileName`, `contentType`).
3. Request signed upload URL from Pinata (`/v3/files/sign`).
4. Return signed URL + gateway base URL to the iOS client.

`POST /v1/faucet/fund` processing order:
1. Verify bearer token (+ optional HMAC header).
2. Validate faucet payload (`eoaAddress`).
3. Queue testnet funding on configured chains (Sepolia, Base Sepolia, Arbitrum Sepolia).
4. Return `202` immediately.

## Local Dev

```bash
cd packages/relay-proxy
bun install
bun run dev
```
