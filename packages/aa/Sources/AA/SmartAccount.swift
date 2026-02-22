import BigInt
import Foundation
import Passkey
import RPC
import Transactions
import web3swift

public struct OnchainCrossChainOrder: Sendable, Equatable {
    public let fillDeadline: UInt32
    public let orderDataType: Data
    public let orderData: Data

    public init(fillDeadline: UInt32, orderDataType: Data, orderData: Data) {
        self.fillDeadline = fillDeadline
        self.orderDataType = orderDataType
        self.orderData = orderData
    }
}

public struct DispatchOrder: Sendable, Equatable {
    public let salt: Data
    public let destChainId: UInt64
    public let outputToken: String
    public let sumOutput: BigUInt
    public let inputAmount: BigUInt
    public let inputToken: String
    public let minOutput: BigUInt

    public init(
        salt: Data,
        destChainId: UInt64,
        outputToken: String,
        sumOutput: BigUInt,
        inputAmount: BigUInt,
        inputToken: String,
        minOutput: BigUInt,
    ) {
        self.salt = salt
        self.destChainId = destChainId
        self.outputToken = outputToken
        self.sumOutput = sumOutput
        self.inputAmount = inputAmount
        self.inputToken = inputToken
        self.minOutput = minOutput
    }
}

public struct InitializationConfig: Sendable, Equatable {
    public let accumulatorFactory: String
    public let spokePool: String

    public init(accumulatorFactory: String, spokePool: String) {
        self.accumulatorFactory = accumulatorFactory
        self.spokePool = spokePool
    }
}

public struct AccumulatorExecutionParams: Sendable, Equatable {
    public let salt: Data
    public let fillDeadline: UInt32
    public let sumOutput: BigUInt
    public let outputToken: String
    public let finalMinOutput: BigUInt
    public let finalOutputToken: String
    public let recipient: String
    public let destinationCaller: String
    public let destCalls: [Call]

    public init(
        salt: Data,
        fillDeadline: UInt32,
        sumOutput: BigUInt,
        outputToken: String,
        finalMinOutput: BigUInt,
        finalOutputToken: String,
        recipient: String,
        destinationCaller: String,
        destCalls: [Call],
    ) {
        self.salt = salt
        self.fillDeadline = fillDeadline
        self.sumOutput = sumOutput
        self.outputToken = outputToken
        self.finalMinOutput = finalMinOutput
        self.finalOutputToken = finalOutputToken
        self.recipient = recipient
        self.destinationCaller = destinationCaller
        self.destCalls = destCalls
    }
}

public struct AccumulatorExecutionIntent: Sendable, Equatable {
    public let accumulator: String
    public let params: AccumulatorExecutionParams

    public init(accumulator: String, params: AccumulatorExecutionParams) {
        self.accumulator = accumulator
        self.params = params
    }
}

public enum SmartAccount {
    /// Merkle-verified execution via `executeX(Call[], bytes32 salt, bytes32[] proof, bytes signature)`.
    public enum ExecuteX {
        /// Compute the pre-domain EIP-712 struct hash for ExecuteX.
        public static func structHash(calls: [Call], salt: Data) throws -> Data {
            let callsEncoded = try ABIEncoder.encodeCallTupleArray(calls)
            let callsHashWord = try ABIWord.bytes32(Data(callsEncoded.sha3(.keccak256)))
            let saltWord = try ABIWord.bytes32(salt)
            return Data((AAUtils.executeXTypeHash + callsHashWord + saltWord).sha3(.keccak256))
        }

        /// Compute the chain-bound leaf hash for ExecuteX calls.
        public static func leafHash(
            account: String,
            chainId: UInt64,
            calls: [Call],
            salt: Data,
        ) throws -> Data {
            let sx = try structHash(calls: calls, salt: salt)
            return try leafHash(account: account, chainId: chainId, structHash: sx)
        }

