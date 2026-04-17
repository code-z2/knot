/**
 * Gas service — manages the gas-tank financial lifecycle: exposure
 * gating, debt tracking, balance queries, on-chain USDC collection,
 * and cosigned withdrawals.
 *
 * ## Dual-state model
 *
 * Gas accounting is split across two storage layers to balance
 * consistency and throughput:
 *
 * - **Durable Object** (`GasAccountDurableObject`): Holds `pendingExposureUsdc`
 *   — the sum of all relay fees that have been reserved but not yet settled.
 *   The DO provides single-writer serialization per user, preventing
 *   concurrent relays from over-spending the balance.
 *
 * - **D1** (`gas_profiles`): Holds `outstandingDebtUsdc` — realized fees
 *   that were successfully relayed and are awaiting on-chain collection
 *   from the user’s GasTank contract.
 *
 * The `admitExposure` call is the critical gate: it atomically checks
 * `balance + overdraft - outstandingDebt - pendingExposure >= newQuote`
 * inside the DO. Only after this succeeds does the relay handler
 * proceed to submit UserOperations.
 *
 * @module
 */
import { erc20Abi, type Address, type Call } from 'viem';
import { formatUserOperationRequest } from 'viem/account-abstraction';

import { GAS_TANK_ABI } from '@/constants';
import { createGasProfileStore } from '@/stores/gas';
import type {
    BundlerClient,
    ChainEnvironment,
    CloudflareBindings,
    CreateAppOptions,
    GasClient,
    GasCollectionContext,
    GasProfileRecord,
    GasTankDebtMutationResult,
    GasTankDORecord,
    GasTankDORequestHandler,
} from '@/types';
import {
    encodeGasTankContractDeployment,
    encodeGasTankDebit,
    gasTankDORequestHandler,
    getGasChain,
    getWithdrawTypedData,
    predictGasTankAddress,
    uint,
} from '@/utils';

function createGasConfig(
    bundler: BundlerClient,
    requestHandler: GasTankDORequestHandler,
    environment: ChainEnvironment,
    treasury: Address,
) {
    return {
        bundler,
        requestHandler,
        environment,
        treasury,
    };
}

/**
 * Build the gas client — the public API surface for gas operations.
 *
 * Internally wires up the bundler client (for on-chain reads/writes),
 * the DO request handler (for exposure gating), and the treasury address
 * (destination for collected debt).
 */
