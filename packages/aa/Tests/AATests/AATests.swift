@testable import AA
import BigInt
import Passkey
import RPC
import Transactions
import web3swift
import XCTest

final class AATests: XCTestCase {
    func testInit() {
        _ = SmartAccountClient()
    }

    // ═══════════════════════════════════════════════════════════════════════════
    //  ExecuteX tests
    // ═══════════════════════════════════════════════════════════════════════════

    func testExecuteXLeafHashVariesBySaltAndChain() throws {
        let calls = [
            Call(to: "0x0000000000000000000000000000000000000001", dataHex: "0xabcdef", valueWei: "42"),
        ]
        let account = "0x0000000000000000000000000000000000000abc"

        let hashA = try SmartAccount.ExecuteX.leafHash(
            account: account, chainId: 8453, calls: calls, salt: Data(repeating: 0x01, count: 32),
        )
        let hashB = try SmartAccount.ExecuteX.leafHash(
            account: account, chainId: 8453, calls: calls, salt: Data(repeating: 0x02, count: 32),
        )
        let hashC = try SmartAccount.ExecuteX.leafHash(
            account: account, chainId: 10, calls: calls, salt: Data(repeating: 0x01, count: 32),
        )

        XCTAssertEqual(hashA.count, 32)
        XCTAssertNotEqual(hashA, hashB, "Different salts should produce different leaves")
        XCTAssertNotEqual(hashA, hashC, "Different chains should produce different leaves")
    }

    func testExecuteXLeafHashVariesByAccount() throws {
        let calls = [
            Call(to: "0x0000000000000000000000000000000000000001", dataHex: "0x", valueWei: "0"),
        ]
        let salt = Data(repeating: 0xAA, count: 32)

        let hashA = try SmartAccount.ExecuteX.leafHash(
            account: "0x00000000000000000000000000000000000000aa", chainId: 8453, calls: calls,
            salt: salt,
        )
        let hashB = try SmartAccount.ExecuteX.leafHash(
            account: "0x00000000000000000000000000000000000000bb", chainId: 8453, calls: calls,
            salt: salt,
        )

        XCTAssertNotEqual(hashA, hashB, "Different accounts should produce different leaves")
    }

    func testExecuteXSingleLeafRootEqualsLeaf() {
        let leaf = Data(repeating: 0x42, count: 32)
        let root = SmartAccount.ExecuteX.rootForSingleLeaf(leaf)
        XCTAssertEqual(root, leaf)
    }

    func testExecuteXTwoLeavesRootIsCommutative() {
        let leafA = Data(repeating: 0x11, count: 32)
        let leafB = Data(repeating: 0x22, count: 32)

        let rootAB = SmartAccount.ExecuteX.rootForTwoLeaves(leafA, leafB)
        let rootBA = SmartAccount.ExecuteX.rootForTwoLeaves(leafB, leafA)

        XCTAssertEqual(rootAB, rootBA, "Merkle root should be commutative (OZ sorted pair)")
        XCTAssertNotEqual(rootAB, leafA, "Root should differ from either leaf")
    }

    func testExecuteXEncodeCallHasExpectedSelector() throws {
        let calls = [
            Call(to: "0x0000000000000000000000000000000000000001", dataHex: "0x", valueWei: "0"),
        ]
        let salt = Data(repeating: 0xBB, count: 32)
        let signature = Data(repeating: 0x99, count: 65)

        let encoded = try SmartAccount.ExecuteX.encodeCall(
            calls: calls, salt: salt, merkleProof: [], signature: signature,
        )

        let selector = Data("executeX((address,uint256,bytes)[],bytes32,bytes32[],bytes)".utf8)
            .sha3(.keccak256).prefix(4)
        XCTAssertEqual(encoded.prefix(4), selector)
        XCTAssertGreaterThan(encoded.count, 4 + 128) // at least 4 offset words
    }

    func testExecuteXSigningDigestWrapsRoot() {
        let root = Data(repeating: 0xFF, count: 32)
        let digest = SmartAccount.ExecuteX.signingDigest(root: root)

        // Should match toEthSignedMessageHash
        let expected = AAUtils.toEthSignedMessageHash(root)
        XCTAssertEqual(digest, expected)
    }

    // ═══════════════════════════════════════════════════════════════════════════
    //  Dispatch tests
    // ═══════════════════════════════════════════════════════════════════════════

    func testDispatchBuildOrderSetsCorrectTypeHash() throws {
        let order = DispatchOrder(
            salt: Data(repeating: 0x11, count: 32),
            destChainId: 42161,
            outputToken: "0x0000000000000000000000000000000000000001",
            sumOutput: BigUInt(100),
            inputAmount: BigUInt(110),
            inputToken: "0x0000000000000000000000000000000000000002",
            minOutput: BigUInt(100),
        )

        let envelope = try SmartAccount.Dispatch.buildOrder(fillDeadline: 12345, dispatchOrder: order)

        XCTAssertEqual(envelope.fillDeadline, 12345)
        XCTAssertEqual(envelope.orderDataType, AAUtils.dispatchOrderTypeHash)
        XCTAssertGreaterThan(envelope.orderData.count, 0)
    }

