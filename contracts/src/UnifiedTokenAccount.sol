// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import {Account} from "openzeppelin-contracts/account/Account.sol";
import {IERC1271} from "openzeppelin-contracts/interfaces/IERC1271.sol";
import {ERC1155Holder} from "openzeppelin-contracts/token/ERC1155/utils/ERC1155Holder.sol";
import {ERC721Holder} from "openzeppelin-contracts/token/ERC721/utils/ERC721Holder.sol";
import {Address} from "openzeppelin-contracts/utils/Address.sol";
import {EIP712} from "openzeppelin-contracts/utils/cryptography/EIP712.sol";
import {ECDSA} from "openzeppelin-contracts/utils/cryptography/ECDSA.sol";
import {MessageHashUtils} from "openzeppelin-contracts/utils/cryptography/MessageHashUtils.sol";
import {SignerEIP7702} from "openzeppelin-contracts/utils/cryptography/signers/SignerEIP7702.sol";
import {SignerWebAuthn} from "openzeppelin-contracts/utils/cryptography/signers/SignerWebAuthn.sol";
import {SignerP256} from "openzeppelin-contracts/utils/cryptography/signers/SignerP256.sol";
import {AbstractSigner} from "openzeppelin-contracts/utils/cryptography/signers/AbstractSigner.sol";
import {Initializable} from "openzeppelin-contracts/proxy/utils/Initializable.sol";
import {ReentrancyGuard} from "openzeppelin-contracts/utils/ReentrancyGuard.sol";
import {IWeth} from "./interfaces/IWeth.sol";

import {IAccumulatorFactory} from "./interfaces/IAccumulatorFactory.sol";
import {ISpokePool} from "./interfaces/ISpokePool.sol";
import {Dispatcher} from "./abstracts/Dispatcher.sol";
import {Call, OnchainCrossChainOrder, SuperIntentData} from "./types/Structs.sol";

