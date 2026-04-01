import type { Address, Chain } from 'viem';
import type { RpcId } from './rpc';

export type ChainEnvironment = 'mainnet' | 'testnet';

export type MainnetChainId = 8453 | 42161;

export type TestnetChainId = 84532 | 421614 | 11155111;

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

export type BaseChainConfig<
    TChainId extends SupportedChainId,
    TEnvironment extends ChainEnvironment,
> = Chain & {
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

export type ChainPolicyBody = {
    id: RpcId;
    params?: {
        chainId?: number;
        request?: readonly [unknown, string?];
    };
};