    func testDispatchEncodeCallHasExpectedSelector() throws {
        let envelope = OnchainCrossChainOrder(
            fillDeadline: 123,
            orderDataType: Data(repeating: 0x44, count: 32),
            orderData: Data([0xDE, 0xAD, 0xBE, 0xEF]),
        )

        let encoded = try SmartAccount.Dispatch.encodeCall(order: envelope)

        let selector = Data("dispatch((uint32,bytes32,bytes))".utf8).sha3(.keccak256).prefix(4)
        XCTAssertEqual(encoded.prefix(4), selector)
        XCTAssertGreaterThan(encoded.count, 4 + 32)
    }

    func testDispatchAsCallTargetsAccount() throws {
        let account = "0x0000000000000000000000000000000000000abc"
        let order = DispatchOrder(
            salt: Data(repeating: 0x22, count: 32),
            destChainId: 10,
            outputToken: "0x0000000000000000000000000000000000000001",
            sumOutput: BigUInt(50),
            inputAmount: BigUInt(55),
            inputToken: "0x0000000000000000000000000000000000000002",
            minOutput: BigUInt(50),
        )

        let call = try SmartAccount.Dispatch.asCall(
            account: account, fillDeadline: 99999, dispatchOrder: order,
        )

        XCTAssertEqual(call.to, account)
        XCTAssertEqual(call.valueWei, "0")
        XCTAssertTrue(call.dataHex.hasPrefix("0x"))
    }

    // ═══════════════════════════════════════════════════════════════════════════
    //  Initialize tests
    // ═══════════════════════════════════════════════════════════════════════════

    func testInitializeEncodingLayout() throws {
        let passkey = PasskeyPublicKeyModel(
            x: Data(repeating: 0x01, count: 32),
            y: Data(repeating: 0x02, count: 32),
            credentialID: Data([0xAA]),
        )
        let config = InitializationConfig(
            accumulatorFactory: "0x00000000000000000000000000000000000000f1",
            spokePool: "0x00000000000000000000000000000000000000f3",
        )

        let encoded = try SmartAccount.Initialize.encodeCall(
            passkeyPublicKey: passkey,
            config: config,
        )

        let selector = Data("initialize(bytes32,bytes32,address,address)".utf8).sha3(.keccak256).prefix(
            4,
        )
        XCTAssertEqual(encoded.prefix(4), selector)
        XCTAssertEqual(word(encoded, 0), passkey.x)
        XCTAssertEqual(word(encoded, 1), passkey.y)
        XCTAssertEqual(word(encoded, 2), try ABIWord.address(config.accumulatorFactory))
        XCTAssertEqual(word(encoded, 3), try ABIWord.address(config.spokePool))
    }

    // ═══════════════════════════════════════════════════════════════════════════
    //  Auxiliary encoder tests
    // ═══════════════════════════════════════════════════════════════════════════

    func testAuxiliaryEncodersHaveExpectedSelectors() throws {
        let accumulatorCall = try SmartAccount.AccumulatorFactory.encodeComputeAddressCall(
            userAccount: "0x0000000000000000000000000000000000000001",
        )
        let accumulatorSelector = Data("computeAddress(address)".utf8).sha3(.keccak256).prefix(4)
        XCTAssertEqual(accumulatorCall.prefix(4), accumulatorSelector)

        let sigCall = try SmartAccount.IsValidSignature.encodeCall(
            hash: Data(repeating: 0x77, count: 32),
            signature: Data(repeating: 0x88, count: 65),
        )
        let sigSelector = Data("isValidSignature(bytes32,bytes)".utf8).sha3(.keccak256).prefix(4)
        XCTAssertEqual(sigCall.prefix(4), sigSelector)
    }

    func testComputeAccumulatorAddressUsesFactoryEthCall() async throws {
        let expected = "0x00000000000000000000000000000000000000aa"
        let transport = StubTransport(codeByChain: [:], accumulatorByChain: [8453: expected])
        let rpcClient = RPCClient(
            resolver: StaticRPCEndpointResolverService(
                endpointsByChain: [8453: ChainEndpointsModel(rpcURL: "https://stub.local/8453")],
            ),
            transport: transport,
        )
        let client = SmartAccountClient(rpcClient: rpcClient)

        let address = try await client.computeAccumulatorAddress(
            account: "0x0000000000000000000000000000000000000abc",
            chainId: 8453,
        )

        XCTAssertEqual(address, expected)
    }

