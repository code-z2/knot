# MerkleValidator — Module Type 1 (Validator)

## Purpose

Validates all UserOperations via Merkle proof + P-256/WebAuthn signature. Replaces V1's inline `_executeX` verification logic and `verifyMerkleRoot` callback.

## Interface

```solidity
contract MerkleValidator is IERC7579Validator {
    // Per-account P-256 public key
    mapping(address account => PublicKey) internal _keys;

    struct PublicKey {
        bytes32 qx;
        bytes32 qy;
    }
}
```

## Module Lifecycle

### onInstall

```solidity
function onInstall(bytes calldata data) external {
    (bytes32 qx, bytes32 qy) = abi.decode(data, (bytes32, bytes32));
    require(qx != 0 && qy != 0, "invalid key");
    _keys[msg.sender] = PublicKey(qx, qy);
}
```

### onUninstall

```solidity
function onUninstall(bytes calldata) external {
    delete _keys[msg.sender];
}
```

## Validation: `validateUserOp`

Called by `AccountERC7579._validateUserOp` when the validator address is extracted from the UserOp nonce key.

```solidity
function validateUserOp(
    PackedUserOperation calldata userOp,
    bytes32 userOpHash
) external returns (uint256) {
    (bytes32[] memory proof, bytes memory innerSig) = abi.decode(
        userOp.signature, (bytes32[], bytes)
    );

    // userOpHash IS the leaf — all UserOp fields bound by EntryPoint
    bytes32 root = _computeRoot(userOpHash, proof);

    // Verify P-256 signature over root
    PublicKey memory key = _keys[userOp.sender];
    bool valid = _verifyP256(key, root, innerSig);

    return valid ? VALIDATION_SUCCESS : VALIDATION_FAILED;
}
```

### Leaf = `userOpHash`

The EntryPoint computes `userOpHash` as an EIP-712 hash (v0.8+) that includes:

- `sender`, `nonce`, `keccak256(initCode)`, `keccak256(callData)`
- `accountGasLimits`, `preVerificationGas`, `gasFees`
- `keccak256(paymasterAndData)`
- `chainId`, `entryPoint address`

Every UserOp field is bound. No custom leaf type needed. No EIP-712 domain separator reconstruction needed in the validator.

### Merkle Proof Walk

```solidity
function _computeRoot(bytes32 leaf, bytes32[] memory proof) internal pure returns (bytes32) {
    bytes32 current = leaf;
    for (uint256 i; i < proof.length; i++) {
        current = _hashPair(current, proof[i]);
    }
    return current;
}

function _hashPair(bytes32 a, bytes32 b) internal pure returns (bytes32) {
    return a < b
        ? keccak256(abi.encodePacked(a, b))
        : keccak256(abi.encodePacked(b, a));
}
```

Sorted pair hashing — no left/right distinction needed. Simplifies proof construction client-side.

### Single-Chain vs Cross-Chain

| Scenario | Leaves | Proof | Signature |
|---|---|---|---|
| Single-chain tx | 1 (userOpHash) | `[]` (empty) | P-256 over userOpHash |
| 2-chain cross-chain | 2 (userOpHash_A, userOpHash_B) | `[sibling]` each | P-256 over root |
| N-chain cross-chain | N | log2(N) siblings each | P-256 over root |

Single-chain has zero overhead — empty proof, signature directly over the hash. Cross-chain adds only proof siblings.

## Validation: `isValidSignature` (ERC-1271)

For off-chain signature verification (e.g., ERC-20 permit, off-chain order signing). The account's `isValidSignature` routes to installed validators.

```solidity
function isValidSignature(
    bytes32 hash,
    bytes calldata signature
) external view returns (bytes4) {
    (bytes32[] memory proof, bytes memory innerSig) = abi.decode(
        signature, (bytes32[], bytes)
    );

    bytes32 root = _computeRoot(hash, proof);
    PublicKey memory key = _keys[msg.sender]; // msg.sender = account
    bool valid = _verifyP256(key, root, innerSig);

    return valid ? bytes4(0x1626ba7e) : bytes4(0xffffffff);
}
```

Same proof + signature format. The `hash` parameter is the leaf.

## P-256 Signature Verification

Uses OZ's `P256` precompile wrapper (RIP-7212 with fallback):

```solidity
function _verifyP256(
    PublicKey memory key,
    bytes32 digest,
    bytes memory signature
) internal view returns (bool) {
    (bytes32 r, bytes32 s) = abi.decode(signature, (bytes32, bytes32));
    return P256.verify(digest, r, s, key.qx, key.qy);
}
```

For WebAuthn signatures, the `innerSig` includes the authenticator data and client data JSON. The validator decodes and verifies per the WebAuthn spec using OZ's `WebAuthn` library.

## Nonce Key Encoding

The EntryPoint v0.8 nonce is `uint256`:

```
| validator address (160 bits) | channel (32 bits) | sequence (64 bits) |
```

OZ's `AccountERC7579._extractUserOpValidator` reads the first 20 bytes as the validator address.

The 32-bit channel allows parallel nonce sequences:

- `0x0000` — Regular transactions
- `0x0001` — Cross-chain intent (destination UserOps)
- `0x0002+` — Reserved for future use

Each (key, sequence) pair is tracked independently by the EntryPoint. Pre-signed destination UserOps use channel `0x0001` so they don't conflict with regular account usage.

## Key Rotation

Rotating the P-256 key is a single UserOp:

```solidity
execute(BATCH_MODE, [
    self.uninstallModule(1, merkleValidator, ""),
    self.installModule(1, merkleValidator, abi.encode(newQx, newQy))
])
```

Atomic. Old key invalidated, new key active, in one transaction.

## Bootstrap (First UserOp)

Before any validator is installed, the account falls back to `SignerEIP7702._rawSignatureValidation` — the EOA's ECDSA key. The first UserOp uses this to install MerkleValidator (and all other modules).

After installation, all subsequent UserOps are validated by MerkleValidator. The ECDSA fallback is only used once.

## Security Considerations

- **No custom hashing.** The validator never computes leaf hashes — the EntryPoint provides `userOpHash`. This eliminates an entire class of hash construction bugs.
- **All fields bound.** Gas limits, paymaster, callData — everything is in the leaf. A malicious bundler cannot modify any field without breaking the proof.
- **Sorted pair hashing.** No left/right ambiguity in proofs. Simpler client code, fewer implementation bugs.
- **Single key per account.** No multi-key complexity. Key rotation is explicit (uninstall + reinstall).
