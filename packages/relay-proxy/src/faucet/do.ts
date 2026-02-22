import { DurableObject } from "cloudflare:workers";
import {
  createWalletClient,
  encodeFunctionData,
  getAddress,
  http,
  publicActions,
  type Address,
  type Chain,
  type Hex,
} from "viem";
import { privateKeyToAccount } from "viem/accounts";
import { arbitrumSepolia, baseSepolia, sepolia } from "viem/chains";

import {
  ERC20_TRANSFER_ABI,
  ETH_DRIP_WEI,
  TESTNET_USDC_BY_CHAIN,
  USDC_DRIP_AMOUNT,
} from "../constants";
import { BadRequestError } from "../errors";
import type { Env } from "../relay/models";
import { jsonResponse } from "../utils";

const FAUCET_CHAINS: readonly Chain[] = [sepolia, baseSepolia, arbitrumSepolia];

export class FaucetTracker extends DurableObject<Env> {
  async fetch(request: Request): Promise<Response> {
    const url = new URL(request.url);

    if (request.method !== "POST" || url.pathname !== "/fund") {
      return jsonResponse({ ok: false, error: "not_found" }, 404);
    }

    let payload: { recipientAddress: string };
    try {
      payload = (await request.json()) as { recipientAddress: string };
    } catch {
      return jsonResponse({ ok: false, error: "invalid_json" }, 400);
    }

    if (!payload.recipientAddress) {
      return jsonResponse({ ok: false, error: "missing_recipient" }, 400);
    }

    const faucetPrivateKey = this.normalizePrivateKey(this.env.FAUCET_PRIVATE_KEY ?? "");
    const faucetAccount = privateKeyToAccount(faucetPrivateKey);
    
    // Process all chains sequentially to avoid nonce collisions
    await this.fundAccount(payload.recipientAddress, faucetAccount);

    return jsonResponse({ ok: true, status: "funded" });
  }

  private async fundAccount(
    recipientAddress: string,
    faucetAccount: ReturnType<typeof privateKeyToAccount>
  ): Promise<void> {
    const recipient = getAddress(recipientAddress);

    for (const chain of FAUCET_CHAINS) {
      await this.fundOnChainSafe(chain, faucetAccount, recipient);
    }
  }

  private async fundOnChainSafe(
    chain: Chain,
    account: ReturnType<typeof privateKeyToAccount>,
    recipient: Address
  ): Promise<void> {
    try {
      await this.fundOnChain(chain, account, recipient);
    } catch (error) {
      const reason = error instanceof Error ? error.message : "unknown chain funding error";
      console.error(`faucet chain ${chain.id} failed`, reason);
    }
  }

  private async fundOnChain(
    chain: Chain,
    account: ReturnType<typeof privateKeyToAccount>,
    recipient: Address
  ): Promise<void> {
    const client = createWalletClient({
      account,
      chain,
      transport: http(),
    }).extend(publicActions);

    const usdcAddress = TESTNET_USDC_BY_CHAIN[chain.id];

    if (usdcAddress) {
      try {
        const usdcCalldata = encodeFunctionData({
          abi: ERC20_TRANSFER_ABI,
          functionName: "transfer",
          args: [recipient, USDC_DRIP_AMOUNT],
        });
        const usdcHash = await client.sendTransaction({
          to: usdcAddress,
          data: usdcCalldata,
        });
        console.log(`faucet chain ${chain.id} usdc tx ${usdcHash}`);
      } catch (error) {
        const reason = error instanceof Error ? error.message : "unknown usdc transfer error";
        console.error(`faucet chain ${chain.id} usdc transfer failed`, reason);
      }
    }

    try {
      const ethHash = await client.sendTransaction({
        to: recipient,
        value: ETH_DRIP_WEI,
      });
      console.log(`faucet chain ${chain.id} eth tx ${ethHash}`);
    } catch (error) {
      const reason = error instanceof Error ? error.message : "unknown eth transfer error";
      console.error(`faucet chain ${chain.id} eth transfer failed`, reason);
    }
  }

  private normalizePrivateKey(value: string): Hex {
    const trimmed = value.trim().toLowerCase();
    if (!trimmed) {
      throw new BadRequestError("Faucet private key is not configured.");
    }

    const normalized = trimmed.startsWith("0x") ? trimmed : `0x${trimmed}`;
    if (!/^0x[0-9a-f]{64}$/.test(normalized)) {
      throw new BadRequestError("Invalid faucet private key.");
    }
    return normalized as Hex;
  }
}