    func testExecuteXPlannerPrependsInitializeForUndeployedChain() async throws {
        let transport = StubTransport(codeByChain: [8453: "0x"])
        let rpcClient = RPCClient(
            resolver: StaticRPCEndpointResolverService(
                endpointsByChain: [8453: ChainEndpointsModel(rpcURL: "https://stub.local/8453")],
            ),
            transport: transport,
        )
        let planner = ExecuteXPlanner(smartAccountClient: SmartAccountClient(rpcClient: rpcClient))

        let account = "0x0000000000000000000000000000000000000abc"
        let passkey = PasskeyPublicKeyModel(
            x: Data(repeating: 0x01, count: 32),
            y: Data(repeating: 0x02, count: 32),
            credentialID: Data([0xAA]),
        )
        let auth = RelayAuthorizationModel(
            address: "0x0000000000000000000000000000000000000def",
            chainId: 8453,
            nonce: 0,
            r: "0x" + String(repeating: "11", count: 32),
            s: "0x" + String(repeating: "22", count: 32),
            yParity: 1,
        )
        let leaf = ExecuteXLeafRequest(
            chainId: 8453,
            payload: .executeCalls([
                Call(
                    to: "0x0000000000000000000000000000000000000001",
                    dataHex: "0xabcdef",
                    valueWei: "0",
                ),
            ]),
        )

        let plan = try await planner.buildPlan(
            request: ExecuteXPlanRequest(
                account: account,
                passkeyPublicKey: passkey,
                leaves: [leaf],
                authorizationsByChainId: [8453: auth],
            ),
            signRoot: { _ in Data(repeating: 0x99, count: 65) },
        )

        XCTAssertEqual(plan.immediateRelayTxs.count, 1)
        XCTAssertEqual(plan.backgroundRelayTxs.count, 0)
        XCTAssertEqual(plan.deferredRelayTxs.count, 0)
        XCTAssertEqual(plan.accumulatorExecutions.count, 0)

        guard case let .execute(executeLeaf) = plan.leaves[0].payload else {
            XCTFail("Expected execute leaf")
            return
        }
        XCTAssertTrue(executeLeaf.didAppendInitializeCall)
        XCTAssertTrue(executeLeaf.authorizationRequired)
        XCTAssertEqual(executeLeaf.relayTx.request.authorizationList, [auth])
        XCTAssertEqual(executeLeaf.calls.count, 2)

        let initSelector = Data("initialize(bytes32,bytes32,address,address)".utf8).sha3(.keccak256)
            .prefix(4)
        let firstCallData = Data.fromHex(String(executeLeaf.calls[0].dataHex.dropFirst(2))) ?? Data()
        XCTAssertEqual(firstCallData.prefix(4), initSelector)
    }

    func testExecuteXPlannerIncludesAccumulatorIntentLeaf() async throws {
        let transport = StubTransport(codeByChain: [8453: "0x01"])
        let rpcClient = RPCClient(
            resolver: StaticRPCEndpointResolverService(
                endpointsByChain: [
                    8453: ChainEndpointsModel(rpcURL: "https://stub.local/8453"),
                    10: ChainEndpointsModel(rpcURL: "https://stub.local/10"),
                ],
            ),
            transport: transport,
        )
        let planner = ExecuteXPlanner(smartAccountClient: SmartAccountClient(rpcClient: rpcClient))

        let account = "0x0000000000000000000000000000000000000abc"
        let passkey = PasskeyPublicKeyModel(
            x: Data(repeating: 0x01, count: 32),
            y: Data(repeating: 0x02, count: 32),
            credentialID: Data([0xAA]),
        )

        let executeLeaf = ExecuteXLeafRequest(
            chainId: 8453,
            mode: .immediate,
            payload: .executeCalls([
                Call(to: "0x0000000000000000000000000000000000000001", dataHex: "0x1234", valueWei: "0"),
            ]),
        )
        let accumulatorParams = AccumulatorExecutionParams(
            salt: Data(repeating: 0x10, count: 32),
            fillDeadline: 1_700_000_000,
            sumOutput: BigUInt(1_000_000),
            outputToken: "0x0000000000000000000000000000000000000002",
            finalMinOutput: BigUInt(900_000),
            finalOutputToken: "0x0000000000000000000000000000000000000002",
            recipient: "0x0000000000000000000000000000000000000003",
            destinationCaller: "0x0000000000000000000000000000000000000000",
            destCalls: [],
        )
        let accumulatorLeaf = ExecuteXLeafRequest(
            chainId: 10,
            mode: .deferred,
            payload: .accumulatorIntent(
                AccumulatorExecutionIntent(
                    accumulator: "0x00000000000000000000000000000000000000aa",
                    params: accumulatorParams,
                ),
            ),
        )

        let plan = try await planner.buildPlan(
            request: ExecuteXPlanRequest(
                account: account,
                passkeyPublicKey: passkey,
                leaves: [executeLeaf, accumulatorLeaf],
            ),
            signRoot: { _ in Data(repeating: 0x77, count: 65) },
        )

        XCTAssertEqual(plan.leaves.count, 2)
        XCTAssertEqual(plan.immediateRelayTxs.count, 1)
        XCTAssertEqual(plan.deferredRelayTxs.count, 1)
        XCTAssertEqual(plan.accumulatorExecutions.count, 1)
        XCTAssertEqual(plan.accumulatorExecutions[0].mode, .deferred)
        XCTAssertEqual(
            plan.accumulatorExecutions[0].executeIntentCall.to,
            "0x00000000000000000000000000000000000000aa",
        )
        XCTAssertEqual(plan.accumulatorExecutions[0].merkleProof.count, 1)
    }

