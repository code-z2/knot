// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Account} from "openzeppelin-contracts/account/Account.sol";
import {IERC1271} from "openzeppelin-contracts/interfaces/IERC1271.sol";
import {ERC1155Holder} from "openzeppelin-contracts/token/ERC1155/utils/ERC1155Holder.sol";
import {ERC721Holder} from "openzeppelin-contracts/token/ERC721/utils/ERC721Holder.sol";
import {SignerEIP7702} from "openzeppelin-contracts/utils/cryptography/signers/SignerEIP7702.sol";
import {SignerWebAuthn} from "openzeppelin-contracts/utils/cryptography/signers/SignerWebAuthn.sol";
import {SignerP256} from "openzeppelin-contracts/utils/cryptography/signers/SignerP256.sol";
import {AbstractSigner} from "openzeppelin-contracts/utils/cryptography/signers/AbstractSigner.sol";
import {Initializable} from "openzeppelin-contracts/proxy/utils/Initializable.sol";

import {Call, ChainCalls} from "./types/Structs.sol";
import {Exec} from "./utils/Exec.sol";
import {IAccumulator} from "./interfaces/IAccumulator.sol";

/// @title UnifiedTokenAccount
/// @notice EIP-7702 account that signs and orchestrates scatter-gather.
/// @dev
/// Role in the flow:
/// - Holds the user's passkey (WebAuthn) for intent signing.
/// - Executes chain-specific batches (swap -> bridge -> register job on destination).
/// - Approves destination accumulators via registerJob.
///
/// This account does NOT execute the final swap; it only authorizes the accumulator
/// and coordinates the multi-chain scatter. The accumulator owns execution once
/// fills have arrived.
contract UnifiedTokenAccount is
    Account,
    Initializable,
    IERC1271,
    SignerWebAuthn,
    SignerEIP7702,
    ERC1155Holder,
    ERC721Holder
{
    event JobRegistered(bytes32 indexed jobId, address indexed accumulator);

    error ExecuteError(uint256 index, bytes error);

    /// @param qx P-256 public key x coordinate.
    /// @param qy P-256 public key y coordinate.
    constructor(bytes32 qx, bytes32 qy) SignerP256(qx, qy) {}

    /// @notice One-time initializer for upgradeable deployments.
    /// @dev Used only if deployed as a proxy; EIP-7702 uses the constructor path.
    function initialize(bytes32 qx, bytes32 qy) external initializer {
        _checkEntryPointOrSelf();

        _setSigner(qx, qy);
    }

    /// @notice Execute a single call (account or entrypoint only).
    /// @dev This is the primitive used by the account to perform swap/bridge calls per chain.
    function execute(address target, uint256 value, bytes calldata data) external virtual {
        _checkEntryPointOrSelf();

        bool ok = Exec.call(target, value, data, gasleft());
        if (!ok) {
            Exec.revertWithReturnData();
        }
    }

    /// @notice Execute a batch of calls (reverts on first failure).
    /// @dev Use this to bundle "swap -> approve -> bridge -> registerJob" on a chain.
    function executeBatch(Call[] calldata calls) external virtual {
        _checkEntryPointOrSelf();

        uint256 callsLength = calls.length;
        for (uint256 i = 0; i < callsLength; i++) {
            Call calldata call = calls[i];
            bool ok = Exec.call(call.target, call.value, call.data, gasleft());
            if (!ok) {
                if (callsLength == 1) {
                    Exec.revertWithReturnData();
                } else {
                    revert ExecuteError(i, Exec.getReturnData(0));
                }
            }
        }
    }

    /// @notice Execute only the Call[] for the current chainId from a ChainCalls[] blob.
    /// @dev This lets you sign one payload and execute the relevant slice on each chain.
    function executeChainCalls(bytes calldata data) external virtual {
        _checkEntryPointOrSelf();

        ChainCalls[] memory bundles = abi.decode(data, (ChainCalls[]));
        uint256 bundlesLength = bundles.length;

        for (uint256 i = 0; i < bundlesLength; i++) {
            if (bundles[i].chainId == block.chainid) {
                this.executeBatch(bundles[i].calls);
                return;
            }
        }
    }

    /// @notice Register a job and approve it on the accumulator.
    /// @dev The accumulator derives the same intentHash from the payload + nonce. We bind the
    /// job to the account nonce and chainId so replays are rejected without the correct nonce.
    function registerJob(bytes32 jobId, address accumulator) external {
        _checkEntryPointOrSelf();

        uint256 nonce = getNonce();
        uint256 salt = (nonce << 60) | block.chainid;
        bytes32 intenthash = _hashSaltJobId(salt, jobId);
        // aderyn-fp-next-line(unsafe-erc20-operation)
        IAccumulator(accumulator).approve(intenthash);
        emit JobRegistered(intenthash, accumulator);
    }

    /// @dev Hash helper for job approval IDs (salted by nonce + chainId).
    function _hashSaltJobId(uint256 salt, bytes32 jobId) internal pure returns (bytes32 result) {
        assembly ("memory-safe") {
            mstore(0x00, salt)
            mstore(0x20, jobId)
            result := keccak256(0x00, 0x40)
        }
    }

    /// @inheritdoc IERC1271
    function isValidSignature(bytes32 hash, bytes calldata signature) public view override returns (bytes4) {
        return _rawSignatureValidation(hash, signature) ? this.isValidSignature.selector : bytes4(0xffffffff);
    }

    /// @dev Uses EIP-7702 self-signature when called by the account, otherwise WebAuthn.
    /// This enables the account to authorize its own internal calls while still enforcing
    /// passkey signatures for external requests.
    function _rawSignatureValidation(bytes32 hash, bytes calldata signature)
        internal
        view
        override(AbstractSigner, SignerEIP7702, SignerWebAuthn)
        returns (bool)
    {
        if (msg.sender == address(this)) {
            return SignerEIP7702._rawSignatureValidation(hash, signature);
        }
        return SignerWebAuthn._rawSignatureValidation(hash, signature);
    }
}
