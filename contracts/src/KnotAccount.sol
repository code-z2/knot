// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import {ERC1155Holder} from "openzeppelin-contracts/token/ERC1155/utils/ERC1155Holder.sol";
import {ERC721Holder} from "openzeppelin-contracts/token/ERC721/utils/ERC721Holder.sol";
import {Initializable} from "openzeppelin-contracts/proxy/utils/Initializable.sol";
import {SignerEIP7702} from "openzeppelin-contracts/utils/cryptography/signers/SignerEIP7702.sol";
import {
    MODULE_TYPE_VALIDATOR,
    MODULE_TYPE_EXECUTOR,
    MODULE_TYPE_FALLBACK
} from "openzeppelin-contracts/interfaces/draft-IERC7579.sol";
import {AccountERC7579} from "openzeppelin-contracts/account/extensions/draft-AccountERC7579.sol";
import {AccountERC7579Hooked} from "openzeppelin-contracts/account/extensions/draft-AccountERC7579Hooked.sol";

import {IAccumulatorModule} from "./interfaces/IAccumulatorModule.sol";

/// @title KnotAccount
/// @notice ERC-7579 modular smart account for the Knot protocol.
///
/// @dev Pure OZ shell. All domain logic lives in modules:
///      - MerkleValidator (type 1): Merkle-proof-bound P-256/WebAuthn signature validation.
///      - CrossChainExecutor (type 2): Source-chain Across SpokePool dispatch.
///      - AccumulatorModule (type 2+3): Destination-chain fill tracking and intent execution.
///      The account keeps OZ hook support available for future protocol modules, but does not
///      install an active hook during bootstrap.
///
///      Bootstrap: The first UserOp is validated via `SignerEIP7702` (EOA ECDSA fallback in
///      Account base) and calls `initialize` to install all modules. After initialization,
///      MerkleValidator handles all UserOp validation and ERC-1271 signatures.
contract KnotAccount is AccountERC7579Hooked, Initializable, SignerEIP7702, ERC1155Holder, ERC721Holder {
    // ═══════════════════════════════════════════════════════════════════════════
    //                                 ERRORS
    // ═══════════════════════════════════════════════════════════════════════════

    error InvalidModule();

    // ═══════════════════════════════════════════════════════════════════════════
    //                          CONSTRUCTOR / INIT
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice One-time initialization. Installs all modules in a single call.
    /// @dev Access: onlyEntryPointOrSelf — the first UserOp (validated by EOA ECDSA via
    ///      SignerEIP7702 fallback) calls this to bootstrap the modular account.
    ///
    /// @param validator       MerkleValidator module address.
    /// @param validatorData   abi.encode(bytes32 qx, bytes32 qy) — P-256 public key.
    /// @param executor        CrossChainExecutor module address.
    /// @param executorData    abi.encode(ModuleConfig({spokePool, consumerHub})).
    /// @param accumulator     AccumulatorModule address (installed as executor + fallback handler).
    /// @param accumulatorData abi.encode(ModuleConfig({spokePool, consumerHub})).
    function initialize(
        address validator,
        bytes calldata validatorData,
        address executor,
        bytes calldata executorData,
        address accumulator,
        bytes calldata accumulatorData
    ) external onlyEntryPointOrSelf initializer {
        if (validator == address(0) || executor == address(0) || accumulator == address(0)) {
            revert InvalidModule();
        }

        // Type 1 — Validator (MerkleValidator)
        _installModule(MODULE_TYPE_VALIDATOR, validator, validatorData);

        // Type 2 — Executor (CrossChainExecutor)
        _installModule(MODULE_TYPE_EXECUTOR, executor, executorData);

        // Type 2 — Executor (AccumulatorModule)
        _installModule(MODULE_TYPE_EXECUTOR, accumulator, accumulatorData);

        // Type 3 — Fallback handler (AccumulatorModule: handleV3AcrossMessage)
        _installModule(
            MODULE_TYPE_FALLBACK, accumulator, abi.encodePacked(IAccumulatorModule.handleV3AcrossMessage.selector)
        );

        // Type 3 — Fallback handler (AccumulatorModule: executeIntent)
        _installModule(MODULE_TYPE_FALLBACK, accumulator, abi.encodePacked(IAccumulatorModule.executeIntent.selector));

        // Type 3 — Fallback handler (AccumulatorModule: markStale)
        _installModule(MODULE_TYPE_FALLBACK, accumulator, abi.encodePacked(IAccumulatorModule.markStale.selector));
    }

    // ═══════════════════════════════════════════════════════════════════════════
    //                                 MEMO
    // ═══════════════════════════════════════════════════════════════════════════

    /// @dev Emitted when a memo is attached to an execution. Indexed for efficient log filtering.
    event Memo(bytes32 indexed memo);

    /// @notice Execute with a memo annotation. Emits `Memo` then delegates to standard execute.
    /// @param mode ERC-7579 execution mode.
    /// @param executionCalldata ERC-7579 encoded execution calldata.
    /// @param memo Opaque bytes32 memo — emitted in event, never stored.
    function execute(bytes32 mode, bytes calldata executionCalldata, bytes32 memo) public payable onlyEntryPointOrSelf {
        if (memo != bytes32(0)) {
            emit Memo(memo);
        }
        execute(mode, executionCalldata);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    //                              OVERRIDES
    // ═══════════════════════════════════════════════════════════════════════════

    /// @inheritdoc AccountERC7579Hooked
    function accountId() public pure override returns (string memory) {
        return "knot.KnotAccount.v2.0.0";
    }

    /// @dev Resolve AbstractSigner diamond: EOA ECDSA (EIP-7702) for fallback validation.
    function _rawSignatureValidation(bytes32 hash, bytes calldata signature)
        internal
        view
        override(AccountERC7579, SignerEIP7702)
        returns (bool)
    {
        return SignerEIP7702._rawSignatureValidation(hash, signature);
    }
}
