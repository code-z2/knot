// SPDX-License-Identifier: MIT
pragma solidity ^0.8.33;

import {Test} from "forge-std/Test.sol";
import {AccountERC7579} from "openzeppelin-contracts/account/extensions/draft-AccountERC7579.sol";
import {PackedUserOperation} from "openzeppelin-contracts/interfaces/draft-IERC4337.sol";
import {
    MODULE_TYPE_VALIDATOR,
    VALIDATION_FAILED,
    VALIDATION_SUCCESS
} from "openzeppelin-contracts/interfaces/draft-IERC7579.sol";
import {IERC1271} from "openzeppelin-contracts/interfaces/IERC1271.sol";
import {Base64} from "openzeppelin-contracts/utils/Base64.sol";
import {Math} from "openzeppelin-contracts/utils/math/Math.sol";
import {P256} from "openzeppelin-contracts/utils/cryptography/P256.sol";
import {WebAuthn} from "openzeppelin-contracts/utils/cryptography/WebAuthn.sol";

import {MerkleValidator} from "../src/MerkleValidator.sol";

contract TestERC7579Account is AccountERC7579 {
    constructor(address validator, bytes memory initData) {
        _installModule(MODULE_TYPE_VALIDATOR, validator, initData);
    }

    function uninstallValidator(address validator) external {
        _uninstallModule(MODULE_TYPE_VALIDATOR, validator, "");
    }

    function _rawSignatureValidation(bytes32, bytes calldata) internal view override returns (bool) {
        return false;
    }
}

