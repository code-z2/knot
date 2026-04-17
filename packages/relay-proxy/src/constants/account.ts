import { keccak256, stringToBytes } from 'viem';

export const ERC7579_SINGLE_CALLTYPE = '0x00' as const;
export const ERC7579_BATCH_CALLTYPE = '0x01' as const;
export const ERC7579_EXECUTE_TYPE_DEFAULT = '0x00' as const;
export const ERC7579_EXECUTE_TYPE_TRY = '0x01' as const;

export const GAS_TANK_CREATE_X_SALT = keccak256(stringToBytes('knot.v1.gas-tank'));

export const EIP7702_FACTORY = '0x7702' as const;
