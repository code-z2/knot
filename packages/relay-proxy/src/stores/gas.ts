/**
 * Gas-tank persistence — two stores backed by different Cloudflare storage
 * primitives, chosen for their access patterns:
 *
 * - **GasProfileStore** (D1): Holds user gas profiles (overdraft settings,
 *   outstanding debt). Profiles are read/written transactionally per-user
 *   and benefit from SQL’s upsert semantics.
 *
 * - **GasUsageStore** (KV): Holds daily spend buckets keyed by
 *   `gas-usage:{userId}:{YYYY-MM-DD}`. KV is ideal here because usage
 *   data is append-heavy, naturally TTL’d, and queried by sequential
 *   date range scans. Testnet usage is intentionally not persisted
 *   to avoid polluting mainnet spend analytics.
 *
 * @module
 */
import { GAS_USAGE_KEY_PREFIX, GAS_USAGE_TTL_SECONDS } from '@/constants';
import type { CloudflareBindings, GasProfileRecord, GasUsageBucketRecord, GasWindow } from '@/types';
import {
    createDefaultGasProfile,
    emptyUsageBucket,
    getGasWindowDays,
    getUtcDateBucket,
    incrementBucket,
    isTestnetChainId,
    objectEntries,
    parseJsonRecord,
    uint,
} from '@/utils';
import { Hex } from 'viem';

/**
 * D1-backed store for gas profile records (overdraft state, debt).
 *
 * Every user has at most one profile row. Missing rows return a
 * zero-valued default so callers never need null checks beyond
 * the initial query.
 */
export function createGasProfileStore(env: Pick<CloudflareBindings, 'GAS_TANK_DB'>) {
    return {
        async getGasProfile(userId: string): Promise<GasProfileRecord> {
            const result = await env.GAS_TANK_DB.prepare(
                `select
                    user_id as userId,
                    minimum_allowed_usdc as minimumAllowedUsdc,
                    overdraft_eligible as overdraftEligible,
                    overdraft_enabled as overdraftEnabled,
                    overdraft_locked as overdraftLocked,
                    overdraft_outstanding_usdc as overdraftOutstandingUsdc,
                    outstanding_debt_usdc as outstandingDebtUsdc,
                    updated_at as updatedAt
                 from gas_profiles
                 where user_id = ?1`,
            )
                .bind(userId)
                .first<{
                    minimumAllowedUsdc: Hex;
                    overdraftEligible: number;
                    overdraftEnabled: number;
                    overdraftLocked: number;
                    overdraftOutstandingUsdc: Hex;
                    outstandingDebtUsdc: Hex;
                    updatedAt: number;
                    userId: string;
                }>();

            if (!result) {
                return createDefaultGasProfile(userId);
            }

            return {
                ...result,
                overdraftOutstandingUsdc: uint(result.overdraftOutstandingUsdc),
                outstandingDebtUsdc: uint(result.outstandingDebtUsdc),
                minimumAllowedUsdc: uint(result.minimumAllowedUsdc),
                overdraftEligible: result.overdraftEligible === 1,
                overdraftEnabled: result.overdraftEnabled === 1,
                overdraftLocked: result.overdraftLocked === 1,
            };
        },

        async updateGasProfile(profile: GasProfileRecord): Promise<GasProfileRecord> {
            await env.GAS_TANK_DB.prepare(
                `insert into gas_profiles (
                    user_id,
                    minimum_allowed_usdc,
                    overdraft_eligible,
                    overdraft_enabled,
                    overdraft_locked,
                    overdraft_outstanding_usdc,
                    outstanding_debt_usdc,
                    updated_at
                 ) values (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8)
                 on conflict(user_id) do update set
                    minimum_allowed_usdc = excluded.minimum_allowed_usdc,
                    overdraft_eligible = excluded.overdraft_eligible,
                    overdraft_enabled = excluded.overdraft_enabled,
                    overdraft_locked = excluded.overdraft_locked,
                    overdraft_outstanding_usdc = excluded.overdraft_outstanding_usdc,
                    outstanding_debt_usdc = excluded.outstanding_debt_usdc,
                    updated_at = excluded.updated_at`,
            )
                .bind(
                    profile.userId,
                    profile.minimumAllowedUsdc.hex,
                    Number(profile.overdraftEligible),
                    Number(profile.overdraftEnabled),
                    Number(profile.overdraftLocked),
                    profile.overdraftOutstandingUsdc.hex,
                    profile.outstandingDebtUsdc.hex,
                    profile.updatedAt,
                )
                .run();

            return profile;
        },
    };
}

/**
 * KV-backed store for daily gas-usage buckets.
 *
 * Each bucket is a single KV entry containing per-chain USDC totals
 * for one calendar day. Buckets auto-expire via KV TTL, so no
 * explicit cleanup is needed. History queries scan backwards from
 * today by the requested window size (3m, 6m, 1y).
 */
export function createGasUsageStore(env: Pick<CloudflareBindings, 'GAS_USAGE_KV'>) {
    return {
        async getBucket(userId: string, bucket: string): Promise<GasUsageBucketRecord | null> {
            const raw = await env.GAS_USAGE_KV.get(`${GAS_USAGE_KEY_PREFIX}${userId}:${bucket}`);
            return parseJsonRecord<GasUsageBucketRecord>(raw);
        },

        async getUsageHistory(userId: string, window: GasWindow, now = Date.now()) {
            const days = getGasWindowDays(window);
            const aggregate = emptyUsageBucket();

            for (let offset = 0; offset < days; offset += 1) {
                const bucket = await this.getBucket(userId, getUtcDateBucket(now, offset));

                if (!bucket) {
                    continue;
                }

                aggregate.totalUsdc = uint.add(aggregate.totalUsdc, bucket.totalUsdc);
                aggregate.updatedAt = aggregate.updatedAt > bucket.updatedAt ? aggregate.updatedAt : bucket.updatedAt;

                for (const [chainId, amount] of objectEntries(bucket.chains)) {
                    aggregate.chains[chainId] = uint.add(aggregate.chains[chainId] ?? uint.zero, amount);
                }
            }

            return aggregate;
        },

        async incrementUsage(
            userId: string,
            chainId: number,
            amountUsdc: uint,
            now = Date.now(),
            ttlSeconds = GAS_USAGE_TTL_SECONDS,
        ): Promise<GasUsageBucketRecord> {
            const bucket = getUtcDateBucket(now);
            const current = (await this.getBucket(userId, bucket)) ?? emptyUsageBucket();
            const next = incrementBucket(current, chainId, amountUsdc, new Date(now).toISOString());
            if (isTestnetChainId(chainId)) {
                // Testnet usage is computed in-memory but never persisted,
                // keeping production KV clean for billing analytics.
                return next;
            }
            await env.GAS_USAGE_KV.put(`${GAS_USAGE_KEY_PREFIX}${userId}:${bucket}`, JSON.stringify(next), {
                expirationTtl: ttlSeconds,
            });

            return next;
        },
    };
}
