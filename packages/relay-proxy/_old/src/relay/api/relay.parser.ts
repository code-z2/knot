/**
 * HTTP request boundary parsing for relay submissions.
 * Validates untrusted JSON input into typed models.
 */
import type { Address, Hex } from 'viem';
import { recoverAuthorizationAddress } from 'viem/utils';

import { BadRequestError } from '../../shared/errors';
import {
    assertAddress,
    assertHex,
    assertObject,
    assertPositiveInteger,
    assertSupportMode,
    assertUnsignedInteger,
    normalizeAddress,
} from '../../shared/validation';

import type {
    RelayAuthorizationModel,
    RelayTransactionRequestModel,
    RelayTxEnvelopeModel,
    SubmitRelayRequestModel,
} from '../types';
import type { PaymentOptionModel, SupportMode } from '../../shared/types';

/**
 * Parses and validates a raw JSON string into a SubmitRelayRequestModel.
 * @throws BadRequestError if any field is missing or malformed.
 */
export function parseSubmitRequest(rawBody: string): SubmitRelayRequestModel {
    let parsed: unknown;
    try {
        parsed = JSON.parse(rawBody);
    } catch {
        throw new BadRequestError('Invalid JSON body.');
    }

    const payload = assertObject(parsed, 'Invalid relay request payload');
    const account = assertAddress(payload.account, 'Invalid account address') as string;
    const supportMode = assertSupportMode(payload.supportMode, 'Invalid supportMode');

    return {
        account,
        supportMode,
        immediateTxs: parseTxEnvelopeList(payload.immediateTxs, 'immediateTxs'),
        backgroundTxs: parseTxEnvelopeList(payload.backgroundTxs, 'backgroundTxs'),
        deferredTxs: parseTxEnvelopeList(payload.deferredTxs, 'deferredTxs'),
        paymentOptions: parsePaymentOptions(payload.paymentOptions),
    };
}

/**
 * Verifies that tx.request.from and all authorizationList signatures belong to account.
 * @throws BadRequestError on mismatch.
 */
export async function assertRelayTransactionsMatchAccount(
    account: string,
    txs: readonly RelayTxEnvelopeModel[],
): Promise<void> {
    for (const tx of txs) {
        if (tx.request.from !== account) {
            throw new BadRequestError(`Relay tx account mismatch for chain ${tx.chainId}.`);
        }

        for (const [index, auth] of (tx.request.authorizationList ?? []).entries()) {
            if (auth.chainId !== tx.chainId) {
                throw new BadRequestError(
                    `request.authorizationList[${index}].chainId must match relay chain ${tx.chainId}.`,
                );
            }

            const recoveredAuthority = await recoverAuthAddress(auth, index);
            if (recoveredAuthority !== account) {
                throw new BadRequestError(
                    `request.authorizationList[${index}] signer mismatch for chain ${tx.chainId}.`,
                );
            }
        }
    }
}

/** Returns a shallow copy of payment options. */
export function sanitizePaymentOptions(
    options: readonly PaymentOptionModel[],
): PaymentOptionModel[] {
    return [...options];
}

// ---------------------------------------------------------------------------
// Compound Parsers (system boundary validation)
// ---------------------------------------------------------------------------

async function recoverAuthAddress(auth: RelayAuthorizationModel, index: number): Promise<string> {
    try {
        return normalizeAddress(await recoverAuthorizationAddress({ authorization: auth }));
    } catch {
        throw new BadRequestError(
            `request.authorizationList[${index}] has an invalid EIP-7702 signature.`,
        );
    }
}

function parseTxEnvelopeList(value: unknown, fieldName: string): RelayTxEnvelopeModel[] {
    if (!Array.isArray(value)) {
        throw new BadRequestError(`${fieldName} must be an array.`);
    }
    return value.map((item) => parseTxEnvelope(item, fieldName));
}

