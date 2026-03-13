/**
 * Application-wide constants. Single source of truth.
 * Domain-specific constants (ABIs, chain lists) live in their respective modules.
 */
import type { Address } from 'viem';

import type { SupportMode } from './types';

export const SUPPORT_MODES: ReadonlySet<SupportMode> = new Set<SupportMode>([
    'testnet',
    'mainnet',
]);

// ---------------------------------------------------------------------------
// Faucet
// ---------------------------------------------------------------------------

export const ETH_DRIP_WEI = 10_000_000_000_000_000n; // 0.01 ETH
export const USDC_DRIP_AMOUNT = 2_000_000n; // 2 USDC (6 decimals)

export const TESTNET_USDC_BY_CHAIN: Readonly<Record<number, Address>> = {
    11155111: '0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238', // Sepolia
    84532: '0x036CbD53842c5426634e7929541eC2318f3dCF7e', // Base Sepolia
    421614: '0x75faf114eafb1BDbe2F0316DF893fd58CE46AA4d', // Arbitrum Sepolia
};

// ---------------------------------------------------------------------------
// TTLs
// ---------------------------------------------------------------------------

export const FAUCET_PENDING_TTL_SECONDS = 600; // 10 minutes
export const FAUCET_FUNDED_TTL_SECONDS = 31_536_000; // 1 year
export const DEFERRED_TX_TTL_SECONDS = 2_592_000; // 30 days
export const DEFERRED_DISPATCHED_TTL_SECONDS = 86_400; // 1 day (for status polling after dispatch)

// ---------------------------------------------------------------------------
// Sweeper
// ---------------------------------------------------------------------------

export const STUCK_THRESHOLD_MS = 15 * 60 * 1000; // 15 minutes
export const DEFERRED_TTL_WARNING_DAYS = 7; // Alert when intent age exceeds this

// ---------------------------------------------------------------------------
// Retry
// ---------------------------------------------------------------------------

export const TRACKER_DECREMENT_MAX_ATTEMPTS = 3;
export const TRACKER_DECREMENT_BASE_DELAY_MS = 500;

// ---------------------------------------------------------------------------
// HTTP
// ---------------------------------------------------------------------------

export const JSON_HEADERS: Readonly<Record<string, string>> = {
    'content-type': 'application/json; charset=utf-8',
    'cache-control': 'no-store',
};