    func testExecuteXPlannerSingleChainUsesLeafAsRootAndEmptyProof() async throws {
        let transport = StubTransport(codeByChain: [8453: "0x01"])
        let rpcClient = RPCClient(
            resolver: StaticRPCEndpointResolverService(
                endpointsByChain: [8453: ChainEndpointsModel(rpcURL: "https://stub.local/8453")],
            ),
            transport: transport,
        )
        let planner = ExecuteXPlanner(smartAccountClient: SmartAccountClient(rpcClient: rpcClient))

        let account = "0x0000000000000000000000000000000000000abc"
        let passkey = PasskeyPublicKeyModel(
            x: Data(repeating: 0x01, count: 32),
            y: Data(repeating: 0x02, count: 32),
            credentialID: Data([0xAA]),
        )
        let expectedSignature = Data(repeating: 0x55, count: 65)

        let plan = try await planner.buildPlan(
            request: ExecuteXPlanRequest(
                account: account,
                passkeyPublicKey: passkey,
                leaves: [
                    ExecuteXLeafRequest(
                        chainId: 8453,
                        payload: .executeCalls([
                            Call(
                                to: "0x0000000000000000000000000000000000000001",
                                dataHex: "0x1234",
                                valueWei: "0",
                            ),
                        ]),
                    ),
                ],
            ),
            signRoot: { _ in expectedSignature },
        )

        XCTAssertEqual(plan.signature, expectedSignature)
        XCTAssertEqual(plan.leaves.count, 1)
        XCTAssertEqual(plan.immediateRelayTxs.count, 1)

        guard case let .execute(executeLeaf) = plan.leaves[0].payload else {
            XCTFail("Expected execute leaf")
            return
        }
        XCTAssertEqual(plan.merkleRoot, executeLeaf.leafHash)
        XCTAssertTrue(executeLeaf.merkleProof.isEmpty)
        XCTAssertTrue(executeLeaf.relayTx.request.authorizationList.isEmpty)
    }

    func testExecuteXPlannerBuildFlowPlanMergesCallsByChain() async throws {
        let transport = StubTransport(codeByChain: [8453: "0x01"])
        let rpcClient = RPCClient(
            resolver: StaticRPCEndpointResolverService(
                endpointsByChain: [8453: ChainEndpointsModel(rpcURL: "https://stub.local/8453")],
            ),
            transport: transport,
        )
        let planner = ExecuteXPlanner(smartAccountClient: SmartAccountClient(rpcClient: rpcClient))

        let account = "0x0000000000000000000000000000000000000abc"
        let passkey = PasskeyPublicKeyModel(
            x: Data(repeating: 0x01, count: 32),
            y: Data(repeating: 0x02, count: 32),
            credentialID: Data([0xAA]),
        )

        let plan = try await planner.buildFlowPlan(
            request: ExecuteXFlowPlanRequest(
                account: account,
                passkeyPublicKey: passkey,
                destinationChainId: 8453,
                chainActions: [
                    ExecuteXChainAction(
                        chainId: 8453,
                        calls: [
                            Call(
                                to: "0x0000000000000000000000000000000000000001", dataHex: "0xaaaa", valueWei: "0",
                            ),
                        ],
                    ),
                    ExecuteXChainAction(
                        chainId: 8453,
                        calls: [
                            Call(
                                to: "0x0000000000000000000000000000000000000002", dataHex: "0xbbbb", valueWei: "0",
                            ),
                        ],
                    ),
                ],
            ),
            signRoot: { _ in Data(repeating: 0x11, count: 65) },
        )

        XCTAssertEqual(plan.leaves.count, 1)
        guard case let .execute(executeLeaf) = plan.leaves[0].payload else {
            XCTFail("Expected execute leaf")
            return
        }
        XCTAssertEqual(executeLeaf.calls.count, 2)
        XCTAssertEqual(executeLeaf.mode, .immediate)
        XCTAssertEqual(plan.immediateRelayTxs.count, 1)
        XCTAssertEqual(plan.backgroundRelayTxs.count, 0)
    }

