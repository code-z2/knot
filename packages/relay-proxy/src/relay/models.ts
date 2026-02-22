import type { Address, Hex } from "viem";

export interface Env {
  GAS_TANK_KV: KVNamespace;
  FAUCET_FUNDING_KV?: KVNamespace;
  FAUCET_TRACKER_DO?: DurableObjectNamespace;
  RELAY_AUTH_TOKEN: string;
  RELAY_AUTH_HMAC_SECRET?: string;
  GELATO_MAINNET_API_KEY?: string;
  GELATO_TESTNET_API_KEY?: string;
  PINATA_JWT: string;
  PINATA_GATEWAY_BASE_URL: string;
  PINATA_GROUP_ID: string;
  PINATA_SIGN_EXPIRES_SECONDS?: string;
  PINATA_MAX_FILE_SIZE_BYTES?: string;
  GELATO_SYNC_TIMEOUT_MS?: string;
  INITIAL_CREDIT_NATIVE?: string;
  FLOOR_LIMITED_TESTNET_NATIVE?: string;
  FLOOR_LIMITED_MAINNET_NATIVE?: string;
  FLOOR_FULL_MAINNET_NATIVE?: string;
  FAUCET_PRIVATE_KEY?: string;
}

export type SupportMode = "LIMITED_TESTNET" | "LIMITED_MAINNET" | "FULL_MAINNET";

export type HexQuantity = Hex;
export type RelayYParity = 0 | 1;

export interface RelayAuthorizationModel {
  address: Address;
  chainId: number;
  nonce: number;
  r: Hex;
  s: Hex;
  yParity: RelayYParity;
}

export interface RelayTransactionRequestModel {
  from: Address;
  to: Address;
  data: Hex;
  value?: HexQuantity;
  authorizationList?: readonly RelayAuthorizationModel[];
}

export interface RelayTxEnvelopeModel {
  chainId: number;
  supportMode?: SupportMode;
  request: RelayTransactionRequestModel;
}

export interface PaymentOptionModel {
  chainId: number;
  tokenAddress: Address;
  symbol: string;
  amount: string;
}

export interface SubmitRelayRequestModel {
  account: string;
  supportMode: SupportMode;
  immediateTxs: RelayTxEnvelopeModel[];
  backgroundTxs: RelayTxEnvelopeModel[];
  deferredTxs: RelayTxEnvelopeModel[];
  paymentOptions?: PaymentOptionModel[];
}

export interface RelaySubmissionModel {
  id: string;
  transactionHash?: string;
}

export interface RelayStatusModel {
  id: string;
  rawStatus: string;
  state: string;
  transactionHash?: string;
  blockNumber?: string;
  failureReason?: string;
}

export interface TankStateModel {
  balanceWei: bigint;
  initialized: boolean;
}

export interface DirectUploadRequestModel {
  eoaAddress: string;
  fileName: string;
  contentType: string;
}

export interface NormalizedDirectUploadRequestModel {
  eoaAddress: string;
  fileName: string;
  contentType: string;
  imageID: string;
}

export interface FaucetFundRequestModel {
  eoaAddress: string;
  supportMode: SupportMode;
}