/// @title UnifiedTokenAccount
/// @notice EIP-7702 smart account with ERC-7683 cross-chain intent support.
/// @dev
/// This is a fully functional account (execute, executeBatch) that also implements
///
/// Auth model:
/// - execute/executeBatch/executeSuperIntent: self only or via entrypoint or via relayer.
contract UnifiedTokenAccount is
    Account,
    EIP712,
    Initializable,
    IERC1271,
    Dispatcher,
    SignerWebAuthn,
    SignerEIP7702,
    ERC1155Holder,
    ERC721Holder,
    ReentrancyGuard
{
    bytes32 private constant EXECUTE_TYPEHASH =
        keccak256("Execute(address target,uint256 value,bytes32 dataHash,uint256 nonce,uint256 deadline)");
    bytes32 private constant EXECUTE_BATCH_TYPEHASH =
        keccak256("ExecuteBatch(bytes32 callsHash,uint256 nonce,uint256 deadline)");
    bytes32 private constant SUPER_INTENT_EXEC_TYPEHASH =
        keccak256("SuperIntentExecution(bytes32 superIntentHash,uint32 fillDeadline)");

    // ── State ───────────────────────────────────────────────────────────────
    /// @notice Deterministic destination accumulator deployed for this account.
    address public ACCUMULATOR;
    /// @notice Lower bound for accepted `fillDeadline` in `executeCrossChainOrder`.
    uint256 public constant MIN_FILL_DEADLINE_WINDOW = 5 minutes;
    /// @notice Upper bound for accepted `fillDeadline` in `executeCrossChainOrder`.
    uint256 public constant MAX_FILL_DEADLINE_WINDOW = 1 days;

    /// @notice Highest execution nonce observed so far (not necessarily contiguous).
    uint256 public lastUsedExecutionNonce;
    /// @notice Replay protection bitmap for explicit-signature execute paths.
    mapping(uint256 nonce => bool used) public usedExecutionNonces;

    // ── Events ──────────────────────────────────────────────────────────────
    event AccountInitialized(
        address indexed accumulator, address indexed spokePool, address indexed wrappedNativeToken
    );

    /// @param qx P-256 public key x coordinate.
    /// @param qy P-256 public key y coordinate.
    constructor(bytes32 qx, bytes32 qy) SignerP256(qx, qy) EIP712("UnifiedTokenAccount", "1") {}

    /// @notice One-time initializer. Sets the signer, dispatcher config, and deploys the accumulator.
    /// @dev The init signature binds chainId + account address + initialize parameters.
    function initialize(
        bytes32 qx,
        bytes32 qy,
        IAccumulatorFactory accumulatorFactory,
        IWeth wrappedNativeToken,
        ISpokePool spokePool,
        bytes calldata initSignature
    ) external initializer {
        if (qx == 0 || qy == 0) {
            revert InvalidPublicKey();
        }
        if (address(spokePool) == address(0)) {
            revert InvalidSpokePool();
        }
        if (address(wrappedNativeToken) == address(0)) {
            revert InvalidWrappedNativeToken();
        }
        if (address(accumulatorFactory) == address(0)) {
            revert InvalidAccumulatorFactory();
        }
        _validateInitializeSignature(qx, qy, accumulatorFactory, wrappedNativeToken, spokePool, initSignature);
        _setSigner(qx, qy);
        SPOKE_POOL = spokePool;
        WRAPPED_NATIVE_TOKEN = wrappedNativeToken;
        ACCUMULATOR = accumulatorFactory.deploy(address(spokePool));
        emit AccountInitialized(ACCUMULATOR, address(spokePool), address(wrappedNativeToken));
    }

    // ── Errors ──────────────────────────────────────────────────────────────
    error InvalidPublicKey();
    error InvalidAccumulatorFactory();
    error InvalidSpokePool();
    error InvalidWrappedNativeToken();
    error InvalidSignature();
    error InvalidInitializeSignature();
    error SignatureExpired(uint256 deadline);
    error ExecutionNonceAlreadyUsed(uint256 nonce);
    error InvalidOrderDataType();
    error FillDeadlineTooSoon(uint32 fillDeadline, uint256 minimumAllowed);
    error FillDeadlineTooFar(uint32 fillDeadline, uint256 maximumAllowed);

    // ═══════════════════════════════════════════════════════════════════════
    //  Account execution
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Execute a single call via ERC-4337/default route.
    function execute(address target, uint256 value, bytes calldata data) external onlyEntryPointOrSelf {
        Address.functionCallWithValue(target, data, value);
    }

    /// @notice Execute a single call with explicit EIP-712 authorization.
    function execute(Call calldata call, uint256 nonce, uint256 deadline, bytes calldata signature) external {
        _consumeExecutionNonceAndValidate(_hashExecuteCall(call, nonce, deadline), nonce, deadline, signature);
        Address.functionCallWithValue(call.target, call.data, call.value);
    }

    /// @notice Execute a batch of calls via ERC-4337/default route.
    function executeBatch(Call[] calldata calls) external onlyEntryPointOrSelf {
        uint256 len = calls.length;
        for (uint256 i; i < len; i++) {
            Address.functionCallWithValue(calls[i].target, calls[i].data, calls[i].value);
        }
    }

    /// @notice Execute a batch with explicit EIP-712 authorization.
    function executeBatch(Call[] calldata calls, uint256 nonce, uint256 deadline, bytes calldata signature) external {
        _consumeExecutionNonceAndValidate(_hashExecuteBatch(calls, nonce, deadline), nonce, deadline, signature);

        uint256 len = calls.length;
        for (uint256 i; i < len; i++) {
            Address.functionCallWithValue(calls[i].target, calls[i].data, calls[i].value);
        }
    }

    /// @notice Entry point for cross-chain intents with signature-first validation.
    /// @dev Validates fill window, order type, and signature before dispatching to `Dispatcher`.
    ///      The `orderData` decode happens once in this function and is passed through as a struct.
    function executeCrossChainOrder(OnchainCrossChainOrder calldata order, bytes calldata signature)
        external
        nonReentrant
    {
        _validateFillDeadline(order.fillDeadline);
        if (order.orderDataType != SUPER_INTENT_TYPEHASH) {
            revert InvalidOrderDataType();
        }

        SuperIntentData memory data = abi.decode(order.orderData, (SuperIntentData));

        bytes32 digest = _hashSuperIntentExecution(data, order.fillDeadline);
        if (!_rawSignatureValidation(digest, signature)) {
            revert InvalidSignature();
        }

        _executeCrossChainOrder(data, order.fillDeadline);
    }

    // ═══════════════════════════════════════════════════════════════════════
    //  ERC-1271
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Verifies that `signature` was produced by the account owner over `data`.
    /// @dev Intended for off-chain verification; not called on-chain by any contract.
    function isValidIntentSignature(SuperIntentData calldata data, uint32 fillDeadline, bytes calldata signature)
        public
        view
        returns (bytes4)
    {
        bytes32 digest = _hashSuperIntentExecution(data, fillDeadline);
        return _rawSignatureValidation(digest, signature) ? this.isValidIntentSignature.selector : bytes4(0xffffffff);
    }

    /// @inheritdoc IERC1271
    function isValidSignature(bytes32 hash, bytes calldata signature) public view override returns (bytes4) {
        return _rawSignatureValidation(hash, signature) ? this.isValidSignature.selector : bytes4(0xffffffff);
    }

    // ═══════════════════════════════════════════════════════════════════════
    //  Internal: Dispatcher hooks
    // ═══════════════════════════════════════════════════════════════════════

    /// @dev Returns the accumulator address for resolve helpers.
    function _getAccumulator() internal view override returns (address) {
        return ACCUMULATOR;
    }

    // ═══════════════════════════════════════════════════════════════════════
    //  Internal: Signature
    // ═══════════════════════════════════════════════════════════════════════

    /// @dev Enforces deadline + nonce replay checks, validates signature, then consumes nonce.
    function _consumeExecutionNonceAndValidate(
        bytes32 digest,
        uint256 nonce,
        uint256 deadline,
        bytes calldata signature
    ) internal {
        if (block.timestamp > deadline) {
            revert SignatureExpired(deadline);
        }
        if (usedExecutionNonces[nonce]) {
            revert ExecutionNonceAlreadyUsed(nonce);
        }
        if (!_rawSignatureValidation(digest, signature)) {
            revert InvalidSignature();
        }
        usedExecutionNonces[nonce] = true;
        if (nonce > lastUsedExecutionNonce) {
            lastUsedExecutionNonce = nonce;
        }
    }

    /// @dev Hashes a single-call execution payload into an EIP-712 digest.
    function _hashExecuteCall(Call calldata call, uint256 nonce, uint256 deadline) internal view returns (bytes32) {
        return _hashTypedDataV4(
            keccak256(abi.encode(EXECUTE_TYPEHASH, call.target, call.value, keccak256(call.data), nonce, deadline))
        );
    }

    /// @dev Hashes a batch execution payload into an EIP-712 digest.
    function _hashExecuteBatch(Call[] calldata calls, uint256 nonce, uint256 deadline) internal view returns (bytes32) {
        return
            _hashTypedDataV4(
                keccak256(abi.encode(EXECUTE_BATCH_TYPEHASH, keccak256(abi.encode(calls)), nonce, deadline))
            );
    }

    /// @dev Hashes cross-chain execution authorization:
    ///      `SuperIntentExecution(superIntentHash, fillDeadline)` under this account's EIP-712 domain.
    function _hashSuperIntentExecution(SuperIntentData memory data, uint32 fillDeadline)
        internal
        view
        returns (bytes32)
    {
        return _hashTypedDataV4(
            keccak256(abi.encode(SUPER_INTENT_EXEC_TYPEHASH, _hashSuperIntentData(data), fillDeadline))
        );
    }

    /// @dev EIP-7702 self-signature for internal calls, WebAuthn for external.
    function _rawSignatureValidation(bytes32 hash, bytes calldata signature)
        internal
        view
        override(AbstractSigner, SignerEIP7702, SignerWebAuthn)
        returns (bool)
    {
        if (signature.length == 65) {
            return SignerEIP7702._rawSignatureValidation(hash, signature);
        }
        return SignerWebAuthn._rawSignatureValidation(hash, signature);
    }

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

    /// @dev Validates the plain-hash initialize authorization signature (non-EIP712).
    ///      Recovered signer must be `address(this)` so initialization inputs are account-authorized.
    function _validateInitializeSignature(
        bytes32 qx,
        bytes32 qy,
        IAccumulatorFactory accumulatorFactory,
        IWeth wrappedNativeToken,
        ISpokePool spokePool,
        bytes calldata initSignature
    ) internal view {
        bytes32 digest = keccak256(
            abi.encode(
                block.chainid,
                address(this),
                qx,
                qy,
                address(accumulatorFactory),
                address(wrappedNativeToken),
                address(spokePool)
            )
        );
        address recovered = ECDSA.recoverCalldata(MessageHashUtils.toEthSignedMessageHash(digest), initSignature);
        if (recovered != address(this)) {
            revert InvalidInitializeSignature();
        }
    }
}