    func testExecuteXPlannerAccumulatorOnlyDeployedChainSkipsSyntheticInitialize() async throws {
        let transport = StubTransport(codeByChain: [10: "0x01"])
        let rpcClient = RPCClient(
            resolver: StaticRPCEndpointResolverService(
                endpointsByChain: [10: ChainEndpointsModel(rpcURL: "https://stub.local/10")],
            ),
            transport: transport,
        )
        let planner = ExecuteXPlanner(smartAccountClient: SmartAccountClient(rpcClient: rpcClient))

        let account = "0x0000000000000000000000000000000000000abc"
        let passkey = PasskeyPublicKeyModel(
            x: Data(repeating: 0x01, count: 32),
            y: Data(repeating: 0x02, count: 32),
            credentialID: Data([0xAA]),
        )
        let accumulatorLeaf = ExecuteXLeafRequest(
            chainId: 10,
            mode: .deferred,
            payload: .accumulatorIntent(
                AccumulatorExecutionIntent(
                    accumulator: "0x00000000000000000000000000000000000000aa",
                    params: AccumulatorExecutionParams(
                        salt: Data(repeating: 0x33, count: 32),
                        fillDeadline: 1_700_000_000,
                        sumOutput: BigUInt(1_000_000),
                        outputToken: "0x0000000000000000000000000000000000000002",
                        finalMinOutput: BigUInt(900_000),
                        finalOutputToken: "0x0000000000000000000000000000000000000002",
                        recipient: "0x0000000000000000000000000000000000000003",
                        destinationCaller: "0x0000000000000000000000000000000000000000",
                        destCalls: [],
                    ),
                ),
            ),
        )

        let plan = try await planner.buildPlan(
            request: ExecuteXPlanRequest(
                account: account,
                passkeyPublicKey: passkey,
                leaves: [accumulatorLeaf],
            ),
            signRoot: { _ in Data(repeating: 0x77, count: 65) },
        )

        let executeLeafCount = plan.leaves.count(where: {
            if case .execute = $0.payload { return true }
            return false
        })

        XCTAssertEqual(executeLeafCount, 0)
        XCTAssertEqual(plan.immediateRelayTxs.count, 0)
        XCTAssertEqual(plan.deferredRelayTxs.count, 1)
        XCTAssertEqual(plan.accumulatorExecutions.count, 1)
    }

    func testExecuteXPlannerAddsPriorityInitializeForAccumulatorOnlyUndeployedChain() async throws {
        let transport = StubTransport(codeByChain: [10: "0x"])
        let rpcClient = RPCClient(
            resolver: StaticRPCEndpointResolverService(
                endpointsByChain: [10: ChainEndpointsModel(rpcURL: "https://stub.local/10")],
            ),
            transport: transport,
        )
        let planner = ExecuteXPlanner(smartAccountClient: SmartAccountClient(rpcClient: rpcClient))

        let account = "0x0000000000000000000000000000000000000abc"
        let passkey = PasskeyPublicKeyModel(
            x: Data(repeating: 0x01, count: 32),
            y: Data(repeating: 0x02, count: 32),
            credentialID: Data([0xAA]),
        )
        let auth = RelayAuthorizationModel(
            address: "0x0000000000000000000000000000000000000def",
            chainId: 10,
            nonce: 0,
            r: "0x" + String(repeating: "11", count: 32),
            s: "0x" + String(repeating: "22", count: 32),
            yParity: 1,
        )
        let accumulatorParams = AccumulatorExecutionParams(
            salt: Data(repeating: 0x44, count: 32),
            fillDeadline: 1_700_000_000,
            sumOutput: BigUInt(1_000_000),
            outputToken: "0x0000000000000000000000000000000000000002",
            finalMinOutput: BigUInt(900_000),
            finalOutputToken: "0x0000000000000000000000000000000000000002",
            recipient: "0x0000000000000000000000000000000000000003",
            destinationCaller: "0x0000000000000000000000000000000000000000",
            destCalls: [],
        )
        let accumulatorLeaf = ExecuteXLeafRequest(
            chainId: 10,
            mode: .deferred,
            payload: .accumulatorIntent(
                AccumulatorExecutionIntent(
                    accumulator: "0x00000000000000000000000000000000000000aa",
                    params: accumulatorParams,
                ),
            ),
        )

        let plan = try await planner.buildPlan(
            request: ExecuteXPlanRequest(
                account: account,
                passkeyPublicKey: passkey,
                leaves: [accumulatorLeaf],
                authorizationsByChainId: [10: auth],
            ),
            signRoot: { _ in Data(repeating: 0x66, count: 65) },
        )

        XCTAssertEqual(plan.accumulatorExecutions.count, 1)
        XCTAssertEqual(plan.immediateRelayTxs.count, 1)
        XCTAssertEqual(plan.backgroundRelayTxs.count, 0)
        XCTAssertEqual(plan.deferredRelayTxs.count, 1)

        guard
            let initLeaf = plan.leaves.compactMap({ leaf -> PlannedExecuteXCall? in
                if case let .execute(execute) = leaf.payload {
                    return execute
                }
                return nil
            }).first
        else {
            XCTFail("Expected synthetic initialize execute leaf")
            return
        }

        XCTAssertEqual(initLeaf.mode, .immediate)
        XCTAssertEqual(initLeaf.chainId, 10)
        XCTAssertTrue(initLeaf.didAppendInitializeCall)
        XCTAssertTrue(initLeaf.authorizationRequired)
        XCTAssertEqual(initLeaf.relayTx.request.authorizationList, [auth])
        XCTAssertEqual(initLeaf.calls.count, 1)
    }

