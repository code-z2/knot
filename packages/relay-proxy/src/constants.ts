import type { Address } from "viem";

export const SUPPORT_MODES: Set<string> = new Set(["LIMITED_TESTNET", "LIMITED_MAINNET", "FULL_MAINNET"]);
export const ETH_DRIP_WEI = 10_000_000_000_000_000n; // 0.01 ETH
export const USDC_DRIP_AMOUNT = 2_000_000n; // 2 USDC (6 decimals)
export const FAUCET_PENDING_TTL_SECONDS = 600;
export const FAUCET_FUNDED_TTL_SECONDS = 31_536_000;
export const DEFERRED_TX_TTL_SECONDS = 2_592_000;

export const TESTNET_USDC_BY_CHAIN: Record<number, Address> = {
  11155111: "0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238", // Sepolia
  84532: "0x036CbD53842c5426634e7929541eC2318f3dCF7e", // Base Sepolia
  421614: "0x75faf114eafb1BDbe2F0316DF893fd58CE46AA4d", // Arbitrum Sepolia
};

export const ERC20_TRANSFER_ABI = [
  {
    type: "function",
    name: "transfer",
    stateMutability: "nonpayable",
    inputs: [
      { name: "to", type: "address" },
      { name: "amount", type: "uint256" },
    ],
    outputs: [{ name: "", type: "bool" }],
  },
] as const;

export const JSON_HEADERS = {
  "content-type": "application/json; charset=utf-8",
  "cache-control": "no-store",
};