function parseTxEnvelope(value: unknown, fieldName: string): RelayTxEnvelopeModel {
    const item = assertObject(value, `Invalid relay tx envelope in ${fieldName}`);
    const chainId = assertPositiveInteger(item.chainId, `Invalid chainId in ${fieldName}`);

    let supportMode: SupportMode | undefined;
    if (item.supportMode !== undefined) {
        supportMode = assertSupportMode(item.supportMode, `Invalid supportMode in ${fieldName}`);
    }

    return {
        chainId,
        supportMode,
        request: parseTxRequest(item.request, chainId, fieldName),
    };
}

function parseTxRequest(
    value: unknown,
    chainId: number,
    fieldName: string,
): RelayTransactionRequestModel {
    const request = assertObject(value, `Missing request object in ${fieldName}`);
    const from = assertAddress(
        request.from,
        `Invalid request.from for chain ${chainId}`,
    ) as Address;
    const to = assertAddress(request.to, `Invalid request.to for chain ${chainId}`) as Address;
    const data = assertHex(request.data, `Invalid request.data for chain ${chainId}`);

    const out: RelayTransactionRequestModel = { from, to, data };

    if (request.value !== undefined) {
        out.value = assertHex(request.value, `Invalid request.value for chain ${chainId}`);
    }

    const authList = parseAuthorizationList(request.authorizationList, chainId);
    if (authList.length > 0) {
        out.authorizationList = authList;
    }

    return out;
}

function parseAuthorizationList(value: unknown, chainId: number): RelayAuthorizationModel[] {
    if (value === undefined) return [];
    if (!Array.isArray(value)) {
        throw new BadRequestError(`Invalid request.authorizationList for chain ${chainId}.`);
    }

    return value.map((item, index) => {
        const auth = assertObject(item, `Invalid authorizationList[${index}] for chain ${chainId}`);
        const yParityRaw = assertUnsignedInteger(
            auth.yParity,
            `Invalid authorizationList[${index}].yParity for chain ${chainId}`,
        );

        let yParity: 0 | 1;
        if (yParityRaw === 0 || yParityRaw === 1) {
            yParity = yParityRaw;
        } else if (yParityRaw === 27 || yParityRaw === 28) {
            yParity = (yParityRaw - 27) as 0 | 1;
        } else {
            throw new BadRequestError(
                `Invalid authorizationList[${index}].yParity for chain ${chainId}.`,
            );
        }

        return {
            address: assertAddress(
                auth.address,
                `Invalid authorizationList[${index}].address for chain ${chainId}`,
            ) as Address,
            chainId: assertPositiveInteger(
                auth.chainId,
                `Invalid authorizationList[${index}].chainId for chain ${chainId}`,
            ),
            nonce: assertUnsignedInteger(
                auth.nonce,
                `Invalid authorizationList[${index}].nonce for chain ${chainId}`,
            ),
            r: assertHex(auth.r, `Invalid authorizationList[${index}].r for chain ${chainId}`),
            s: assertHex(auth.s, `Invalid authorizationList[${index}].s for chain ${chainId}`),
            yParity,
        };
    });
}

function parsePaymentOptions(value: unknown): PaymentOptionModel[] {
    if (value === undefined) return [];
    if (!Array.isArray(value)) {
        throw new BadRequestError('paymentOptions must be an array.');
    }

    return value.map((item, index) => {
        const option = assertObject(item, `Invalid paymentOptions[${index}]`);

        const symbol = typeof option.symbol === 'string' ? option.symbol.trim() : '';
        if (!symbol) throw new BadRequestError(`Invalid paymentOptions[${index}].symbol.`);

        const amountRaw =
            typeof option.amount === 'string' || typeof option.amount === 'number'
                ? String(option.amount).trim()
                : '';
        const amountNum = Number(amountRaw);
        if (!Number.isFinite(amountNum) || amountNum <= 0) {
            throw new BadRequestError(`Invalid paymentOptions[${index}].amount.`);
        }

        return {
            chainId: assertPositiveInteger(
                option.chainId,
                `Invalid paymentOptions[${index}].chainId`,
            ),
            tokenAddress: assertAddress(
                option.tokenAddress,
                `Invalid paymentOptions[${index}].tokenAddress`,
            ) as Address,
            symbol,
            amount: amountRaw,
        };
    });
}