function createGasRuntime(config: ReturnType<typeof createGasConfig>): GasClient {
    const { bundler, requestHandler: makeDORequest, environment, treasury } = config;

    const serverAccount = bundler.account;
    const publicClient = serverAccount.publicClient;

    const gasChain = getGasChain(environment);

    const ctx = (async (userId: Address, profileStore?: ReturnType<typeof createGasProfileStore>) => {
        const [balance, { pendingExposureUsdc }] = await Promise.all([getGasBalance(userId), getRecord(userId)]);
        const record = {
            pendingExposureUsdc: uint(pendingExposureUsdc),
            provider: getGasProvider(userId),
            balanceUsdc: uint(balance),
        };
        if (profileStore) {
            const gasProfile = await profileStore.getGasProfile(userId);
            return {
                ...record,
                gasProfile,
            };
        }
        return {
            ...record,
            gasProfile: null,
        };
    }) as {
        (
            userId: Address,
            profileStore: ReturnType<typeof createGasProfileStore>,
        ): Promise<GasCollectionContext<GasProfileRecord>>;
        (userId: Address, profileStore?: undefined): Promise<GasCollectionContext<null>>;
    };

    /**
     * Cosign a withdrawal request with the server key.
     *
     * The GasTank contract requires dual signatures (user + server)
     * to prevent unauthorized drains. The server only cosigns after
     * verifying the user has no outstanding debt.
     */
    const cosign = async (userId: Address, params: { amount: uint; deadline: number; to: Address }) => {
        const gasTankAddress = getGasTankAddress(userId);
        const nonce = await getGasWithdrawalNonce(userId);
        return serverAccount.signTypedData(
            getWithdrawTypedData(gasTankAddress, gasChain.id, {
                ...params,
                nonce,
            }),
        );
    };

    const getRecord = (userId: Address) => {
        return makeDORequest<GasTankDORecord>(userId, '/');
    };

    const getGasTankAddress = (userId: Address) => {
        return predictGasTankAddress(userId, serverAccount.address, config.environment);
    };

    const getGasProvider = (userId: Address) => {
        return {
            gasTankAddress: getGasTankAddress(userId),
            kind: 'knot' as const,
        };
    };

    const getGasBalance = async (userId: Address) => {
        return publicClient.readContract({
            abi: erc20Abi,
            address: gasChain.gelato.quoteToken,
            args: [getGasTankAddress(userId)],
            functionName: 'balanceOf',
        });
    };

    const getGasWithdrawalNonce = async (userId: Address) => {
        const gasTankAddress = getGasTankAddress(userId);
        const code = await publicClient.getCode({
            address: gasTankAddress,
        });

        if (!code) {
            return 0n;
        }

        return publicClient.readContract({
            abi: GAS_TANK_ABI,
            address: gasTankAddress,
            functionName: 'withdrawNonce',
        });
    };

    const admitExposure = (userId: Address, balance: uint, quote: uint) => {
        return makeDORequest<GasTankDORecord>(userId, '/admit', {
            method: 'POST',
            body: JSON.stringify({ balance: balance.hex, quote: quote.hex }),
        });
    };

    const decrementOutstandingDebt = (userId: string, amountUsdc: uint) => {
        return makeDORequest<GasTankDebtMutationResult>(userId, '/outstanding-debt/decrement', {
            method: 'POST',
            body: JSON.stringify(amountUsdc.hex),
        });
    };
    const decrementPendingExposure = (userId: string, amountUsdc: uint) => {
        return makeDORequest<GasTankDORecord>(userId, '/pending-exposure/decrement', {
            method: 'POST',
            body: JSON.stringify(amountUsdc.hex),
        });
    };

    const incrementOutstandingDebt = (userId: Address, amountUsdc: uint) => {
        return makeDORequest<GasTankDebtMutationResult>(userId, '/outstanding-debt/increment', {
            method: 'POST',
            body: JSON.stringify(amountUsdc.hex),
        });
    };
    const incrementPendingExposure = (userId: Address, amountUsdc: uint) => {
        return makeDORequest<GasTankDORecord>(userId, '/pending-exposure/increment', {
            method: 'POST',
            body: JSON.stringify(amountUsdc.hex),
        });
    };

    /**
     * Encode the on-chain calls needed to collect outstanding debt.
     *
     * If the user’s GasTank contract hasn’t been deployed yet (no code
     * at the predicted CREATE2 address), this prepends a deployment call
     * via CreateX before the `debit()` call. This lazy-deployment pattern
     * means users never need a separate "create gas tank" transaction.
     */
    const encodeDebitCall = async (userId: Address, amountUsdc: uint) => {
        const gasTankAddress = getGasTankAddress(userId);
        const code = await publicClient.getCode({
            address: gasTankAddress,
        });

        const calls: Call[] = [];
        if (!code) {
            const deployCall = encodeGasTankContractDeployment(
                userId,
                serverAccount.address,
                gasChain.gelato.quoteToken,
            );
            calls.push(deployCall);
        }

        const debitCall = encodeGasTankDebit(amountUsdc.value, config.treasury, gasTankAddress);
        calls.push(debitCall);
        return calls;
    };

    const submitDebitCalls = async (calls: readonly Call[]) => {
        const request = await config.bundler.prepareUserOperation({
            calls: [...calls],
            maxFeePerGas: 0n,
            maxPriorityFeePerGas: 0n,
            parameters: ['authorization', 'factory', 'gas', 'nonce', 'signature'],
        });

        const authorization = request.authorization
            ? {
                  authorization: await serverAccount.authorization.account.signAuthorization({
                      address: request.authorization.address,
                      chainId: request.authorization.chainId,
                      nonce: request.authorization.nonce,
                  }),
              }
            : {};

        const signature = await serverAccount.signUserOperation({
            ...request,
            ...authorization,
        });

        const operation = formatUserOperationRequest({
            ...request,
            ...authorization,
            signature,
        });

        const receipt = await config.bundler.sendUserOperationSync(operation, serverAccount.entryPoint.address);

        if (!receipt.success) {
            throw new Error('gas_tank_batch_submission_failed');
        }
    };

    return {
        ctx,
        encodeDebitCall,
        cosign,
        getGasBalance,
        getGasProvider,
        getGasTankAddress,
        getGasWithdrawalNonce,
        submitDebitCalls,
        getRecord,
        admitExposure,
        decrementOutstandingDebt,
        decrementPendingExposure,
        incrementOutstandingDebt,
        incrementPendingExposure,
    };
}

export function createGasClient(
    env: Pick<CloudflareBindings, 'GAS_TANK_DO' | 'TREASURY_ADDRESS'>,
    bundler: BundlerClient,
    options: Pick<CreateAppOptions, 'gasClient'>,
) {
    if (options.gasClient) {
        return options.gasClient;
    }
    const requestHandler = gasTankDORequestHandler(env);
    const config = createGasConfig(bundler, requestHandler, bundler.chain.environment, env.TREASURY_ADDRESS);
    return createGasRuntime(config);
}
