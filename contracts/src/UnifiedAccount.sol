// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import {Account} from "openzeppelin-contracts/account/Account.sol";
import {IERC1271} from "openzeppelin-contracts/interfaces/IERC1271.sol";
import {ERC1155Holder} from "openzeppelin-contracts/token/ERC1155/utils/ERC1155Holder.sol";
import {ERC721Holder} from "openzeppelin-contracts/token/ERC721/utils/ERC721Holder.sol";
import {Address} from "openzeppelin-contracts/utils/Address.sol";
import {EIP712} from "openzeppelin-contracts/utils/cryptography/EIP712.sol";
import {MessageHashUtils} from "openzeppelin-contracts/utils/cryptography/MessageHashUtils.sol";
import {MerkleProof} from "openzeppelin-contracts/utils/cryptography/MerkleProof.sol";
import {SignerEIP7702} from "openzeppelin-contracts/utils/cryptography/signers/SignerEIP7702.sol";
import {SignerWebAuthn} from "openzeppelin-contracts/utils/cryptography/signers/SignerWebAuthn.sol";
import {SignerP256} from "openzeppelin-contracts/utils/cryptography/signers/SignerP256.sol";
import {AbstractSigner} from "openzeppelin-contracts/utils/cryptography/signers/AbstractSigner.sol";
import {Initializable} from "openzeppelin-contracts/proxy/utils/Initializable.sol";
import {ReentrancyGuard} from "openzeppelin-contracts/utils/ReentrancyGuard.sol";

import {IAccumulatorFactory} from "./interfaces/IAccumulatorFactory.sol";
import {IMerkleVerifier} from "./interfaces/IMerkleVerifier.sol";
import {ISpokePool} from "./interfaces/ISpokePool.sol";
import {Dispatcher} from "./abstracts/Dispatcher.sol";
import {Call, OnchainCrossChainOrder} from "./types/Structs.sol";

