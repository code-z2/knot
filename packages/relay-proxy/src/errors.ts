import type { PaymentOptionModel, SupportMode } from "./relay/models";

export class BadRequestError extends Error {}

export class AuthError extends Error {}

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

  constructor(input: {
    account: string;
    supportMode: SupportMode;
    estimatedDebitWei: bigint;
    balanceWei: bigint;
    postDebitWei: bigint;
    minimumAllowedWei: bigint;
    requiredTopUpWei: bigint;
    suggestedTopUpWei: bigint;
    paymentOptions: PaymentOptionModel[];
  }) {
    super("payment_required");
    this.account = input.account;
    this.supportMode = input.supportMode;
    this.estimatedDebitWei = input.estimatedDebitWei;
    this.balanceWei = input.balanceWei;
    this.postDebitWei = input.postDebitWei;
    this.minimumAllowedWei = input.minimumAllowedWei;
    this.requiredTopUpWei = input.requiredTopUpWei;
    this.suggestedTopUpWei = input.suggestedTopUpWei;
    this.paymentOptions = input.paymentOptions;
  }
}
