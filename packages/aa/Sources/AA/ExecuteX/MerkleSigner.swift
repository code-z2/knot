import Foundation

struct ExecuteXSignedMerkleBundle {
    let root: Data
    let proofs: [[Data]]
    let digest: Data
    let signature: Data
}

struct ExecuteXMerkleSigner {
    func signLeaves(
        _ resolvedLeaves: [ExecuteXResolvedLeaf],
        signRoot: @Sendable (Data) async throws -> Data,
    ) async throws -> ExecuteXSignedMerkleBundle {
        let (root, proofs) = try SmartAccount.Merkle.rootAndProofs(
            leaves: resolvedLeaves.map(\.leafHash),
        )
        let digest = SmartAccount.ExecuteX.signingDigest(root: root)
        let signature = try await signRoot(digest)

        return ExecuteXSignedMerkleBundle(
            root: root,
            proofs: proofs,
            digest: digest,
            signature: signature,
        )
    }
}