/// @title UnifiedAccount
/// @notice EIP-7702 smart account with Merkle-tree-based cross-chain intent support.
///
/// @dev Auth model:
///      - execute/executeBatch: self only or via entrypoint (ERC-4337 flow).
///      - executeX: Merkle-verified signed execution. Each chain gets its own EIP-712
///        chain-bound leaf. The root is chain-agnostic (signed via toEthSignedMessageHash).
///        User signs root once; each chain verifies its leaf + proof independently.
///      - dispatch: onlyEntryPointOrSelf — called via self-call from executeX batch.
///      - verifyMerkleRoot: callback for the Accumulator to verify dest chain leaves.
///
///      Merkle tree structure:
///        Leaf = _hashTypedDataV4(keccak256(abi.encode(EXECUTEX_TYPEHASH, callsHash, salt)))
///        Root = processProofCalldata(proof, leaf)  (chain-agnostic)
///        Signed = toEthSignedMessageHash(root)
contract UnifiedAccount is
    Account,
    EIP712,
    Initializable,
    IERC1271,
    IMerkleVerifier,
    Dispatcher,
    SignerWebAuthn,
    SignerEIP7702,
    ERC1155Holder,
    ERC721Holder,
    ReentrancyGuard
{
    // ═══════════════════════════════════════════════════════════════════════════
    //                              TYPEHASHES
    // ═══════════════════════════════════════════════════════════════════════════

    /// @dev EIP-712 typehash for the executeX leaf.
    ///      `callsHash` is keccak256(abi.encode(calls)) — the entire Call[] encoded.
    bytes32 private constant EXECUTEX_TYPEHASH = keccak256("ExecuteX(bytes32 callsHash,bytes32 salt)");

    /// @dev EIP-712 typehash for DispatchOrder, used as `orderDataType` in OnchainCrossChainOrder.
    bytes32 public constant DISPATCH_ORDER_TYPEHASH = keccak256(
        "DispatchOrder(bytes32 salt,uint256 destChainId,address outputToken,"
        "uint256 sumOutput,uint256 inputAmount,address inputToken,uint256 minOutput)"
    );

    // ═══════════════════════════════════════════════════════════════════════════
    //                                 STATE
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Deterministic destination accumulator deployed for this account.
    address public accumulator;

    /// @notice Lower bound for accepted `fillDeadline` in `dispatch`.
    uint256 public constant MIN_FILL_DEADLINE_WINDOW = 5 minutes;

    /// @notice Upper bound for accepted `fillDeadline` in `dispatch`.
    uint256 public constant MAX_FILL_DEADLINE_WINDOW = 1 days;

    /// @notice Replay protection for executeX salts. Each salt can only be used once per chain.
    mapping(bytes32 salt => bool used) public usedSalts;

    // ═══════════════════════════════════════════════════════════════════════════
    //                                 EVENTS
    // ═══════════════════════════════════════════════════════════════════════════

    event AccountInitialized(address indexed accumulator, address indexed spokePool);

    // ═══════════════════════════════════════════════════════════════════════════
    //                                 ERRORS
    // ═══════════════════════════════════════════════════════════════════════════

    error InvalidPublicKey();
    error InvalidAccumulatorFactory();
    error InvalidSpokePool();
    error InvalidSignature();
    error SaltAlreadyUsed(bytes32 salt);
    error FillDeadlineTooSoon(uint32 fillDeadline, uint256 minimumAllowed);
    error FillDeadlineTooFar(uint32 fillDeadline, uint256 maximumAllowed);
    error InvalidOrderDataType(bytes32 provided, bytes32 expected);

    // ═══════════════════════════════════════════════════════════════════════════
    //                          CONSTRUCTOR / INIT
    // ═══════════════════════════════════════════════════════════════════════════

    /// @param qx P-256 public key x coordinate.
    /// @param qy P-256 public key y coordinate.
    constructor(bytes32 qx, bytes32 qy) SignerP256(qx, qy) EIP712("UnifiedAccount", "1") {}

    /// @notice One-time initializer. Sets the signer, dispatcher config, and deploys the accumulator.
    /// @dev Access: onlyEntryPointOrSelf — owner is established by deployment/EIP-7702 delegation.
    ///      No signature verification needed; the owner is inherently the delegator.
    function initialize(bytes32 qx, bytes32 qy, IAccumulatorFactory _accumulatorFactory, ISpokePool _spokePool)
        external
        onlyEntryPointOrSelf
        initializer
    {
        if (qx == 0 || qy == 0) {
            revert InvalidPublicKey();
        }
        if (address(_spokePool) == address(0)) {
            revert InvalidSpokePool();
        }
        if (address(_accumulatorFactory) == address(0)) {
            revert InvalidAccumulatorFactory();
        }
        _setSigner(qx, qy);
        spokePool = _spokePool;
        accumulator = _accumulatorFactory.deploy(address(_spokePool));
        emit AccountInitialized(accumulator, address(_spokePool));
    }

    // ═══════════════════════════════════════════════════════════════════════════
    //  Account execution (ERC-4337 / self-call)
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Execute a single call via ERC-4337/default route.
    function execute(address target, uint256 value, bytes calldata data) external onlyEntryPointOrSelf {
        Address.functionCallWithValue(target, data, value);
    }

    /// @notice Execute a batch of calls via ERC-4337/default route.
    function executeBatch(Call[] calldata calls) external onlyEntryPointOrSelf {
        uint256 len = calls.length;
        for (uint256 i; i < len; i++) {
            Address.functionCallWithValue(calls[i].target, calls[i].data, calls[i].value);
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════
    //  Merkle-verified execution (executeX)
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Execute a batch of calls authorized by a Merkle leaf + proof + root signature.
    ///
    /// @dev Each chain gets its own EIP-712 chain-bound leaf in the Merkle tree.
    ///      The root is chain-agnostic (signed via toEthSignedMessageHash(root)).
    ///      This is the primary signed execution path for cross-chain intents:
    ///        executeX Call[] = [...sourceCalls, dispatch(order)]
    ///
    ///      Salt provides replay protection. Each salt can only be used once per chain.
    ///      The leaf is EIP-712 domain-bound (includes chainId), so the same salt
    ///      cannot be replayed across chains — different leaves, different proofs.
    ///
    /// @param calls       The batch of calls to execute (source calls + dispatch, or any calls).
    /// @param salt        Unique salt for replay protection.
    /// @param merkleProof Sibling hashes from leaf to root.
    /// @param signature   Signature over `toEthSignedMessageHash(root)`.
    function executeX(Call[] calldata calls, bytes32 salt, bytes32[] calldata merkleProof, bytes calldata signature)
        external
        payable
        nonReentrant
    {
        // Replay protection.
        if (usedSalts[salt]) {
            revert SaltAlreadyUsed(salt);
        }
        usedSalts[salt] = true;

        // Build chain-bound EIP-712 leaf hash.
        bytes32 leafHash =
            _hashTypedDataV4(keccak256(abi.encode(EXECUTEX_TYPEHASH, keccak256(abi.encode(calls)), salt)));

        // Walk proof to compute chain-agnostic root.
        bytes32 root = MerkleProof.processProofCalldata(merkleProof, leafHash);

        // Verify signature over the chain-agnostic root.
        bytes32 digest = MessageHashUtils.toEthSignedMessageHash(root);
        if (!_rawSignatureValidation(digest, signature)) {
            revert InvalidSignature();
        }

        // Execute the batch via self-call so that each call's msg.sender is this contract.
        uint256 len = calls.length;
        for (uint256 i; i < len; i++) {
            Address.functionCallWithValue(calls[i].target, calls[i].data, calls[i].value);
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════
    //  Cross-chain dispatch (via executeX)
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Dispatch a single cross-chain leg via the SpokePool.
    /// @dev Access: onlyEntryPointOrSelf — called via self-call from executeX batch.
    ///      No signature verification here; auth is enforced at the executeX layer.
    ///      Payable to allow forwarding native value to the SpokePool deposit.
    ///
    ///      ERC-7683 compatible: accepts OnchainCrossChainOrder envelope.
    ///      Validates orderDataType matches DISPATCH_ORDER_TYPEHASH and fillDeadline bounds.
    function dispatch(OnchainCrossChainOrder calldata order) external payable onlyEntryPointOrSelf {
        if (order.orderDataType != DISPATCH_ORDER_TYPEHASH) {
            revert InvalidOrderDataType(order.orderDataType, DISPATCH_ORDER_TYPEHASH);
        }
        _validateFillDeadline(order.fillDeadline);
        _dispatch(order);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    //  Merkle verification callback (implements IMerkleVerifier)
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Verify that a struct hash belongs to a Merkle tree whose root was signed by the owner.
    /// @dev Called by the Accumulator on the destination chain.
    ///      The Accumulator passes its EIP-712 struct hash (pre-domain). This contract wraps it
    ///      with `_hashTypedDataV4` to produce the chain-bound leaf, then walks the proof to
    ///      the root and verifies the signature.
    ///
    ///      This ensures ALL leaves in the Merkle tree are uniformly EIP-712 chain-bound —
    ///      both executeX leaves and Accumulator execution leaves use `_hashTypedDataV4`.
    ///
    /// @param structHash  The EIP-712 struct hash (pre-domain) from the Accumulator.
    /// @param merkleProof Sibling hashes from leaf to root.
    /// @param signature   Signature over `toEthSignedMessageHash(root)`.
    /// @return magicValue `IMerkleVerifier.verifyMerkleRoot.selector` on success.
    function verifyMerkleRoot(bytes32 structHash, bytes32[] calldata merkleProof, bytes calldata signature)
        external
        view
        override
        returns (bytes4 magicValue)
    {
        // Wrap struct hash with EIP-712 domain separator to produce chain-bound leaf.
        bytes32 leafHash = _hashTypedDataV4(structHash);

        // Walk proof to compute chain-agnostic root.
        bytes32 root = MerkleProof.processProofCalldata(merkleProof, leafHash);

        // Verify signature over the chain-agnostic root.
        bytes32 digest = MessageHashUtils.toEthSignedMessageHash(root);
        return
            _rawSignatureValidation(digest, signature) ? IMerkleVerifier.verifyMerkleRoot.selector : bytes4(0xffffffff);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    //  ERC-1271
    // ═══════════════════════════════════════════════════════════════════════════

    /// @inheritdoc IERC1271
    function isValidSignature(bytes32 hash, bytes calldata signature) public view override returns (bytes4) {
        return _rawSignatureValidation(hash, signature) ? this.isValidSignature.selector : bytes4(0xffffffff);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    //  Internal: Dispatcher hooks
    // ═══════════════════════════════════════════════════════════════════════════

    /// @dev Returns the accumulator address for the Dispatcher.
    function _getAccumulator() internal view override returns (address) {
        return accumulator;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    //  Internal: Signature
    // ═══════════════════════════════════════════════════════════════════════════

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
}