    func testExecuteXPlannerAccumulatorOnlyUndeployedChainRequiresAuthorization() async throws {
        let transport = StubTransport(codeByChain: [10: "0x"])
        let rpcClient = RPCClient(
            resolver: StaticRPCEndpointResolverService(
                endpointsByChain: [10: ChainEndpointsModel(rpcURL: "https://stub.local/10")],
            ),
            transport: transport,
        )
        let planner = ExecuteXPlanner(smartAccountClient: SmartAccountClient(rpcClient: rpcClient))

        let account = "0x0000000000000000000000000000000000000abc"
        let passkey = PasskeyPublicKeyModel(
            x: Data(repeating: 0x01, count: 32),
            y: Data(repeating: 0x02, count: 32),
            credentialID: Data([0xAA]),
        )
        let accumulatorParams = AccumulatorExecutionParams(
            salt: Data(repeating: 0x44, count: 32),
            fillDeadline: 1_700_000_000,
            sumOutput: BigUInt(1_000_000),
            outputToken: "0x0000000000000000000000000000000000000002",
            finalMinOutput: BigUInt(900_000),
            finalOutputToken: "0x0000000000000000000000000000000000000002",
            recipient: "0x0000000000000000000000000000000000000003",
            destinationCaller: "0x0000000000000000000000000000000000000000",
            destCalls: [],
        )
        let accumulatorLeaf = ExecuteXLeafRequest(
            chainId: 10,
            mode: .deferred,
            payload: .accumulatorIntent(
                AccumulatorExecutionIntent(
                    accumulator: "0x00000000000000000000000000000000000000aa",
                    params: accumulatorParams,
                ),
            ),
        )

        do {
            _ = try await planner.buildPlan(
                request: ExecuteXPlanRequest(
                    account: account,
                    passkeyPublicKey: passkey,
                    leaves: [accumulatorLeaf],
                    authorizationsByChainId: [:],
                ),
                signRoot: { _ in Data(repeating: 0x66, count: 65) },
            )
            XCTFail("Expected missingAuthorization error")
        } catch let error as ExecuteXPlannerError {
            guard case let .missingAuthorization(chainId) = error else {
                XCTFail("Unexpected planner error: \(error)")
                return
            }
            XCTAssertEqual(chainId, 10)
        }
    }

    func testExecuteXPlannerBuildFlowPlanRoutesDestinationAndAccumulatorModes() async throws {
        let transport = StubTransport(codeByChain: [8453: "0x01", 10: "0x01"])
        let rpcClient = RPCClient(
            resolver: StaticRPCEndpointResolverService(
                endpointsByChain: [
                    8453: ChainEndpointsModel(rpcURL: "https://stub.local/8453"),
                    10: ChainEndpointsModel(rpcURL: "https://stub.local/10"),
                ],
            ),
            transport: transport,
        )
        let planner = ExecuteXPlanner(smartAccountClient: SmartAccountClient(rpcClient: rpcClient))

        let account = "0x0000000000000000000000000000000000000abc"
        let passkey = PasskeyPublicKeyModel(
            x: Data(repeating: 0x01, count: 32),
            y: Data(repeating: 0x02, count: 32),
            credentialID: Data([0xAA]),
        )
        let accumulatorParams = AccumulatorExecutionParams(
            salt: Data(repeating: 0x22, count: 32),
            fillDeadline: 1_700_000_000,
            sumOutput: BigUInt(1_000_000),
            outputToken: "0x0000000000000000000000000000000000000002",
            finalMinOutput: BigUInt(900_000),
            finalOutputToken: "0x0000000000000000000000000000000000000002",
            recipient: "0x0000000000000000000000000000000000000003",
            destinationCaller: "0x0000000000000000000000000000000000000000",
            destCalls: [],
        )

        let plan = try await planner.buildFlowPlan(
            request: ExecuteXFlowPlanRequest(
                account: account,
                passkeyPublicKey: passkey,
                destinationChainId: 10,
                chainActions: [
                    ExecuteXChainAction(
                        chainId: 8453,
                        calls: [
                            Call(
                                to: "0x0000000000000000000000000000000000000001", dataHex: "0x1234", valueWei: "0",
                            ),
                        ],
                    ),
                    ExecuteXChainAction(
                        chainId: 10,
                        calls: [
                            Call(
                                to: "0x0000000000000000000000000000000000000001", dataHex: "0xabcd", valueWei: "0",
                            ),
                        ],
                    ),
                ],
                destinationAccumulatorIntent: AccumulatorExecutionIntent(
                    accumulator: "0x00000000000000000000000000000000000000aa",
                    params: accumulatorParams,
                ),
            ),
            signRoot: { _ in Data(repeating: 0x77, count: 65) },
        )

        XCTAssertEqual(plan.immediateRelayTxs.count, 1)
        XCTAssertEqual(plan.backgroundRelayTxs.count, 1)
        XCTAssertEqual(plan.deferredRelayTxs.count, 1)
        XCTAssertEqual(plan.leaves.count, 3)

        let destinationExecute = plan.leaves.compactMap { leaf -> PlannedExecuteXCall? in
            guard case let .execute(execute) = leaf.payload, execute.chainId == 10 else { return nil }
            return execute
        }
        XCTAssertEqual(destinationExecute.count, 1)
        XCTAssertEqual(destinationExecute.first?.mode, .immediate)

        XCTAssertEqual(plan.accumulatorExecutions.count, 1)
        XCTAssertEqual(plan.accumulatorExecutions.first?.mode, .deferred)
    }

