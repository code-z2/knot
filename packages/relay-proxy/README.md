# Relay Proxy (Cloudflare Worker)

Gelato relay proxy with KV-backed gas tank accounting for iOS clients.

## API

### `POST /v1/relay/submit`

Request:

```json
{
  "account": "0x...",
  "supportMode": "LIMITED_TESTNET",
  "immediateTxs": [
    {
      "chainId": 8453,
      "supportMode": "LIMITED_MAINNET",
      "request": { "from": "0x...", "to": "0x...", "data": "0x..." }
    }
  ],
  "backgroundTxs": [
    { "chainId": 42161, "request": { "from": "0x...", "to": "0x...", "data": "0x..." } }
  ],
  "deferredTxs": [
    { "chainId": 42161, "request": { "from": "0x...", "to": "0x...", "data": "0x..." } }
  ],
  "paymentOptions": [
    { "chainId": 8453, "tokenAddress": "0x...", "symbol": "USDC", "amount": "10" }
  ]
}
```

Per-transaction `supportMode` is optional. If omitted, the top-level `supportMode` is used.

Behavior:
- Estimates gas per tx via viem public-client simulation (`eth_estimateGas`)
- Quotes all txs via `relayer_getFeeQuote` using only `{ chainId, gas, token }`
- Fee quote token policy:
  - mainnet mode tx: `0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48` (USDC)
  - testnet mode tx: `0x0000000000000000000000000000000000000000` (native)
- Debits gas tank in USDC units
- Sends `immediateTxs` with `relayer_sendTransactionSync`
- Sends `backgroundTxs` with `relayer_sendTransaction`
- Stores `deferredTxs` in KV for later trigger

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

### `GET /v1/relay/status?id=...&supportMode=...`

Proxies `relayer_getStatus`.

### `GET /v1/relay/credit?account=...&supportMode=...`

Returns current gas tank balance for the account/mode bucket.

### `POST /v1/faucet/fund`

Best-effort testnet faucet trigger for a wallet address.

Request:

```json
{
  "eoaAddress": "0x...",
  "supportMode": "LIMITED_TESTNET"
}
```

Response statuses:
- `202 Accepted` with `{ "ok": true, "status": "funding_initiated" }`
- `202 Accepted` with `{ "ok": true, "status": "funding_pending" }`
- `200 OK` with `{ "ok": true, "status": "already_funded" }`
- `200 OK` with `{ "ok": true, "status": "skipped_non_testnet" }` for non-testnet modes

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
- `GELATO_MAINNET_API_KEY`
- `GELATO_TESTNET_API_KEY`
- `GAS_TANK_KV` (Wrangler KV binding)
- `PINATA_JWT`
- `PINATA_GATEWAY_BASE_URL`
- `PINATA_GROUP_ID`

Optional:
- `RELAY_AUTH_HMAC_SECRET`
- `GELATO_SYNC_TIMEOUT_MS` (wait timeout for `immediateTxs`)
- `FAUCET_FUNDING_KV` (Wrangler KV binding; falls back to `GAS_TANK_KV` if omitted)
- `PINATA_SIGN_EXPIRES_SECONDS`
- `PINATA_MAX_FILE_SIZE_BYTES`
- `PINATA_GROUP_FIELD` (`group_id` or `group`, default: `group_id`)
- `FAUCET_PRIVATE_KEY`
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
wrangler secret put GELATO_MAINNET_API_KEY
wrangler secret put GELATO_TESTNET_API_KEY
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
2. Validate payload shape (`account`, `supportMode`, `immediateTxs`, `backgroundTxs`, `deferredTxs`).
3. Validate each transaction `request.from` and any EIP-7702 `authorizationList` signer against `account`.
4. Simulate gas for relay-now txs (`immediateTxs + backgroundTxs`) via viem `eth_estimateGas`.
5. Quote relay-now txs through Gelato `relayer_getFeeQuote` with `{ chainId, gas, token }`.
6. Read KV gas-tank balance for `gas-tank:<mode>:<account>`.
7. Enforce mode floor (`LIMITED_*` can go negative by configured floor).
8. Debit estimated total from KV.
9. Submit all `immediateTxs` with `relayer_sendTransactionSync`.
10. Submit all `backgroundTxs` with `relayer_sendTransaction`.
11. Persist all `deferredTxs` in KV and return IDs + accounting summary.

`POST /v1/images/direct-upload` processing order:
1. Verify bearer token (+ optional HMAC header).
2. Validate upload request (`eoaAddress`, `fileName`, `contentType`).
3. Request signed upload URL from Pinata (`/v3/files/sign`).
4. Return signed URL + gateway base URL to the iOS client.

`POST /v1/faucet/fund` processing order:
1. Verify bearer token (+ optional HMAC header).
2. Validate faucet payload (`eoaAddress`, `supportMode`).
3. For `LIMITED_TESTNET`, check KV key `faucet-funded:<mode>:<account>`.
4. If funded/pending, return immediately without resubmitting transfers.
5. If not funded, mark pending and queue testnet funding on Sepolia/Base Sepolia/Arbitrum Sepolia.
6. On success, persist funded marker in KV. On failure, clear pending marker.

## Local Dev

```bash
cd packages/relay-proxy
bun install
bun run dev
```
