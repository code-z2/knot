import {
    ERC7579_BATCH_CALLTYPE,
    ERC7579_EXECUTE_TYPE_DEFAULT,
    ERC7579_EXECUTE_TYPE_TRY,
    ERC7579_SINGLE_CALLTYPE,
} from '@/constants';
import { Address, Hex, PrivateKeyAccount, PublicActions, PublicClient } from 'viem';

export type CallType = typeof ERC7579_SINGLE_CALLTYPE | typeof ERC7579_BATCH_CALLTYPE;

export type ExecType = typeof ERC7579_EXECUTE_TYPE_DEFAULT | typeof ERC7579_EXECUTE_TYPE_TRY;

export type KnotAccountInitParams = {
    spokePool: Address;
    consumerHub: Address;
    validatorModule: Address;
    executorModule: Address;
    accumulatorModule: Address;
    publicKey: {
        x: Hex;
        y: Hex;
    };
};

export type ToKnotAccountParameters = {
    client: PublicClient;
    owner: PrivateKeyAccount;
    delegate: Address;
    initParams: KnotAccountInitParams;
};
