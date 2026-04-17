/**
 * ERC-7579 account encoding utilities — calldata construction and
 * decoding for Knot smart accounts.
 *
 * ERC-7579 defines a modular smart-account standard where `execute()`
 * accepts a 32-byte `mode` (encoding the call type and execution type)
 * and an `executionCalldata` blob whose format depends on the mode.
 *
 * Knot accounts support two call types:
 * - **Single** (`0x00`): `abi.encodePacked(target, value, data)`
 * - **Batch** (`0x01`): `abi.encode(Execution[])` where each element
 *   is `{ target, value, callData }`
 *
 * The `encodeKnotAccount*` functions wrap the raw ERC-7579 encoding
 * with the Knot account's `execute()` function selector, producing
 * the final `callData` field for a UserOperation.
 *
 * @module
 */
import {
    ERC7579_BATCH_CALLTYPE,
    ERC7579_EXECUTE_TYPE_DEFAULT,
    ERC7579_SINGLE_CALLTYPE,
    EXECUTION_BATCH_ABI,
    KNOT_ACCOUNT_ABI,
    KNOT_MODULE_CONFIG_ABI,
    KNOT_VALIDATOR_CONFIG_ABI,
} from '@/constants';
import { CallType, ExecType, KnotAccountInitParams } from '@/types';
import {
    Address,
    type Call,
    type Hex,
    decodeAbiParameters,
    decodeFunctionData,
    encodeAbiParameters,
    encodeFunctionData,
    encodePacked,
    slice,
} from 'viem';

import { concat, pad } from 'viem';

export function encodeMode(callType: CallType, execType: ExecType = '0x00'): Hex {
    return concat([
        callType, // byte 0  — 1 byte
        execType, // byte 1  — 1 byte
        '0x0000', // bytes 2-3 — unused
        pad('0x', { size: 4 }), // bytes 4-7  — modeSelector (zeroed)
        pad('0x', { size: 24 }), // bytes 8-31 — modePayload  (zeroed)
    ]);
}

export function decodeMode(mode: Hex): { callType: CallType; execType: ExecType } {
    const callTypeByte = slice(mode, 0, 1);

    switch (callTypeByte) {
        case ERC7579_SINGLE_CALLTYPE:
            return { callType: ERC7579_SINGLE_CALLTYPE, execType: ERC7579_EXECUTE_TYPE_DEFAULT };
        case ERC7579_BATCH_CALLTYPE:
            return { callType: ERC7579_BATCH_CALLTYPE, execType: ERC7579_EXECUTE_TYPE_DEFAULT };
        default:
            throw new Error(`Unknown callType byte: ${callTypeByte}`);
    }
}

export function encodeSingleExecution(call: Call): Hex {
    return encodePacked(['address', 'uint256', 'bytes'], [call.to, call.value ?? 0n, call.data ?? '0x']);
}

export function decodeSingleExecution(executionCalldata: Hex): Call {
    const target = `0x${executionCalldata.slice(2, 42)}` as Hex;
    const value = BigInt(`0x${executionCalldata.slice(42, 106)}`);
    const callData = `0x${executionCalldata.slice(106)}` as Hex;

    return { to: target, value, data: callData };
}

export function encodeBatchExecution(calls: readonly Call[]): Hex {
    return encodeAbiParameters(EXECUTION_BATCH_ABI, [
        calls.map((call) => ({
            target: call.to,
            value: call.value ?? 0n,
            callData: call.data ?? '0x',
        })),
    ]);
}

export function decodeBatchExecution(executionCalldata: Hex): Call[] {
    const [executions] = decodeAbiParameters(EXECUTION_BATCH_ABI, executionCalldata);

    return executions.map((e) => ({
        to: e.target,
        value: e.value,
        data: e.callData,
    }));
}

export function encodeERC7579SingleCall(call: Call): {
    mode: Hex;
    executionCalldata: Hex;
} {
    return {
        mode: encodeMode(ERC7579_SINGLE_CALLTYPE),
        executionCalldata: encodeSingleExecution(call),
    };
}

export function encodeERC7579BatchCall(calls: readonly Call[]): {
    mode: Hex;
    executionCalldata: Hex;
} {
    return {
        mode: encodeMode(ERC7579_BATCH_CALLTYPE),
        executionCalldata: encodeBatchExecution(calls),
    };
}

export function decodeERC7579Call(mode: Hex, executionCalldata: Hex): Call[] {
    const { callType } = decodeMode(mode);
    if (callType === ERC7579_BATCH_CALLTYPE) {
        return decodeBatchExecution(executionCalldata);
    }
    if (callType === ERC7579_SINGLE_CALLTYPE) {
        return [decodeSingleExecution(executionCalldata)];
    }
    throw new Error(`Unknown callType: ${callType}`);
}

export function encodeKnotAccountSingleExecution(call: Call) {
    const { mode, executionCalldata } = encodeERC7579SingleCall(call);
    return encodeFunctionData({
        abi: KNOT_ACCOUNT_ABI,
        functionName: 'execute',
        args: [mode, executionCalldata],
    });
}

export function encodeKnotAccountBatchExecution(calls: readonly Call[]) {
    const { mode, executionCalldata } = encodeERC7579BatchCall(calls);
    return encodeFunctionData({
        abi: KNOT_ACCOUNT_ABI,
        functionName: 'execute',
        args: [mode, executionCalldata],
    });
}

export function decodeKnotAccountExecution(data: Hex) {
    const { functionName, args } = decodeFunctionData({
        abi: KNOT_ACCOUNT_ABI,
        data,
    });
    if (functionName !== 'execute') {
        throw new Error(`Unknown function name: ${functionName}`);
    }

    const [mode, executionCalldata] = args;
    return decodeERC7579Call(mode, executionCalldata);
}

export function encodeKnotAccountModuleConfig(spokePool: Address, consumerHub: Address): Hex {
    return encodeAbiParameters(KNOT_MODULE_CONFIG_ABI, [{ spokePool, consumerHub }]);
}

export function encodeKnotAccountValidatorConfig(gx: Hex, gy: Hex): Hex {
    return encodeAbiParameters(KNOT_VALIDATOR_CONFIG_ABI, [gx, gy]);
}

export function encodeKnotAccountInitParams(params: KnotAccountInitParams): Hex {
    const initCalldata = encodeFunctionData({
        abi: KNOT_ACCOUNT_ABI,
        functionName: 'initialize',
        args: [
            params.validatorModule,
            encodeKnotAccountValidatorConfig(params.publicKey.x, params.publicKey.y),
            params.executorModule,
            encodeKnotAccountModuleConfig(params.spokePool, params.consumerHub),
            params.accumulatorModule,
            encodeKnotAccountModuleConfig(params.spokePool, params.consumerHub),
        ],
    });
    return initCalldata;
}
