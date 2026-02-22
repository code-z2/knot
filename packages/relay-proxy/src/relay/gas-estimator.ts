import { createPublicClient, extractChain, http, type Chain, type StateOverride } from "viem";
import * as viemChains from "viem/chains";

import { BadRequestError } from "../errors";

import type { RelayTransactionRequestModel } from "./models";

type ViemChainExport = (typeof viemChains)[keyof typeof viemChains];

const ALL_KNOWN_CHAINS = Object.values(viemChains).filter(isChainDefinition) as Chain[];

export async function estimateRelayRequestGas(chainId: number, request: RelayTransactionRequestModel): Promise<bigint> {
  const chain = extractChain({ chains: ALL_KNOWN_CHAINS, id: chainId });
  if (!chain) {
    throw new BadRequestError(`Unsupported chain ${chainId} for gas estimation.`);
  }

  const client = createPublicClient({
    chain,
    transport: http(),
  });

  const stateOverride = buildStateOverride(request);

  try {
    return await client.estimateGas({
      account: request.from,
      to: request.to,
      data: request.data,
      value: request.value ? BigInt(request.value) : 0n,
      authorizationList: request.authorizationList,
      stateOverride,
    });
  } catch (error) {
    const reason = error instanceof Error ? error.message : "unknown gas estimation error";
    throw new BadRequestError(`Gas estimation failed for chain ${chainId}: ${reason}`);
  }
}

function buildStateOverride(request: RelayTransactionRequestModel): StateOverride | undefined {
  const delegateAddress = request.authorizationList?.[0]?.address;
  if (!delegateAddress) {
    return undefined;
  }

  // EIP-7702 delegation code form: 0xef0100 ++ delegate address.
  const delegationCode = `0xef0100${delegateAddress.slice(2)}` as const;
  return [{ address: request.from, code: delegationCode }];
}

function isChainDefinition(value: ViemChainExport): boolean {
  if (!value || typeof value !== "object") {
    return false;
  }
  return "id" in value && "rpcUrls" in value;
}
