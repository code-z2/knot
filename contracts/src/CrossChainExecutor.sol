// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {SafeCast} from "openzeppelin-contracts/utils/math/SafeCast.sol";
import {
    Execution,
    IERC7579Execution,
    IERC7579Module,
    MODULE_TYPE_EXECUTOR
} from "openzeppelin-contracts/interfaces/draft-IERC7579.sol";
import {
    ERC7579Utils,
    CallType,
    ExecType,
    Mode,
    ModePayload,
    ModeSelector
} from "openzeppelin-contracts/account/utils/draft-ERC7579Utils.sol";

import {ICrossChainExecutor} from "./interfaces/ICrossChainExecutor.sol";
import {IKnotConsumerHub} from "./interfaces/IKnotConsumerHub.sol";
import {ISpokePool} from "./interfaces/ISpokePool.sol";
import {DispatchOrder, ModuleConfig, OnchainCrossChainOrder} from "./types/Structs.sol";

/// @title CrossChainExecutor
/// @notice ERC-7579 executor module that dispatches cross-chain orders through Across.
///
/// @dev Auth model:
///      - onInstall/onUninstall: called by the account during module lifecycle.
///      - dispatch: called by the account during an authorized UserOp execution. The module
///        never validates signatures directly; all signature verification happens upstream.
///
///      Native token handling:
///        - If `msg.value > 0`, the module passes ETH back to the account via the payable
///          `executeFromExecutor{value}` callback. The account forwards it to the SpokePool
///          deposit. Across treats a WETH input token with positive value as a native deposit.
///        - If `msg.value == 0`, the module approves the input token from the account to
///          the SpokePool via a reset-approve batch.
///
///      Recipient routing:
///        - `recipient == account` → accumulator flow, full message for destination fill tracking.
///        - `recipient != account` → direct bridge, empty message.
contract CrossChainExecutor is ICrossChainExecutor, IERC7579Module {
    // ═══════════════════════════════════════════════════════════════════════════
    //                              TYPEHASHES
    // ═══════════════════════════════════════════════════════════════════════════

    /// @dev EIP-712 typehash for DispatchOrder, used as `orderDataType` in OnchainCrossChainOrder.
    bytes32 public constant DISPATCH_ORDER_TYPEHASH = keccak256(
        "DispatchOrder(bytes32 salt,uint256 destChainId,address outputToken,"
        "uint256 sumOutput,uint256 inputAmount,address inputToken,uint256 minOutput,address recipient)"
    );

    // ═══════════════════════════════════════════════════════════════════════════
    //                                 TYPES
    // ═══════════════════════════════════════════════════════════════════════════

    // ═══════════════════════════════════════════════════════════════════════════
    //                                CONSTANTS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Lower bound for accepted `fillDeadline` in `dispatch`.
    uint256 public constant MIN_FILL_DEADLINE_WINDOW = 5 minutes;

    /// @notice Upper bound for accepted `fillDeadline` in `dispatch`.
    uint256 public constant MAX_FILL_DEADLINE_WINDOW = 1 days;

    // ═══════════════════════════════════════════════════════════════════════════
    //                                 STATE
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Per-account SpokePool config.
    mapping(address account => ModuleConfig) internal _configs;

    /// @notice Fill protection for dispatch salts, scoped per account.
    mapping(address account => mapping(bytes32 salt => bool used)) internal _usedSalts;

    // ═══════════════════════════════════════════════════════════════════════════
    //                                 ERRORS
    // ═══════════════════════════════════════════════════════════════════════════

    error InvalidSpokePool();
    error InvalidConsumerHub();
    error SaltAlreadyUsed(bytes32 salt);
    error FillDeadlineTooSoon(uint32 fillDeadline, uint256 minimumAllowed);
    error FillDeadlineTooFar(uint32 fillDeadline, uint256 maximumAllowed);
    error InvalidOrderDataType();

    // ═══════════════════════════════════════════════════════════════════════════
    //                            MODULE LIFECYCLE
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Installs the executor for the calling account.
    /// @dev Data layout: `abi.encode(ModuleConfig)`.
    function onInstall(bytes calldata data) external {
        ModuleConfig memory config = abi.decode(data, (ModuleConfig));
        address spokePool = config.spokePool;
        address consumerHub = config.consumerHub;

        if (spokePool == address(0)) {
            revert InvalidSpokePool();
        }
        if (consumerHub == address(0)) {
            revert InvalidConsumerHub();
        }

        _configs[msg.sender] = config;
    }

    /// @notice Removes the executor config for the calling account.
    function onUninstall(bytes calldata) external {
        delete _configs[msg.sender];
    }

    /// @notice Returns whether this module implements the executor module type.
    function isModuleType(uint256 moduleTypeId) external pure returns (bool) {
        return moduleTypeId == MODULE_TYPE_EXECUTOR;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    //                              DISPATCH
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Dispatch a single cross-chain leg via the SpokePool.
    /// @dev Native ETH: If msg.value > 0, ETH is forwarded back to the account and
    ///      attached to the SpokePool deposit. Across treats WETH + value as native.
    function dispatch(OnchainCrossChainOrder calldata envelope) external payable {
        address account = msg.sender;
        ModuleConfig memory config = _configs[account];

        if (config.spokePool == address(0)) {
            revert InvalidSpokePool();
        }
        if (envelope.orderDataType != DISPATCH_ORDER_TYPEHASH) {
            revert InvalidOrderDataType();
        }

        DispatchOrder memory order = abi.decode(envelope.orderData, (DispatchOrder));
        if (_usedSalts[account][order.salt]) {
            revert SaltAlreadyUsed(order.salt);
        }
        _usedSalts[account][order.salt] = true;

        _validateFillDeadline(envelope.fillDeadline);

        bytes memory message;
        if (order.recipient == account) {
            message = _buildDestinationMessage(account, order, envelope.fillDeadline);
        }

        // Compose and execute through the account. msg.value is forwarded back via executeFromExecutor{value}.
        _dispatchDeposit(config, envelope, order, message);
        if (order.recipient == account) {
            IKnotConsumerHub(config.consumerHub)
                .registerIntent(
                    account, _fillId(account, order, envelope.fillDeadline), order.destChainId, envelope.fillDeadline
                );
        }
    }

    /// @notice Returns the installed executor config for an account.
    function configOf(address account) external view returns (address spokePool) {
        return _configs[account].spokePool;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    //                         ACCOUNT EXECUTION
    // ═══════════════════════════════════════════════════════════════════════════

    /// @dev Composes the full execution batch and dispatches it through the account.
    ///      For ERC-20: [approve(0), approve(amount), deposit]
    ///      For native: [deposit{value}]
    ///      msg.value is always forwarded back via the payable executeFromExecutor call.
    function _dispatchDeposit(
        ModuleConfig memory config,
        OnchainCrossChainOrder calldata envelope,
        DispatchOrder memory order,
        bytes memory message
    ) internal {
        bytes memory depositCalldata = abi.encodeCall(
            ISpokePool.deposit,
            (
                _toBytes32(msg.sender),
                _toBytes32(order.recipient),
                _toBytes32(order.inputToken),
                _toBytes32(order.outputToken),
                order.inputAmount,
                order.minOutput,
                order.destChainId,
                bytes32(0),
                SafeCast.toUint32(block.timestamp),
                envelope.fillDeadline,
                uint32(0),
                message
            )
        );

        uint256 value = msg.value;
        uint8 n = value > 0 ? 1 : 3;
        Execution[] memory executions = new Execution[](n);

        if (value == 0) {
            executions[0] = Execution({
                target: order.inputToken, value: 0, callData: abi.encodeCall(IERC20.approve, (config.spokePool, 0))
            });
            executions[1] = Execution({
                target: order.inputToken,
                value: 0,
                callData: abi.encodeCall(IERC20.approve, (config.spokePool, order.inputAmount))
            });
        }

        executions[n - 1] = Execution({target: config.spokePool, value: value, callData: depositCalldata});

        IERC7579Execution(msg.sender).executeFromExecutor{value: value}(
            Mode.unwrap(_encodeMode(ERC7579Utils.CALLTYPE_BATCH)), ERC7579Utils.encodeBatch(executions)
        );
    }

    /// @dev Builds an ERC-7579 execution mode.
    function _encodeMode(CallType callType) internal pure returns (Mode) {
        return ERC7579Utils.encodeMode(
            callType, ExecType.wrap(0x00), ModeSelector.wrap(bytes4(0)), ModePayload.wrap(bytes22(0))
        );
    }

    // ═══════════════════════════════════════════════════════════════════════════
    //                        DESTINATION MESSAGE
    // ═══════════════════════════════════════════════════════════════════════════

    /// @dev Encodes the accumulation-only message consumed on the destination chain.
    function _buildDestinationMessage(address account, DispatchOrder memory order, uint32 fillDeadline)
        internal
        view
        returns (bytes memory message)
    {
        message = abi.encode(order.salt, block.chainid, fillDeadline, account, order.sumOutput, order.outputToken);
    }

    /// @dev Derives the canonical fill id shared with the destination accumulator and hub.
    function _fillId(address account, DispatchOrder memory order, uint32 fillDeadline) internal pure returns (bytes32) {
        return keccak256(abi.encode(order.salt, account, fillDeadline, order.sumOutput, order.outputToken));
    }

    // ═══════════════════════════════════════════════════════════════════════════
    //                              UTILITIES
    // ═══════════════════════════════════════════════════════════════════════════

    /// @dev Enforces accepted `fillDeadline` bounds relative to current block time.
    function _validateFillDeadline(uint32 fillDeadline) internal view {
        uint256 minAllowed = block.timestamp + MIN_FILL_DEADLINE_WINDOW;
        if (fillDeadline < minAllowed) {
            revert FillDeadlineTooSoon(fillDeadline, minAllowed);
        }

        uint256 maxAllowed = block.timestamp + MAX_FILL_DEADLINE_WINDOW;
        if (fillDeadline > maxAllowed) {
            revert FillDeadlineTooFar(fillDeadline, maxAllowed);
        }
    }

    /// @dev Left-pads an address into a bytes32 (Across V3 deposit format).
    function _toBytes32(address addr) internal pure returns (bytes32) {
        return bytes32(uint256(uint160(addr)));
    }
}
