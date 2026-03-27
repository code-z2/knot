import type { PaymentOptionModel, SupportMode } from './types';

export class BadRequestError extends Error {}

export class AuthError extends Error {}

export interface PaymentRequiredContext {
    account: string;
    supportMode: SupportMode;
    estimatedDebitWei: bigint;
    balanceWei: bigint;
    postDebitWei: bigint;
    minimumAllowedWei: bigint;
    requiredTopUpWei: bigint;
    suggestedTopUpWei: bigint;
    paymentOptions: PaymentOptionModel[];
}

export class PaymentRequiredError extends Error {
    readonly account: string;
    readonly supportMode: SupportMode;
    readonly estimatedDebitWei: bigint;
    readonly balanceWei: bigint;
    readonly postDebitWei: bigint;
    readonly minimumAllowedWei: bigint;
    readonly requiredTopUpWei: bigint;
    readonly suggestedTopUpWei: bigint;
    readonly paymentOptions: PaymentOptionModel[];

    constructor(ctx: PaymentRequiredContext) {
        super('payment_required');
        this.account = ctx.account;
        this.supportMode = ctx.supportMode;
        this.estimatedDebitWei = ctx.estimatedDebitWei;
        this.balanceWei = ctx.balanceWei;
        this.postDebitWei = ctx.postDebitWei;
        this.minimumAllowedWei = ctx.minimumAllowedWei;
        this.requiredTopUpWei = ctx.requiredTopUpWei;
        this.suggestedTopUpWei = ctx.suggestedTopUpWei;
        this.paymentOptions = ctx.paymentOptions;
    }
}