        /// Compute a chain-bound leaf hash from a pre-domain EIP-712 struct hash.
        public static func leafHash(
            account: String,
            chainId: UInt64,
            structHash: Data,
        ) throws -> Data {
            let domain = try AAUtils.accountDomainSeparator(chainId: chainId, account: account)
            return AAUtils.hashTypedDataV4(domainSeparator: domain, structHash: structHash)
        }

        /// Compute the Merkle root for a single leaf (no siblings — root == leaf).
        public static func rootForSingleLeaf(_ leaf: Data) -> Data {
            leaf
        }

        /// Compute the Merkle root for two leaves using OZ's commutative keccak256 (sorted pair).
        public static func rootForTwoLeaves(_ a: Data, _ b: Data) -> Data {
            Data(commutativePairBytes(a, b).sha3(.keccak256))
        }

        /// Wrap a Merkle root with `toEthSignedMessageHash` to produce the signing digest.
        public static func signingDigest(root: Data) -> Data {
            AAUtils.toEthSignedMessageHash(root)
        }

        /// ABI-encode an `executeX(Call[], bytes32, bytes32[], bytes)` function call.
        public static func encodeCall(
            calls: [Call],
            salt: Data,
            merkleProof: [Data],
            signature: Data,
        ) throws -> Data {
            let callsArray = try ABIEncoder.encodeCallTupleArray(calls)
            let saltWord = try ABIWord.bytes32(salt)
            let proofArray = try encodeMerkleProof(merkleProof)
            let signatureBytes = ABIEncoder.encodeBytes(signature)

            return ABIEncoder.functionCallOrdered(
                signature: "executeX((address,uint256,bytes)[],bytes32,bytes32[],bytes)",
                arguments: [
                    .dynamic(callsArray),
                    .word(saltWord),
                    .dynamic(proofArray),
                    .dynamic(signatureBytes),
                ],
            )
        }

        private static func commutativePairBytes(_ a: Data, _ b: Data) -> Data {
            if a.lexicographicallyPrecedes(b) {
                return a + b
            }
            return b + a
        }

        private static func encodeMerkleProof(_ proof: [Data]) throws -> Data {
            var out = ABIWord.uint(BigUInt(proof.count))
            for element in proof {
                try out.append(ABIWord.bytes32(element))
            }
            return out
        }
    }

    public enum Merkle {
        /// Build a sorted-pair Merkle root and per-leaf proofs compatible with OZ `processProofCalldata`.
        public static func rootAndProofs(leaves: [Data]) throws -> (root: Data, proofs: [[Data]]) {
            guard !leaves.isEmpty else {
                throw SmartAccountError.emptyLeaves
            }

            if leaves.count == 1 {
                return (root: leaves[0], proofs: [[]])
            }

            var proofs = Array(repeating: [Data](), count: leaves.count)
            var level = leaves
            var positions = Array(0 ..< leaves.count)

            while level.count > 1 {
                for (leafIndex, position) in positions.enumerated() {
                    let siblingIndex = position % 2 == 0 ? position + 1 : position - 1
                    if siblingIndex < level.count {
                        proofs[leafIndex].append(level[siblingIndex])
                    }
                }

                var nextLevel: [Data] = []
                var index = 0
                while index < level.count {
                    let left = level[index]
                    let rightIndex = index + 1
                    if rightIndex < level.count {
                        nextLevel.append(ExecuteX.rootForTwoLeaves(left, level[rightIndex]))
                    } else {
                        nextLevel.append(left)
                    }
                    index += 2
                }

                positions = positions.map { $0 / 2 }
                level = nextLevel
            }

            return (root: level[0], proofs: proofs)
        }
    }

    /// Dispatch a cross-chain order via the SpokePool (ERC-7683 compatible).
    public enum Dispatch {
        public static func buildOrder(
            fillDeadline: UInt32,
            dispatchOrder: DispatchOrder,
        ) throws -> OnchainCrossChainOrder {
            let orderData = try encodeDispatchOrder(dispatchOrder)
            return OnchainCrossChainOrder(
                fillDeadline: fillDeadline,
                orderDataType: AAUtils.dispatchOrderTypeHash,
                orderData: orderData,
            )
        }

