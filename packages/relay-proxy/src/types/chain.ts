import { MAINNET_CHAIN_IDZ, TESTNET_CHAIN_IDZ } from '@/constants';
import type { Address, Chain } from 'viem';
import z from 'zod';
import { BundlerClient } from './bundler';

export type ChainEnvironment = 'mainnet' | 'testnet';

export type MainnetChainId = z.infer<typeof MAINNET_CHAIN_IDZ>;

export type TestnetChainId = z.infer<typeof TESTNET_CHAIN_IDZ>;

export type SupportedChainId = MainnetChainId | TestnetChainId;

export type FaucetAsset =
    | {
          amount: string;
          kind: 'native';
      }
    | {
          amount: string;
          kind: 'erc20';
          token: Address;
      };

export type BaseChainConfig<TChainId extends SupportedChainId, TEnvironment extends ChainEnvironment> = Chain & {
    id: TChainId;
    enabled: boolean;
    environment: TEnvironment;
    gelato: {
        quoteToken: Address;
    };
    supportedEntryPoints: readonly Address[];
};

export type MainnetChainConfig = BaseChainConfig<MainnetChainId, 'mainnet'>;

export type TestnetChainConfig = BaseChainConfig<TestnetChainId, 'testnet'> & {
    faucet: {
        assets: readonly FaucetAsset[];
    };
};

export type SupportedChainConfig = MainnetChainConfig | TestnetChainConfig;

export type ChainRegistry = Readonly<Record<SupportedChainId, SupportedChainConfig>>;

export type PublicChainDescriptor = {
    chainId: SupportedChainId;
    environment: ChainEnvironment;
    name: string;
};

export type ChainPolicyContext = Record<number, { client: Promise<BundlerClient>; config: SupportedChainConfig }>;