contract MerkleValidatorTest is Test {
    bytes4 private constant INVALID_PUBLIC_KEY_SELECTOR =
        bytes4(keccak256("SignerP256InvalidPublicKey(bytes32,bytes32)"));

    MerkleValidator private validator;
    TestERC7579Account private account;

    uint256 private signerPk;
    bytes32 private signerQx;
    bytes32 private signerQy;

    function setUp() public {
        signerPk = 11;
        (uint256 qxRaw, uint256 qyRaw) = vm.publicKeyP256(signerPk);
        signerQx = bytes32(qxRaw);
        signerQy = bytes32(qyRaw);

        validator = new MerkleValidator();
        account = new TestERC7579Account(address(validator), abi.encode(signerQx, signerQy));
    }

    function test_onInstallStoresKey() public view {
        (bytes32 qx, bytes32 qy) = validator.publicKeyOf(address(account));

        assertEq(qx, signerQx);
        assertEq(qy, signerQy);
    }

    function test_onInstallRevertsForInvalidKey() public {
        vm.expectRevert(abi.encodeWithSelector(INVALID_PUBLIC_KEY_SELECTOR, bytes32(0), bytes32(0)));
        vm.prank(address(account));
        validator.onInstall(abi.encode(bytes32(0), bytes32(0)));
    }

    function test_onUninstallClearsKey() public {
        account.uninstallValidator(address(validator));

        (bytes32 qx, bytes32 qy) = validator.publicKeyOf(address(account));
        assertEq(qx, bytes32(0));
        assertEq(qy, bytes32(0));
    }

    function test_validateUserOp_singleLeafRawP256() public {
        bytes32 userOpHash = keccak256("userOpHash");
        PackedUserOperation memory userOp =
            _buildUserOp(userOpHash, new bytes32[](0), _signP256Digest(signerPk, userOpHash), 0, 1);

        vm.prank(address(account.entryPoint()));
        uint256 validationData = account.validateUserOp(userOp, userOpHash, 0);

        assertEq(validationData, VALIDATION_SUCCESS);
    }

    function test_validateUserOp_twoLeafMerkleProofRawP256() public {
        bytes32 userOpHash = keccak256("leafA");
        bytes32 sibling = keccak256("leafB");
        bytes32 root = _hashPair(userOpHash, sibling);
        bytes32[] memory proof = new bytes32[](1);
        proof[0] = sibling;

        PackedUserOperation memory userOp = _buildUserOp(root, proof, _signP256Digest(signerPk, root), 1, 7);

        vm.prank(address(account.entryPoint()));
        uint256 validationData = account.validateUserOp(userOp, userOpHash, 0);

        assertEq(validationData, VALIDATION_SUCCESS);
    }

    function test_validateUserOp_invalidSignatureFails() public {
        bytes32 userOpHash = keccak256("userOpHash");
        PackedUserOperation memory userOp =
            _buildUserOp(userOpHash, new bytes32[](0), _signP256Digest(12, userOpHash), 0, 2);

        vm.prank(address(account.entryPoint()));
        uint256 validationData = account.validateUserOp(userOp, userOpHash, 0);

        assertEq(validationData, VALIDATION_FAILED);
    }

    function test_validateUserOp_webauthnSignature() public {
        bytes32 userOpHash = keccak256("webauthn");
        PackedUserOperation memory userOp =
            _buildUserOp(userOpHash, new bytes32[](0), _signWebAuthnDigest(signerPk, userOpHash), 0, 3);

        vm.prank(address(account.entryPoint()));
        uint256 validationData = account.validateUserOp(userOp, userOpHash, 0);

        assertEq(validationData, VALIDATION_SUCCESS);
    }

    function test_isValidSignatureWithSender_routesThroughAccount() public view {
        bytes32 digest = keccak256("permit");
        bytes memory signature =
            abi.encodePacked(address(validator), abi.encode(new bytes32[](0), _signP256Digest(signerPk, digest)));

        bytes4 result = account.isValidSignature(digest, signature);

        assertEq(result, IERC1271.isValidSignature.selector);
    }

    function test_isValidSignatureWithSenderFailsAfterUninstall() public {
        account.uninstallValidator(address(validator));

        bytes32 digest = keccak256("permit");
        bytes memory signature =
            abi.encodePacked(address(validator), abi.encode(new bytes32[](0), _signP256Digest(signerPk, digest)));

        bytes4 result = account.isValidSignature(digest, signature);

        assertEq(result, bytes4(0xffffffff));
    }

    function _buildUserOp(bytes32, bytes32[] memory proof, bytes memory innerSignature, uint32 channel, uint64 sequence)
        internal
        view
        returns (PackedUserOperation memory userOp)
    {
        userOp.sender = address(account);
        userOp.nonce = _encodeNonce(address(validator), channel, sequence);
        userOp.initCode = "";
        userOp.callData = abi.encodePacked(bytes4(keccak256("execute()")));
        userOp.accountGasLimits = bytes32(0);
        userOp.preVerificationGas = 0;
        userOp.gasFees = bytes32(0);
        userOp.paymasterAndData = "";
        userOp.signature = abi.encode(proof, innerSignature);
    }

    function _encodeNonce(address validatorModule, uint32 channel, uint64 sequence) internal pure returns (uint256) {
        return (uint256(uint160(validatorModule)) << 96) | (uint256(channel) << 64) | uint256(sequence);
    }

    function _hashPair(bytes32 a, bytes32 b) internal pure returns (bytes32) {
        return a < b ? keccak256(abi.encodePacked(a, b)) : keccak256(abi.encodePacked(b, a));
    }

    function _signP256Digest(uint256 privateKey, bytes32 digest) internal pure returns (bytes memory) {
        (bytes32 r, bytes32 s) = vm.signP256(privateKey, digest);
        bytes32 canonicalS = bytes32(Math.min(uint256(s), P256.N - uint256(s)));
        return abi.encodePacked(r, canonicalS);
    }

    function _signWebAuthnDigest(uint256 privateKey, bytes32 digest) internal pure returns (bytes memory) {
        bytes memory challenge = abi.encodePacked(digest);
        bytes memory authenticatorData =
            abi.encodePacked(bytes32(0), WebAuthn.AUTH_DATA_FLAGS_UP | WebAuthn.AUTH_DATA_FLAGS_UV, bytes4(0));
        string memory clientDataJSON =
            string.concat('{"type":"webauthn.get","challenge":"', Base64.encodeURL(challenge), '"}');

        bytes32 messageHash = sha256(abi.encodePacked(authenticatorData, sha256(bytes(clientDataJSON))));
        (bytes32 r, bytes32 s) = vm.signP256(privateKey, messageHash);

        return
            abi.encode(r, bytes32(Math.min(uint256(s), P256.N - uint256(s))), 23, 1, authenticatorData, clientDataJSON);
    }
}