        /// ABI-encode a `dispatch((uint32,bytes32,bytes))` function call.
        public static func encodeCall(order: OnchainCrossChainOrder) throws -> Data {
            let orderTuple = try encodeOrderTuple(order)
            return ABIEncoder.functionCallOrdered(
                signature: "dispatch((uint32,bytes32,bytes))",
                arguments: [
                    .dynamic(orderTuple),
                ],
            )
        }

        /// Build a `Call` targeting the account's own `dispatch` function.
        public static func asCall(
            account: String,
            fillDeadline: UInt32,
            dispatchOrder: DispatchOrder,
            valueWei: String = "0",
        ) throws -> Call {
            let order = try buildOrder(fillDeadline: fillDeadline, dispatchOrder: dispatchOrder)
            let data = try encodeCall(order: order)
            return Call(
                to: account,
                dataHex: "0x" + data.toHexString(),
                valueWei: valueWei,
            )
        }

        private static func encodeOrderTuple(_ order: OnchainCrossChainOrder) throws -> Data {
            let fillDeadline = ABIWord.uint(BigUInt(order.fillDeadline))
            let orderType = try ABIWord.bytes32(order.orderDataType)
            let orderDataOffset = ABIWord.uint(BigUInt(96))
            let orderData = ABIEncoder.encodeBytes(order.orderData)
            return fillDeadline + orderType + orderDataOffset + orderData
        }

        private static func encodeDispatchOrder(_ order: DispatchOrder) throws -> Data {
            let salt = try ABIWord.bytes32(order.salt)
            let destChainId = ABIWord.uint(BigUInt(order.destChainId))
            let outputToken = try ABIWord.address(order.outputToken)
            let sumOutput = ABIWord.uint(order.sumOutput)
            let inputAmount = ABIWord.uint(order.inputAmount)
            let inputToken = try ABIWord.address(order.inputToken)
            let minOutput = ABIWord.uint(order.minOutput)
            return salt + destChainId + outputToken + sumOutput + inputAmount + inputToken + minOutput
        }
    }

    public enum Initialize {
        public static func encodeCall(
            passkeyPublicKey: PasskeyPublicKeyModel,
            config: InitializationConfig,
        ) throws -> Data {
            let qx = try ABIWord.bytes32(passkeyPublicKey.x)
            let qy = try ABIWord.bytes32(passkeyPublicKey.y)
            let accumulatorFactory = try ABIWord.address(config.accumulatorFactory)
            let spokePool = try ABIWord.address(config.spokePool)

            return ABIEncoder.functionCall(
                signature: "initialize(bytes32,bytes32,address,address)",
                words: [qx, qy, accumulatorFactory, spokePool],
                dynamic: [],
            )
        }

        public static func asCall(
            account: String,
            passkeyPublicKey: PasskeyPublicKeyModel,
            config: InitializationConfig,
        ) throws -> Call {
            try Call(
                to: account,
                dataHex: "0x"
                    + encodeCall(passkeyPublicKey: passkeyPublicKey, config: config)
                    .toHexString(),
                valueWei: "0",
            )
        }
    }

    public enum Accumulator {
        /// Hash `ExecutionParams` exactly as the on-chain Accumulator does (pre-domain EIP-712 struct hash).
        public static func hashExecutionParamsStruct(_ params: AccumulatorExecutionParams) throws -> Data {
            let salt = try ABIWord.bytes32(params.salt)
            let fillDeadline = ABIWord.uint(BigUInt(params.fillDeadline))
            let sumOutput = ABIWord.uint(params.sumOutput)
            let outputToken = try ABIWord.address(params.outputToken)
            let finalMinOutput = ABIWord.uint(params.finalMinOutput)
            let finalOutputToken = try ABIWord.address(params.finalOutputToken)
            let recipient = try ABIWord.address(params.recipient)
            let destinationCaller = try ABIWord.address(params.destinationCaller)
            let destCallsHash = try ABIWord.bytes32(hashCalls(params.destCalls))

            let encoded =
                AAUtils.executionParamsTypeHash
                    + salt
                    + fillDeadline
                    + sumOutput
                    + outputToken
                    + finalMinOutput
                    + finalOutputToken
                    + recipient
                    + destinationCaller
                    + destCallsHash
            return Data(encoded.sha3(.keccak256))
        }