    func testExecuteXPlannerDestinationInitOnlyIsImmediateBeforeBackgroundWhenUndeployed() async throws {
        let transport = StubTransport(codeByChain: [8453: "0x01", 10: "0x"])
        let rpcClient = RPCClient(
            resolver: StaticRPCEndpointResolverService(
                endpointsByChain: [
                    8453: ChainEndpointsModel(rpcURL: "https://stub.local/8453"),
                    10: ChainEndpointsModel(rpcURL: "https://stub.local/10"),
                ],
            ),
            transport: transport,
        )
        let planner = ExecuteXPlanner(smartAccountClient: SmartAccountClient(rpcClient: rpcClient))

        let account = "0x0000000000000000000000000000000000000abc"
        let passkey = PasskeyPublicKeyModel(
            x: Data(repeating: 0x01, count: 32),
            y: Data(repeating: 0x02, count: 32),
            credentialID: Data([0xAA]),
        )
        let auth = RelayAuthorizationModel(
            address: "0x0000000000000000000000000000000000000def",
            chainId: 10,
            nonce: 0,
            r: "0x" + String(repeating: "11", count: 32),
            s: "0x" + String(repeating: "22", count: 32),
            yParity: 1,
        )

        let accumulatorParams = AccumulatorExecutionParams(
            salt: Data(repeating: 0x22, count: 32),
            fillDeadline: 1_700_000_000,
            sumOutput: BigUInt(1_000_000),
            outputToken: "0x0000000000000000000000000000000000000002",
            finalMinOutput: BigUInt(900_000),
            finalOutputToken: "0x0000000000000000000000000000000000000002",
            recipient: "0x0000000000000000000000000000000000000003",
            destinationCaller: "0x0000000000000000000000000000000000000000",
            destCalls: [],
        )

        let plan = try await planner.buildFlowPlan(
            request: ExecuteXFlowPlanRequest(
                account: account,
                passkeyPublicKey: passkey,
                destinationChainId: 10,
                chainActions: [
                    ExecuteXChainAction(
                        chainId: 8453,
                        calls: [
                            Call(
                                to: "0x0000000000000000000000000000000000000001", dataHex: "0x1234", valueWei: "0",
                            ),
                        ],
                    ),
                ],
                destinationAccumulatorIntent: AccumulatorExecutionIntent(
                    accumulator: "0x00000000000000000000000000000000000000aa",
                    params: accumulatorParams,
                ),
                authorizationsByChainId: [10: auth],
            ),
            signRoot: { _ in Data(repeating: 0x77, count: 65) },
        )

        XCTAssertEqual(plan.immediateRelayTxs.count, 1)
        XCTAssertEqual(plan.backgroundRelayTxs.count, 1)
        XCTAssertEqual(plan.deferredRelayTxs.count, 1)

        let destinationInitLeaf = plan.leaves.compactMap { leaf -> PlannedExecuteXCall? in
            guard case let .execute(execute) = leaf.payload, execute.chainId == 10 else { return nil }
            return execute
        }.first
        XCTAssertNotNil(destinationInitLeaf)
        XCTAssertEqual(destinationInitLeaf?.mode, .immediate)
        XCTAssertEqual(destinationInitLeaf?.calls.count, 1)
        XCTAssertEqual(destinationInitLeaf?.relayTx.request.authorizationList, [auth])

        let sourceExecuteLeaf = plan.leaves.compactMap { leaf -> PlannedExecuteXCall? in
            guard case let .execute(execute) = leaf.payload, execute.chainId == 8453 else { return nil }
            return execute
        }.first
        XCTAssertNotNil(sourceExecuteLeaf)
        XCTAssertEqual(sourceExecuteLeaf?.mode, .background)
        XCTAssertTrue(sourceExecuteLeaf?.relayTx.request.authorizationList.isEmpty ?? false)
    }

