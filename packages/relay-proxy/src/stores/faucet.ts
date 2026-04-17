import type { CloudflareBindings } from '@/types';

export function createFaucetStore(env: Pick<CloudflareBindings, 'AUTH_DB'>) {
    return {
        async hasConsumed(userId: string): Promise<boolean> {
            const row = await env.AUTH_DB.prepare(
                `select faucet_consumed as faucetConsumed
                 from users
                 where id = ?1
                   and status = 'active'`,
            )
                .bind(userId)
                .first<{ faucetConsumed: number }>();

            return row?.faucetConsumed === 1;
        },

        async consume(userId: string): Promise<boolean> {
            const result = await env.AUTH_DB.prepare(
                `update users
                 set faucet_consumed = 1
                 where id = ?1
                   and status = 'active'
                   and faucet_consumed = 0`,
            )
                .bind(userId)
                .run();

            return result.meta.changes === 1;
        },
    };
}
