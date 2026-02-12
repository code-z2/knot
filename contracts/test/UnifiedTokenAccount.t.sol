// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {UnifiedTokenAccount} from "../src/UnifiedTokenAccount.sol";
import {AccumulatorFactory} from "../src/AccumulatorFactory.sol";
import {ISpokePool} from "../src/interfaces/ISpokePool.sol";
import {IWeth} from "../src/interfaces/IWeth.sol";
import {Call, ChainCalls, OnchainCrossChainOrder, SuperIntentData} from "../src/types/Structs.sol";

contract MockERC20ForAccount {
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        require(balanceOf[msg.sender] >= amount, "balance");
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        uint256 current = allowance[from][msg.sender];
        require(current >= amount, "allowance");
        require(balanceOf[from] >= amount, "balance");
        allowance[from][msg.sender] = current - amount;
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        return true;
    }
}

contract MockWethForAccount is IWeth {
    mapping(address => uint256) public override balanceOf;

    function withdraw(uint256 wad) external override {
        require(balanceOf[msg.sender] >= wad, "balance");
        balanceOf[msg.sender] -= wad;
        (bool ok,) = msg.sender.call{value: wad}("");
        require(ok, "eth");
    }

    function deposit() external payable override {
        balanceOf[msg.sender] += msg.value;
    }

    function transfer(address guy, uint256 wad) external override returns (bool) {
        require(balanceOf[msg.sender] >= wad, "balance");
        balanceOf[msg.sender] -= wad;
        balanceOf[guy] += wad;
        return true;
    }

    receive() external payable {}
}

    contract MockSpokePoolForAccount is ISpokePool {
        struct DepositCall {
            bytes32 depositor;
            bytes32 recipient;
            bytes32 inputToken;
            bytes32 outputToken;
            uint256 inputAmount;
            uint256 outputAmount;
            uint256 destinationChainId;
            bytes32 exclusiveRelayer;
            uint32 quoteTimestamp;
            uint32 fillDeadline;
            uint32 exclusivityDeadline;
            bytes message;
            uint256 value;
        }

        uint256 public depositCallCount;
        DepositCall public lastDeposit;

        function deposit(
            bytes32 depositor,
            bytes32 recipient,
            bytes32 inputToken,
            bytes32 outputToken,
            uint256 inputAmount,
            uint256 outputAmount,
            uint256 destinationChainId,
            bytes32 exclusiveRelayer,
            uint32 quoteTimestamp,
            uint32 fillDeadline,
            uint32 exclusivityDeadline,
            bytes calldata message
        ) external payable override {
            depositCallCount++;
            lastDeposit = DepositCall({
                depositor: depositor,
                recipient: recipient,
                inputToken: inputToken,
                outputToken: outputToken,
                inputAmount: inputAmount,
                outputAmount: outputAmount,
                destinationChainId: destinationChainId,
                exclusiveRelayer: exclusiveRelayer,
                quoteTimestamp: quoteTimestamp,
                fillDeadline: fillDeadline,
                exclusivityDeadline: exclusivityDeadline,
                message: message,
                value: msg.value
            });
        }
    }

    contract MockTargetForAccount {
        uint256 public callCount;
        uint256 public lastValue;
        bytes public lastData;

        function ping(uint256 value) external payable {
            callCount += 1;
            lastValue = value;
            lastData = msg.data;
        }

        function noop() external {}

        receive() external payable {}
    }

    contract UnifiedTokenAccountTest is Test {
        bytes32 private constant EXECUTE_TYPEHASH =
            keccak256("Execute(address target,uint256 value,bytes32 dataHash,uint256 nonce,uint256 deadline)");
        bytes32 private constant EXECUTE_BATCH_TYPEHASH =
            keccak256("ExecuteBatch(bytes32 callsHash,uint256 nonce,uint256 deadline)");
        bytes32 private constant SUPER_INTENT_EXEC_TYPEHASH =
            keccak256("SuperIntentExecution(bytes32 superIntentHash,uint32 fillDeadline)");
        bytes32 private constant CHAIN_CALLS_TYPEHASH = keccak256("ChainCalls(uint256 chainId,bytes calls)");
        bytes32 private constant SUPER_INTENT_TYPEHASH = keccak256(
            "SuperIntentData(uint256 destChainId,bytes32 salt,uint256 finalMinOutput,"
            "bytes32[] packedMinOutputs,bytes32[] packedInputAmounts,bytes32[] packedInputTokens,"
            "address outputToken,address finalOutputToken,address recipient,"
            "ChainCalls[] chainCalls)ChainCalls(uint256 chainId,bytes calls)"
        );

        uint256 private accountPk;
        UnifiedTokenAccount account;
        AccumulatorFactory factory;
        MockWethForAccount weth;
        MockSpokePoolForAccount spokePool;
        MockERC20ForAccount token;
        MockTargetForAccount target;

        bytes32 signerQx;
        bytes32 signerQy;

        function setUp() public {
            accountPk = 0xA11CE;

            (uint256 qxRaw, uint256 qyRaw) = vm.publicKeyP256(11);
            signerQx = bytes32(qxRaw);
            signerQy = bytes32(qyRaw);

            factory = new AccumulatorFactory();
            weth = new MockWethForAccount();
            spokePool = new MockSpokePoolForAccount();
            token = new MockERC20ForAccount();
            target = new MockTargetForAccount();

            account = _deployAccountAtSignerAddress(accountPk, signerQx, signerQy);
            _initializeAccount(account, signerQx, signerQy, accountPk);

            vm.deal(address(account), 20 ether);
            token.mint(address(account), 1_000 ether);
        }

        function test_initialize_setsConfigAndDeploysAccumulator() public view {
            assertEq(address(account.SPOKE_POOL()), address(spokePool));
            assertEq(address(account.WRAPPED_NATIVE_TOKEN()), address(weth));
            assertEq(account.ACCUMULATOR(), factory.computeAddress(address(account)));

            (bytes32 qx, bytes32 qy) = account.signer();
            assertEq(qx, signerQx);
            assertEq(qy, signerQy);
        }

        function test_initialize_revertsWithInvalidSignature() public {
            UnifiedTokenAccount fresh = _deployAccountAtSignerAddress(0xB0B, signerQx, signerQy);
            bytes memory badSig = _signInitDigest(fresh, signerQx, signerQy, 0xDEADBEEF);

            vm.expectRevert(UnifiedTokenAccount.InvalidInitializeSignature.selector);
            fresh.initialize(signerQx, signerQy, factory, weth, ISpokePool(address(spokePool)), badSig);
        }

        function test_initialize_cannotBeCalledTwice() public {
            bytes memory sig = _signInitDigest(account, signerQx, signerQy, accountPk);
            vm.expectRevert();
            account.initialize(signerQx, signerQy, factory, weth, ISpokePool(address(spokePool)), sig);
        }

        function test_execute_defaultRoute_revertsForUnauthorizedCaller() public {
            vm.expectRevert();
            account.execute(address(target), 0, abi.encodeCall(MockTargetForAccount.ping, (7)));
        }

        function test_execute_defaultRoute_allowsSelfCaller() public {
            vm.prank(address(account));
            account.execute(address(target), 0, abi.encodeCall(MockTargetForAccount.ping, (111)));

            assertEq(target.callCount(), 1);
            assertEq(target.lastValue(), 111);
        }

        function test_execute_defaultRoute_sendsValue() public {
            uint256 beforeBal = address(target).balance;

            vm.prank(address(account));
            account.execute(address(target), 1 ether, abi.encodeCall(MockTargetForAccount.ping, (1)));

            assertEq(address(target).balance, beforeBal + 1 ether);
        }

        function test_execute_withSignature_consumesNonceAndCallsTarget() public {
            Call memory call =
                Call({target: address(target), value: 0, data: abi.encodeCall(MockTargetForAccount.ping, (42))});
            uint256 nonce = 9;
            uint256 deadline = block.timestamp + 1 hours;

            bytes32 digest = _hashExecute(call, nonce, deadline);
            bytes memory sig = _signDigest(accountPk, digest);

            account.execute(call, nonce, deadline, sig);

            assertEq(target.callCount(), 1);
            assertEq(target.lastValue(), 42);
            assertTrue(account.usedExecutionNonces(nonce));
            assertEq(account.lastUsedExecutionNonce(), nonce);
        }

        function test_execute_withSignature_rejectsReplayNonce() public {
            Call memory call =
                Call({target: address(target), value: 0, data: abi.encodeCall(MockTargetForAccount.ping, (1))});
            uint256 nonce = 3;
            uint256 deadline = block.timestamp + 1 hours;
            bytes memory sig = _signDigest(accountPk, _hashExecute(call, nonce, deadline));

            account.execute(call, nonce, deadline, sig);

            vm.expectRevert(abi.encodeWithSelector(UnifiedTokenAccount.ExecutionNonceAlreadyUsed.selector, nonce));
            account.execute(call, nonce, deadline, sig);
        }

        function test_execute_withSignature_rejectsExpiredDeadline() public {
            Call memory call =
                Call({target: address(target), value: 0, data: abi.encodeCall(MockTargetForAccount.ping, (1))});
            uint256 nonce = 7;
            uint256 deadline = block.timestamp - 1;
            bytes memory sig = _signDigest(accountPk, _hashExecute(call, nonce, deadline));

            vm.expectRevert(abi.encodeWithSelector(UnifiedTokenAccount.SignatureExpired.selector, deadline));
            account.execute(call, nonce, deadline, sig);
        }

        function test_executeBatch_withSignature_callsAllTargets() public {
            Call[] memory calls = new Call[](2);
            calls[0] = Call({target: address(target), value: 0, data: abi.encodeCall(MockTargetForAccount.ping, (10))});
            calls[1] = Call({target: address(target), value: 0, data: abi.encodeCall(MockTargetForAccount.ping, (20))});

            uint256 nonce = 22;
            uint256 deadline = block.timestamp + 1 hours;
            bytes memory sig = _signDigest(accountPk, _hashExecuteBatch(calls, nonce, deadline));

            account.executeBatch(calls, nonce, deadline, sig);

            assertEq(target.callCount(), 2);
            assertEq(target.lastValue(), 20);
            assertTrue(account.usedExecutionNonces(nonce));
        }

        function test_executeBatch_defaultRoute_allowsSelfCaller() public {
            Call[] memory calls = new Call[](2);
            calls[0] = Call({target: address(target), value: 0, data: abi.encodeCall(MockTargetForAccount.ping, (1))});
            calls[1] = Call({target: address(target), value: 0, data: abi.encodeCall(MockTargetForAccount.ping, (2))});

            vm.prank(address(account));
            account.executeBatch(calls);

            assertEq(target.callCount(), 2);
            assertEq(target.lastValue(), 2);
        }

        function test_executeCrossChainOrder_revertsForInvalidOrderType() public {
            SuperIntentData memory intent = _buildIntent(address(token), 50, 60, 120, true);
            OnchainCrossChainOrder memory order = OnchainCrossChainOrder({
                orderDataType: bytes32(uint256(0x1234)),
                fillDeadline: uint32(block.timestamp + 10 minutes),
                orderData: abi.encode(intent)
            });

            vm.expectRevert(UnifiedTokenAccount.InvalidOrderDataType.selector);
            account.executeCrossChainOrder(order, "");
        }

        function test_executeCrossChainOrder_revertsWhenFillDeadlineTooSoon() public {
            SuperIntentData memory intent = _buildIntent(address(token), 10, 10, 20, false);
            uint32 fillDeadline = uint32(block.timestamp + 60);
            OnchainCrossChainOrder memory order = OnchainCrossChainOrder({
                orderDataType: SUPER_INTENT_TYPEHASH, fillDeadline: fillDeadline, orderData: abi.encode(intent)
            });

            vm.expectRevert();
            account.executeCrossChainOrder(order, "");
        }

        function test_executeCrossChainOrder_revertsWhenTooManyChainCalls() public {
            SuperIntentData memory intent = _buildIntent(address(token), 10, 10, 20, false);
            intent.chainCalls = new ChainCalls[](12);
            for (uint256 i; i < intent.chainCalls.length; i++) {
                intent.chainCalls[i] = ChainCalls({chainId: i + 1, calls: bytes("")});
            }

            uint32 fillDeadline = uint32(block.timestamp + 10 minutes);
            OnchainCrossChainOrder memory order = OnchainCrossChainOrder({
                orderDataType: SUPER_INTENT_TYPEHASH, fillDeadline: fillDeadline, orderData: abi.encode(intent)
            });
            bytes memory sig = _signDigest(accountPk, _hashSuperIntentExecution(intent, fillDeadline));

            vm.expectRevert();
            account.executeCrossChainOrder(order, sig);
        }

        function test_executeCrossChainOrder_dispatchesAndMarksReplay() public {
            SuperIntentData memory intent = _buildIntent(address(token), 100, 110, 100, true);
            uint32 fillDeadline = uint32(block.timestamp + 10 minutes);

            OnchainCrossChainOrder memory order = OnchainCrossChainOrder({
                orderDataType: SUPER_INTENT_TYPEHASH, fillDeadline: fillDeadline, orderData: abi.encode(intent)
            });

            bytes memory sig = _signDigest(accountPk, _hashSuperIntentExecution(intent, fillDeadline));
            account.executeCrossChainOrder(order, sig);

            assertEq(spokePool.depositCallCount(), 1);
            assertEq(target.callCount(), 1); // source-chain call executed before deposit

            (
                bytes32 depositor,
                bytes32 recipientB32,
                bytes32 inputTokenB32,
                bytes32 outputTokenB32,
                uint256 inputAmount,
                uint256 outputAmount,
                uint256 destinationChainId,
                bytes32 exclusiveRelayerB32,
                uint32 quoteTimestamp,
                uint32 recordedFillDeadline,
                uint32 exclusivityDeadline,
                bytes memory message,
                uint256 depositValue
            ) = spokePool.lastDeposit();
            assertEq(depositor, bytes32(uint256(uint160(address(account)))));
            assertEq(destinationChainId, intent.destChainId);
            assertEq(inputAmount, 110);
            assertEq(outputAmount, 100);
            assertEq(recordedFillDeadline, fillDeadline);
            assertEq(depositValue, 0);
            assertEq(token.allowance(address(account), address(spokePool)), 110);
            // silence warnings for getter tuple fields we don't assert in this test
            recipientB32;
            inputTokenB32;
            outputTokenB32;
            exclusiveRelayerB32;
            quoteTimestamp;
            exclusivityDeadline;
            message;

            vm.expectRevert();
            account.executeCrossChainOrder(order, sig);
        }

        function test_executeCrossChainOrder_nativeInput_usesMsgValueAndWrappedToken() public {
            address NATIVE = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
            SuperIntentData memory intent = _buildIntent(NATIVE, 3 ether, 3 ether, 6 ether, false);
            uint32 fillDeadline = uint32(block.timestamp + 10 minutes);

            OnchainCrossChainOrder memory order = OnchainCrossChainOrder({
                orderDataType: SUPER_INTENT_TYPEHASH, fillDeadline: fillDeadline, orderData: abi.encode(intent)
            });

            bytes memory sig = _signDigest(accountPk, _hashSuperIntentExecution(intent, fillDeadline));
            account.executeCrossChainOrder(order, sig);

            (,, bytes32 inputToken,,,,,,,,,, uint256 callValue) = spokePool.lastDeposit();
            assertEq(callValue, 3 ether);
            assertEq(inputToken, bytes32(uint256(uint160(address(weth)))));
        }

        // ───────────────────────── helpers ─────────────────────────

        function _deployAccountAtSignerAddress(uint256 signerPk, bytes32 ctorQx, bytes32 ctorQy)
            internal
            returns (UnifiedTokenAccount deployed)
        {
            UnifiedTokenAccount impl = new UnifiedTokenAccount(ctorQx, ctorQy);
            address signerAddress = vm.addr(signerPk);
            vm.etch(signerAddress, address(impl).code);
            deployed = UnifiedTokenAccount(payable(signerAddress));
        }

        function _initializeAccount(UnifiedTokenAccount a, bytes32 qx, bytes32 qy, uint256 signerPk) internal {
            bytes memory sig = _signInitDigest(a, qx, qy, signerPk);
            a.initialize(qx, qy, factory, weth, ISpokePool(address(spokePool)), sig);
        }

        function _signInitDigest(UnifiedTokenAccount a, bytes32 qx, bytes32 qy, uint256 signerPk)
            internal
            view
            returns (bytes memory)
        {
            bytes32 digest = keccak256(
                abi.encode(block.chainid, address(a), qx, qy, address(factory), address(weth), address(spokePool))
            );
            return _signDigest(signerPk, _toEthSignedMessageHash(digest));
        }

        function _signDigest(uint256 signerPk, bytes32 digest) internal view returns (bytes memory) {
            (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPk, digest);
            return abi.encodePacked(r, s, v);
        }

        function _toEthSignedMessageHash(bytes32 digest) internal pure returns (bytes32) {
            return keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", digest));
        }

        function _domainSeparator() internal view returns (bytes32) {
            return keccak256(
                abi.encode(
                    keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                    keccak256(bytes("UnifiedTokenAccount")),
                    keccak256(bytes("1")),
                    block.chainid,
                    address(account)
                )
            );
        }

        function _hashExecute(Call memory call, uint256 nonce, uint256 deadline) internal view returns (bytes32) {
            bytes32 structHash =
                keccak256(abi.encode(EXECUTE_TYPEHASH, call.target, call.value, keccak256(call.data), nonce, deadline));
            return keccak256(abi.encodePacked("\x19\x01", _domainSeparator(), structHash));
        }

        function _hashExecuteBatch(Call[] memory calls, uint256 nonce, uint256 deadline)
            internal
            view
            returns (bytes32)
        {
            bytes32 structHash = keccak256(
                abi.encode(EXECUTE_BATCH_TYPEHASH, keccak256(abi.encode(calls)), nonce, deadline)
            );
            return keccak256(abi.encodePacked("\x19\x01", _domainSeparator(), structHash));
        }

        function _hashChainCalls(ChainCalls[] memory chainCalls) internal pure returns (bytes32) {
            bytes32[] memory hashes = new bytes32[](chainCalls.length);
            for (uint256 i; i < chainCalls.length; i++) {
                hashes[i] =
                    keccak256(abi.encode(CHAIN_CALLS_TYPEHASH, chainCalls[i].chainId, keccak256(chainCalls[i].calls)));
            }
            return keccak256(abi.encodePacked(hashes));
        }

        function _hashSuperIntentData(SuperIntentData memory data) internal pure returns (bytes32) {
            return keccak256(
                abi.encode(
                    SUPER_INTENT_TYPEHASH,
                    data.destChainId,
                    data.salt,
                    data.finalMinOutput,
                    keccak256(abi.encodePacked(data.packedMinOutputs)),
                    keccak256(abi.encodePacked(data.packedInputAmounts)),
                    keccak256(abi.encodePacked(data.packedInputTokens)),
                    data.outputToken,
                    data.finalOutputToken,
                    data.recipient,
                    _hashChainCalls(data.chainCalls)
                )
            );
        }

        function _hashSuperIntentExecution(SuperIntentData memory data, uint32 fillDeadline)
            internal
            view
            returns (bytes32)
        {
            bytes32 structHash =
                keccak256(abi.encode(SUPER_INTENT_EXEC_TYPEHASH, _hashSuperIntentData(data), fillDeadline));
            return keccak256(abi.encodePacked("\x19\x01", _domainSeparator(), structHash));
        }

        function _packMinOutput(uint64 chainId, uint192 minOutput) internal pure returns (bytes32) {
            return bytes32((uint256(chainId) << 192) | uint256(minOutput));
        }

        function _packInputAmount(uint64 chainId, uint192 amount) internal pure returns (bytes32) {
            return bytes32((uint256(chainId) << 192) | uint256(amount));
        }

        function _packInputToken(uint96 chainId, address tokenAddr) internal pure returns (bytes32) {
            return bytes32((uint256(uint160(tokenAddr)) << 96) | chainId);
        }

        function _buildIntent(
            address inputToken,
            uint192 minOutput,
            uint192 amount,
            uint192 totalMinOutput,
            bool withSourceCall
        ) internal view returns (SuperIntentData memory intent) {
            bytes32[] memory packedMinOutputs = new bytes32[](1);
            bytes32[] memory packedInputAmounts = new bytes32[](1);
            bytes32[] memory packedInputTokens = new bytes32[](1);

            packedMinOutputs[0] = _packMinOutput(uint64(block.chainid), totalMinOutput);
            packedInputAmounts[0] = _packInputAmount(uint64(block.chainid), amount);
            packedInputTokens[0] = _packInputToken(uint96(block.chainid), inputToken);

            ChainCalls[] memory chainCalls = new ChainCalls[](withSourceCall ? 2 : 1);
            if (withSourceCall) {
                Call[] memory sourceCalls = new Call[](1);
                sourceCalls[0] =
                    Call({target: address(target), value: 0, data: abi.encodeCall(MockTargetForAccount.ping, (777))});
                chainCalls[0] = ChainCalls({chainId: block.chainid, calls: abi.encode(sourceCalls)});
                chainCalls[1] = ChainCalls({chainId: 42161, calls: bytes("")});
            } else {
                chainCalls[0] = ChainCalls({chainId: 42161, calls: bytes("")});
            }

            intent = SuperIntentData({
                destChainId: 42161,
                salt: keccak256("salt"),
                finalMinOutput: minOutput,
                packedMinOutputs: packedMinOutputs,
                packedInputAmounts: packedInputAmounts,
                packedInputTokens: packedInputTokens,
                outputToken: address(token),
                finalOutputToken: address(token),
                recipient: address(0xCAFE),
                chainCalls: chainCalls
            });
        }
    }
