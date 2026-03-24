// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import {PackedUserOperation} from "openzeppelin-contracts/interfaces/draft-IERC4337.sol";
import {
    IERC7579Validator,
    MODULE_TYPE_VALIDATOR,
    VALIDATION_FAILED,
    VALIDATION_SUCCESS
} from "openzeppelin-contracts/interfaces/draft-IERC7579.sol";
import {MerkleProof} from "openzeppelin-contracts/utils/cryptography/MerkleProof.sol";
import {P256} from "openzeppelin-contracts/utils/cryptography/P256.sol";
import {SignerP256} from "openzeppelin-contracts/utils/cryptography/signers/SignerP256.sol";
import {SignerWebAuthn} from "openzeppelin-contracts/utils/cryptography/signers/SignerWebAuthn.sol";
import {ECDSA} from "openzeppelin-contracts/utils/cryptography/ECDSA.sol";

/// @title MerkleValidator
/// @notice ERC-7579 validator module for Merkle-proof-bound P-256 and WebAuthn signatures.
///
/// @dev Auth model:
///      - onInstall/onUninstall: called by the account during module lifecycle.
///      - validateUserOp: verifies the provided userOpHash belongs to a Merkle tree whose root
///        was signed by the account's installed passkey.
///      - isValidSignatureWithSender: same proof/signature format for ERC-1271 flows.
///
///      Signature envelope:
///        abi.encode(bytes32[] merkleProof, bytes innerSignature)
///
///      The inner signature is delegated to OpenZeppelin's SignerWebAuthn implementation, which:
///        - verifies WebAuthn assertions when the signature decodes as WebAuthnAuth
///        - falls back to raw P-256 `(r, s)` verification otherwise
contract MerkleValidator is IERC7579Validator, SignerWebAuthn {
    // ═══════════════════════════════════════════════════════════════════════════
    //                                  TYPES
    // ═══════════════════════════════════════════════════════════════════════════

    struct PublicKey {
        bytes32 qx;
        bytes32 qy;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    //                                CONSTANTS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @dev P-256 generator point, used only to satisfy the SignerP256 constructor.
    bytes32 private constant GX = 0x6B17D1F2E12C4247F8BCE6E563A440F277037D812DEB33A0F4A13945D898C296;

    /// @dev P-256 generator point, used only to satisfy the SignerP256 constructor.
    bytes32 private constant GY = 0x4FE342E2FE1A7F9B8EE7EB4A7C0F9E162BCE33576B315ECECBB6406837BF51F5;

    // ═══════════════════════════════════════════════════════════════════════════
    //                                 STATE
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Per-account P-256 public key installed during module setup.
    mapping(address account => PublicKey) internal _keys;

    // ═══════════════════════════════════════════════════════════════════════════
    //                              CONSTRUCTOR
    // ═══════════════════════════════════════════════════════════════════════════

    constructor() SignerP256(GX, GY) {}

    // ═══════════════════════════════════════════════════════════════════════════
    //                            MODULE LIFECYCLE
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Installs the validator for the calling account.
    /// @dev Data layout: `abi.encode(bytes32 qx, bytes32 qy)`.
    function onInstall(bytes calldata data) external {
        (bytes32 qx, bytes32 qy) = abi.decode(data, (bytes32, bytes32));

        if (!P256.isValidPublicKey(qx, qy)) {
            revert SignerP256InvalidPublicKey(qx, qy);
        }

        _keys[msg.sender] = PublicKey({qx: qx, qy: qy});
    }

    /// @notice Removes the validator key for the calling account.
    function onUninstall(bytes calldata) external {
        delete _keys[msg.sender];
    }

    /// @notice Returns whether this module implements the validator module type.
    function isModuleType(uint256 moduleTypeId) external pure returns (bool) {
        return moduleTypeId == MODULE_TYPE_VALIDATOR;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    //                              VALIDATION
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Validates a UserOperation hash against the calling account's installed key.
    /// @dev `userOpHash` is already the EntryPoint-provided leaf hash.
    function validateUserOp(PackedUserOperation calldata userOp, bytes32 userOpHash) external view returns (uint256) {
        (bytes32[] calldata proof, bytes calldata innerSignature) = _decodeSigCalldata(userOp.signature);
        bytes32 root = MerkleProof.processProofCalldata(proof, userOpHash);

        return
            _rawSignatureValidationWithSender(msg.sender, root, innerSignature) ? VALIDATION_SUCCESS : VALIDATION_FAILED;
    }

    /// @notice Validates an ERC-1271 signature using the same Merkle-proof envelope.
    function isValidSignatureWithSender(address sender, bytes32 hash, bytes calldata signature)
        external
        view
        returns (bytes4)
    {
        (bytes32[] calldata proof, bytes calldata innerSignature) = _decodeSigCalldata(signature);
        bytes32 root = MerkleProof.processProofCalldata(proof, hash);

        return _rawSignatureValidationWithSender(sender, root, innerSignature) ? bytes4(0x1626ba7e) : bytes4(0xffffffff);
    }

    /// @notice Returns the installed public key for an account.
    function publicKeyOf(address account) external view returns (bytes32 qx, bytes32 qy) {
        PublicKey memory key = _keys[account];
        return (key.qx, key.qy);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    //                           SIGNER ADAPTER
    // ═══════════════════════════════════════════════════════════════════════════

    /// @dev Adapts OZ SignerWebAuthn to the ERC-7579 module model by resolving the key from `msg.sender`.
    ///      During validator calls, `msg.sender` is always the account currently using the module.
    function signer() public view virtual override returns (bytes32 qx, bytes32 qy) {
        PublicKey memory key = _keys[msg.sender];
        return (key.qx, key.qy);
    }

    /// @dev Returns whether the account currently has an installed key.
    function _hasPublicKey(PublicKey memory key) internal pure returns (bool) {
        return key.qx != bytes32(0) && key.qy != bytes32(0);
    }

    /// @dev EIP-7702 + IERC7579Validator overload.
    function _rawSignatureValidationWithSender(address sender, bytes32 hash, bytes calldata signature)
        internal
        view
        returns (bool)
    {
        if (signature.length == 65) {
            (address recovered, ECDSA.RecoverError err,) = ECDSA.tryRecover(hash, signature);
            return sender == recovered && err == ECDSA.RecoverError.NoError;
        }

        PublicKey memory key = _keys[sender];
        if (_hasPublicKey(key)) {
            return SignerWebAuthn._rawSignatureValidation(hash, signature);
        }

        return false;
    }

    /// @notice Extracts a Merkle proof and inner signature from UserOp signature calldata
    /// @dev Avoids abi.decode to memory — reads offsets directly from calldata
    /// @param userOpSignature The user operation signature
    /// @dev Layout: abi.encode(bytes32[], bytes)
    ///   [0x00..0x20)  offset to bytes32[] data
    ///   [0x20..0x40)  offset to bytes data
    ///   then the dynamic arrays themselves
    /// @return proof The Merkle proof as bytes32[] (calldata slice)
    /// @return signature The inner signature (calldata slice)
    function _decodeSigCalldata(bytes calldata userOpSignature)
        internal
        pure
        returns (bytes32[] calldata proof, bytes calldata signature)
    {
        assembly {
            let baseOffset := userOpSignature.offset
            let proofPtr := add(baseOffset, calldataload(baseOffset))
            let sigPtr := add(baseOffset, calldataload(add(baseOffset, 0x20)))

            proof.offset := add(proofPtr, 0x20)
            proof.length := calldataload(proofPtr)

            signature.offset := add(sigPtr, 0x20)
            signature.length := calldataload(sigPtr)
        }
    }
}