        /// ABI-encode `executeIntent(ExecutionParams, bytes32[], bytes)` calldata.
        public static func encodeExecuteIntentCall(
            params: AccumulatorExecutionParams,
            merkleProof: [Data],
            signature: Data,
        ) throws -> Data {
            let paramsTuple = try encodeExecutionParamsTuple(params)
            let proofArray = try encodeMerkleProof(merkleProof)
            let signatureBytes = ABIEncoder.encodeBytes(signature)

            return ABIEncoder.functionCallOrdered(
                signature:
                "executeIntent((bytes32,uint32,uint256,address,uint256,address,address,address,(address,uint256,bytes)[]),bytes32[],bytes)",
                arguments: [
                    .dynamic(paramsTuple),
                    .dynamic(proofArray),
                    .dynamic(signatureBytes),
                ],
            )
        }

        public static func asCall(
            accumulator: String,
            params: AccumulatorExecutionParams,
            merkleProof: [Data],
            signature: Data,
        ) throws -> Call {
            let data = try encodeExecuteIntentCall(
                params: params,
                merkleProof: merkleProof,
                signature: signature,
            )
            return Call(
                to: accumulator,
                dataHex: "0x" + data.toHexString(),
                valueWei: "0",
            )
        }

        private static func hashCalls(_ calls: [Call]) throws -> Data {
            if calls.isEmpty {
                return Data(repeating: 0, count: 32)
            }

            var callHashes = Data()
            for call in calls {
                let target = try ABIWord.address(call.to)
                let value = try ABIWord.uint(call.valueWei)
                let dataBytes = try ABIWord.bytes(call.dataHex)
                let dataHash = Data(dataBytes.sha3(.keccak256))
                let dataHashWord = try ABIWord.bytes32(dataHash)
                let callHash = Data((target + value + dataHashWord).sha3(.keccak256))
                callHashes.append(callHash)
            }

            return Data(callHashes.sha3(.keccak256))
        }

        private static func encodeExecutionParamsTuple(_ params: AccumulatorExecutionParams) throws -> Data {
            let salt = try ABIWord.bytes32(params.salt)
            let fillDeadline = ABIWord.uint(BigUInt(params.fillDeadline))
            let sumOutput = ABIWord.uint(params.sumOutput)
            let outputToken = try ABIWord.address(params.outputToken)
            let finalMinOutput = ABIWord.uint(params.finalMinOutput)
            let finalOutputToken = try ABIWord.address(params.finalOutputToken)
            let recipient = try ABIWord.address(params.recipient)
            let destinationCaller = try ABIWord.address(params.destinationCaller)
            let encodedCalls = try ABIEncoder.encodeCallTupleArray(params.destCalls)

            // Tuple head has 9 slots; destCalls is dynamic and lives in the tail.
            let destCallsOffset = ABIWord.uint(BigUInt(9 * 32))

            return
                salt
                    + fillDeadline
                    + sumOutput
                    + outputToken
                    + finalMinOutput
                    + finalOutputToken
                    + recipient
                    + destinationCaller
                    + destCallsOffset
                    + encodedCalls
        }

        private static func encodeMerkleProof(_ proof: [Data]) throws -> Data {
            var out = ABIWord.uint(BigUInt(proof.count))
            for element in proof {
                try out.append(ABIWord.bytes32(element))
            }
            return out
        }
    }

    public enum AccumulatorFactory {
        public static func encodeComputeAddressCall(userAccount: String) throws -> Data {
            let userWord = try ABIWord.address(userAccount)
            return ABIEncoder.functionCall(
                signature: "computeAddress(address)",
                words: [userWord],
                dynamic: [],
            )
        }
    }