    func testExecuteXPlannerDestinationUndeployedWithCallsPrependsInitAndStaysImmediate() async throws {
        let transport = StubTransport(codeByChain: [8453: "0x01", 10: "0x"])
        let rpcClient = RPCClient(
            resolver: StaticRPCEndpointResolverService(
                endpointsByChain: [
                    8453: ChainEndpointsModel(rpcURL: "https://stub.local/8453"),
                    10: ChainEndpointsModel(rpcURL: "https://stub.local/10"),
                ],
            ),
            transport: transport,
        )
        let planner = ExecuteXPlanner(smartAccountClient: SmartAccountClient(rpcClient: rpcClient))

        let account = "0x0000000000000000000000000000000000000abc"
        let passkey = PasskeyPublicKeyModel(
            x: Data(repeating: 0x01, count: 32),
            y: Data(repeating: 0x02, count: 32),
            credentialID: Data([0xAA]),
        )
        let auth = RelayAuthorizationModel(
            address: "0x0000000000000000000000000000000000000def",
            chainId: 10,
            nonce: 0,
            r: "0x" + String(repeating: "11", count: 32),
            s: "0x" + String(repeating: "22", count: 32),
            yParity: 1,
        )
        let accumulatorParams = AccumulatorExecutionParams(
            salt: Data(repeating: 0x22, count: 32),
            fillDeadline: 1_700_000_000,
            sumOutput: BigUInt(1_000_000),
            outputToken: "0x0000000000000000000000000000000000000002",
            finalMinOutput: BigUInt(900_000),
            finalOutputToken: "0x0000000000000000000000000000000000000002",
            recipient: "0x0000000000000000000000000000000000000003",
            destinationCaller: "0x0000000000000000000000000000000000000000",
            destCalls: [],
        )

        let plan = try await planner.buildFlowPlan(
            request: ExecuteXFlowPlanRequest(
                account: account,
                passkeyPublicKey: passkey,
                destinationChainId: 10,
                chainActions: [
                    ExecuteXChainAction(
                        chainId: 8453,
                        calls: [
                            Call(
                                to: "0x0000000000000000000000000000000000000001", dataHex: "0x1234", valueWei: "0",
                            ),
                        ],
                    ),
                    ExecuteXChainAction(
                        chainId: 10,
                        calls: [
                            Call(
                                to: "0x0000000000000000000000000000000000000002", dataHex: "0xabcd", valueWei: "0",
                            ),
                        ],
                    ),
                ],
                destinationAccumulatorIntent: AccumulatorExecutionIntent(
                    accumulator: "0x00000000000000000000000000000000000000aa",
                    params: accumulatorParams,
                ),
                authorizationsByChainId: [10: auth],
            ),
            signRoot: { _ in Data(repeating: 0x77, count: 65) },
        )

        XCTAssertEqual(plan.immediateRelayTxs.count, 1)
        XCTAssertEqual(plan.backgroundRelayTxs.count, 1)
        XCTAssertEqual(plan.deferredRelayTxs.count, 1)

        let destinationExecuteLeaf = plan.leaves.compactMap { leaf -> PlannedExecuteXCall? in
            guard case let .execute(execute) = leaf.payload, execute.chainId == 10 else { return nil }
            return execute
        }.first
        XCTAssertNotNil(destinationExecuteLeaf)
        XCTAssertEqual(destinationExecuteLeaf?.mode, .immediate)
        XCTAssertEqual(destinationExecuteLeaf?.calls.count, 2)
        XCTAssertEqual(destinationExecuteLeaf?.relayTx.request.authorizationList, [auth])

        let initSelector = Data("initialize(bytes32,bytes32,address,address)".utf8).sha3(.keccak256)
            .prefix(4)
        let destinationFirstCall = Data.fromHex(
            String((destinationExecuteLeaf?.calls.first?.dataHex ?? "0x").dropFirst(2)),
        ) ?? Data()
        XCTAssertEqual(destinationFirstCall.prefix(4), initSelector)
    }

    // ═══════════════════════════════════════════════════════════════════════════
    //  Helpers
    // ═══════════════════════════════════════════════════════════════════════════

    private func word(_ data: Data, _ index: Int) -> Data {
        let start = 4 + (index * 32)
        return data.subdata(in: start ..< (start + 32))
    }
}

private struct StubTransport: JSONRPCTransportProviding, Sendable {
    let codeByChain: [UInt64: String]
    let accumulatorByChain: [UInt64: String]

    init(codeByChain: [UInt64: String], accumulatorByChain: [UInt64: String] = [:]) {
        self.codeByChain = codeByChain
        self.accumulatorByChain = accumulatorByChain
    }

    func send<Response: Decodable>(
        urlString: String,
        method: String,
        params _: [AnyCodable],
        requestID _: Int,
        responseType _: Response.Type,
    ) async throws -> Response {
        let chainId = UInt64(urlString.split(separator: "/").last ?? "") ?? 0
        let value: String

        switch method {
        case "eth_getCode":
            value = codeByChain[chainId] ?? "0x01"
        case "eth_call":
            let raw = accumulatorByChain[chainId] ?? "0x0000000000000000000000000000000000000000"
            let clean = raw.replacingOccurrences(of: "0x", with: "").lowercased()
            value = "0x" + String(repeating: "0", count: 24) + clean
        default:
            throw RPCError.rpcError(code: -1, message: "Unsupported method in stub: \(method)")
        }

        guard let result = value as? Response else {
            throw RPCError.rpcError(code: -1, message: "Stub response type mismatch")
        }
        return result
    }
}
