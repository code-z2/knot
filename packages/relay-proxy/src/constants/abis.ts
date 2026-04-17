import { parseAbi, parseAbiParameters } from 'viem';

export const KNOT_ACCOUNT_ABI = parseAbi([
    'function initialize(address validator, bytes calldata validatorData, address executor, bytes calldata executorData, address accumulator, bytes calldata accumulatorData) external',
    'function execute(bytes32 mode, bytes calldata executionCalldata) public payable',
    'function execute(bytes32 mode, bytes calldata executionCalldata, bytes32 memo) public payable',
]);

export const CREATE_X_ABI = parseAbi([
    'function deployCreate2(bytes32 salt, bytes memory initCode) external payable returns (address)',
    'function computeCreate2Address(bytes32 salt, bytes32 initCodeHash) external view returns (address)',
]);

export const GAS_TANK_ABI = parseAbi([
    'constructor(address _owner, address _cosigner, address _usdc)',
    'function debit(uint256 amount, address to) external',
    'function withdraw(uint256 amount, address to, uint256 deadline, bytes calldata cosignerSig) external',
    'function withdrawNonce() view returns (uint256)',
]);

export const EXECUTION_BATCH_ABI = parseAbiParameters([
    '(address target, uint256 value, bytes callData)[] executionBatch',
]);

export const KNOT_MODULE_CONFIG_ABI = parseAbiParameters('(address spokePool, address consumerHub)');

export const KNOT_VALIDATOR_CONFIG_ABI = parseAbiParameters('bytes32 qx, bytes32 qy');
