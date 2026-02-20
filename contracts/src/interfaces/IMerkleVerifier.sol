// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

/// @title IMerkleVerifier
/// @notice Callback interface for Merkle root signature verification.
///         The Accumulator (stateless) calls this on the owner account to verify
///         that a struct hash is part of a signed Merkle tree.
interface IMerkleVerifier {
    /// @notice Verify that `structHash` belongs to a Merkle tree whose root was signed by the account owner.
    /// @dev    The account wraps `structHash` with its EIP-712 domain separator to produce the chain-bound
    ///         leaf, then walks the proof to the root and verifies the signature.
    /// @param structHash  The EIP-712 struct hash (pre-domain) to verify.
    /// @param merkleProof Sibling hashes from leaf to root.
    /// @param signature   Signature over `toEthSignedMessageHash(root)`.
    /// @return magicValue `IMerkleVerifier.verifyMerkleRoot.selector` on success.
    function verifyMerkleRoot(bytes32 structHash, bytes32[] calldata merkleProof, bytes calldata signature)
        external
        view
        returns (bytes4 magicValue);
}