    public enum IsValidSignature {
        public static func encodeCall(hash: Data, signature: Data) throws -> Data {
            let hashWord = try ABIWord.bytes32(hash)
            let signatureBytes = ABIEncoder.encodeBytes(signature)
            return ABIEncoder.functionCall(
                signature: "isValidSignature(bytes32,bytes)",
                words: [hashWord],
                dynamic: [signatureBytes],
            )
        }
    }
}

public actor SmartAccountClient {
    private let rpcClient: RPCClient
    private static let validSignatureSelector = "0x1626ba7e"

    public init(rpcClient: RPCClient = RPCClient()) {
        self.rpcClient = rpcClient
    }

    public func isDeployed(account: String, chainId: UInt64) async throws -> Bool {
        let code = try await rpcClient.getCode(chainId: chainId, address: account)
        let normalized = code.lowercased()
        return normalized != "0x" && normalized != "0x0"
    }

    public func getTransactionCount(account: String, chainId: UInt64, blockTag: String = "pending") async throws
        -> UInt64
    {
        let nonceHex: String = try await rpcClient.makeRpcCall(
            chainId: chainId,
            method: "eth_getTransactionCount",
            params: [AnyCodable(account), AnyCodable(blockTag)],
            responseType: String.self,
        )
        let clean = nonceHex.replacingOccurrences(of: "0x", with: "")
        return UInt64(clean, radix: 16) ?? 0
    }

    public func isValidSignature(
        account: String,
        chainId: UInt64,
        hash: Data,
        passkeySignature: PasskeySignatureModel,
    ) async throws -> Bool {
        let authBytes = try passkeySignature.webAuthnAuthBytes(payload: hash)
        let calldata = try SmartAccount.IsValidSignature.encodeCall(hash: hash, signature: authBytes)
        let response = try await ethCallHex(account: account, chainId: chainId, data: calldata)
        return response.lowercased().hasPrefix(Self.validSignatureSelector)
    }

    public func computeAccumulatorAddress(
        account: String,
        chainId: UInt64,
    ) async throws -> String {
        let calldata = try SmartAccount.AccumulatorFactory.encodeComputeAddressCall(userAccount: account)
        let response = try await ethCallHex(
            account: AAConstants.accumulatorFactoryAddress,
            chainId: chainId,
            data: calldata,
        )
        return try ABIUtils.decodeAddressFromABIWord(response).lowercased()
    }

    public func simulateCall(
        account: String,
        chainId: UInt64,
        from: String,
        data: Data,
        valueHex: String = "0x0",
    ) async throws {
        let txObject: [String: Any] = [
            "to": account,
            "from": from,
            "data": "0x" + data.toHexString(),
            "value": AAUtils.normalizeHexQuantity(valueHex),
        ]
        let _: String = try await rpcClient.makeRpcCall(
            chainId: chainId,
            method: "eth_call",
            params: [AnyCodable(txObject), AnyCodable("latest")],
            responseType: String.self,
        )
    }

    public func estimateGas(
        account: String,
        chainId: UInt64,
        from: String,
        data: Data,
        valueHex: String = "0x0",
    ) async throws -> UInt64 {
        let txObject: [String: Any] = [
            "to": account,
            "from": from,
            "data": "0x" + data.toHexString(),
            "value": AAUtils.normalizeHexQuantity(valueHex),
        ]
        let gasHex: String = try await rpcClient.makeRpcCall(
            chainId: chainId,
            method: "eth_estimateGas",
            params: [AnyCodable(txObject)],
            responseType: String.self,
        )
        let clean = gasHex.replacingOccurrences(of: "0x", with: "")
        return UInt64(clean, radix: 16) ?? 0
    }

    private func ethCallHex(account: String, chainId: UInt64, data: Data) async throws -> String {
        let txObject: [String: Any] = [
            "to": account,
            "data": "0x" + data.toHexString(),
        ]
        return try await rpcClient.makeRpcCall(
            chainId: chainId,
            method: "eth_call",
            params: [AnyCodable(txObject), AnyCodable("latest")],
            responseType: String.self,
        )
    }
}
