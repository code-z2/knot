// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {UnifiedAccount} from "../src/UnifiedAccount.sol";
import {AccumulatorFactory} from "../src/AccumulatorFactory.sol";
import {IMerkleVerifier} from "../src/interfaces/IMerkleVerifier.sol";
import {ISpokePool} from "../src/interfaces/ISpokePool.sol";
import {Call, OnchainCrossChainOrder, DispatchOrder} from "../src/types/Structs.sol";
import {MessageHashUtils} from "openzeppelin-contracts/utils/cryptography/MessageHashUtils.sol";
import {Hashes} from "openzeppelin-contracts/utils/cryptography/Hashes.sol";

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

contract UnifiedAccountTest is Test {
    bytes32 private constant EXECUTEX_TYPEHASH = keccak256("ExecuteX(bytes32 callsHash,bytes32 salt)");

    uint256 private accountPk;
    UnifiedAccount account;
    AccumulatorFactory factory;
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
        spokePool = new MockSpokePoolForAccount();
        token = new MockERC20ForAccount();
        target = new MockTargetForAccount();

        account = _deployAccountAtSignerAddress(accountPk, signerQx, signerQy);
        _initializeAccount(account, signerQx, signerQy);

        vm.deal(address(account), 20 ether);
        token.mint(address(account), 1_000 ether);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    //  Initialize tests
    // ═══════════════════════════════════════════════════════════════════════════

    function test_initialize_setsConfigAndDeploysAccumulator() public view {
        assertEq(address(account.spokePool()), address(spokePool));
        assertEq(account.accumulator(), factory.computeAddress(address(account)));

        (bytes32 qx, bytes32 qy) = account.signer();
        assertEq(qx, signerQx);
        assertEq(qy, signerQy);
    }

    function test_initialize_cannotBeCalledTwice() public {
        vm.prank(address(account));
        vm.expectRevert();
        account.initialize(signerQx, signerQy, factory, ISpokePool(address(spokePool)));
    }

    function test_initialize_revertsForNonOwner() public {
        UnifiedAccount fresh = _deployAccountAtSignerAddress(0xB0B, signerQx, signerQy);
        vm.expectRevert();
        fresh.initialize(signerQx, signerQy, factory, ISpokePool(address(spokePool)));
    }

    // ═══════════════════════════════════════════════════════════════════════════
    //  Execute (default route) tests
    // ═══════════════════════════════════════════════════════════════════════════

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

    function test_executeBatch_defaultRoute_allowsSelfCaller() public {
        Call[] memory calls = new Call[](2);
        calls[0] = Call({target: address(target), value: 0, data: abi.encodeCall(MockTargetForAccount.ping, (1))});
        calls[1] = Call({target: address(target), value: 0, data: abi.encodeCall(MockTargetForAccount.ping, (2))});

        vm.prank(address(account));
        account.executeBatch(calls);

        assertEq(target.callCount(), 2);
        assertEq(target.lastValue(), 2);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    //  executeX tests (Merkle-verified execution)
    // ═══════════════════════════════════════════════════════════════════════════

    function test_executeX_singleLeaf_executesCall() public {
        Call[] memory calls = new Call[](1);
        calls[0] = Call({target: address(target), value: 0, data: abi.encodeCall(MockTargetForAccount.ping, (42))});
        bytes32 salt = keccak256("salt1");

        // Single leaf = root is the leaf itself, no proof needed
        bytes32 leafHash = _computeLeafHash(calls, salt);
        bytes32 root = leafHash; // single leaf tree
        bytes memory sig = _signDigest(accountPk, MessageHashUtils.toEthSignedMessageHash(root));

        account.executeX(calls, salt, new bytes32[](0), sig);

        assertEq(target.callCount(), 1);
        assertEq(target.lastValue(), 42);
        assertTrue(account.usedSalts(salt));
    }

    function test_executeX_twoLeafTree_executesCorrectLeaf() public {
        // Leaf A: target call on this chain
        Call[] memory callsA = new Call[](1);
        callsA[0] = Call({target: address(target), value: 0, data: abi.encodeCall(MockTargetForAccount.ping, (99))});
        bytes32 saltA = keccak256("leafA");
        bytes32 leafA = _computeLeafHash(callsA, saltA);

        // Leaf B: some other chain's leaf (simulated as different calls)
        Call[] memory callsB = new Call[](1);
        callsB[0] = Call({target: address(target), value: 0, data: abi.encodeCall(MockTargetForAccount.ping, (77))});
        bytes32 saltB = keccak256("leafB");
        bytes32 leafB = _computeLeafHash(callsB, saltB);

        // Build merkle root (OZ uses commutative keccak256 — sorted pair)
        bytes32 root = Hashes.commutativeKeccak256(leafA, leafB);
        bytes memory sig = _signDigest(accountPk, MessageHashUtils.toEthSignedMessageHash(root));

        // Execute leaf A with leafB as proof
        bytes32[] memory proof = new bytes32[](1);
        proof[0] = leafB;

        account.executeX(callsA, saltA, proof, sig);

        assertEq(target.callCount(), 1);
        assertEq(target.lastValue(), 99);
        assertTrue(account.usedSalts(saltA));
    }

    function test_executeX_rejectsSaltReplay() public {
        Call[] memory calls = new Call[](1);
        calls[0] = Call({target: address(target), value: 0, data: abi.encodeCall(MockTargetForAccount.noop, ())});
        bytes32 salt = keccak256("replay");

        bytes32 leafHash = _computeLeafHash(calls, salt);
        bytes memory sig = _signDigest(accountPk, MessageHashUtils.toEthSignedMessageHash(leafHash));

        account.executeX(calls, salt, new bytes32[](0), sig);

        vm.expectRevert(abi.encodeWithSelector(UnifiedAccount.SaltAlreadyUsed.selector, salt));
        account.executeX(calls, salt, new bytes32[](0), sig);
    }

    function test_executeX_rejectsInvalidSignature() public {
        Call[] memory calls = new Call[](1);
        calls[0] = Call({target: address(target), value: 0, data: abi.encodeCall(MockTargetForAccount.noop, ())});
        bytes32 salt = keccak256("badSig");

        // Sign with wrong key
        bytes32 leafHash = _computeLeafHash(calls, salt);
        bytes memory badSig = _signDigest(0xDEADBEEF, MessageHashUtils.toEthSignedMessageHash(leafHash));

        vm.expectRevert(UnifiedAccount.InvalidSignature.selector);
        account.executeX(calls, salt, new bytes32[](0), badSig);
    }

    function test_executeX_rejectsInvalidProof() public {
        Call[] memory calls = new Call[](1);
        calls[0] = Call({target: address(target), value: 0, data: abi.encodeCall(MockTargetForAccount.noop, ())});
        bytes32 salt = keccak256("badProof");

        // Compute leaf but provide wrong proof — root won't match signature
        bytes32 leafHash = _computeLeafHash(calls, salt);
        bytes memory sig = _signDigest(accountPk, MessageHashUtils.toEthSignedMessageHash(leafHash));

        // Add a bogus proof element — changes the computed root
        bytes32[] memory badProof = new bytes32[](1);
        badProof[0] = keccak256("bogus");

        vm.expectRevert(UnifiedAccount.InvalidSignature.selector);
        account.executeX(calls, salt, badProof, sig);
    }

    function test_executeX_executesMultipleCalls() public {
        Call[] memory calls = new Call[](2);
        calls[0] = Call({target: address(target), value: 0, data: abi.encodeCall(MockTargetForAccount.ping, (10))});
        calls[1] = Call({target: address(target), value: 0, data: abi.encodeCall(MockTargetForAccount.ping, (20))});
        bytes32 salt = keccak256("batch");

        bytes32 leafHash = _computeLeafHash(calls, salt);
        bytes memory sig = _signDigest(accountPk, MessageHashUtils.toEthSignedMessageHash(leafHash));

        account.executeX(calls, salt, new bytes32[](0), sig);

        assertEq(target.callCount(), 2);
        assertEq(target.lastValue(), 20);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    //  dispatch tests (via executeX)
    // ═══════════════════════════════════════════════════════════════════════════

    function test_dispatch_viaExecuteX_depositsToSpokePool() public {
        uint32 fillDeadline = uint32(block.timestamp + 10 minutes);
        OnchainCrossChainOrder memory order = _buildCrossChainOrder(
            fillDeadline,
            DispatchOrder({
                salt: keccak256("dispatch-salt"),
                destChainId: 42161,
                outputToken: address(token),
                sumOutput: 100,
                inputAmount: 110,
                inputToken: address(token),
                minOutput: 100
            })
        );

        // Build Call[] that dispatches via self-call
        Call[] memory calls = new Call[](1);
        calls[0] = Call({target: address(account), value: 0, data: abi.encodeCall(UnifiedAccount.dispatch, (order))});
        bytes32 salt = keccak256("executeX-dispatch");

        bytes32 leafHash = _computeLeafHash(calls, salt);
        bytes memory sig = _signDigest(accountPk, MessageHashUtils.toEthSignedMessageHash(leafHash));

        account.executeX(calls, salt, new bytes32[](0), sig);

        assertEq(spokePool.depositCallCount(), 1);

        (
            bytes32 depositor,,,,
            uint256 inputAmount,
            uint256 outputAmount,
            uint256 destinationChainId,,,
            uint32 recordedFillDeadline,,,
            uint256 depositValue
        ) = spokePool.lastDeposit();
        assertEq(depositor, bytes32(uint256(uint160(address(account)))));
        assertEq(destinationChainId, 42161);
        assertEq(inputAmount, 110);
        assertEq(outputAmount, 100);
        assertEq(recordedFillDeadline, fillDeadline);
        assertEq(depositValue, 0);
        assertEq(token.allowance(address(account), address(spokePool)), 110);
    }

    function test_dispatch_directCall_revertsForNonSelf() public {
        uint32 fillDeadline = uint32(block.timestamp + 10 minutes);
        OnchainCrossChainOrder memory order = _buildCrossChainOrder(
            fillDeadline,
            DispatchOrder({
                salt: keccak256("direct"),
                destChainId: 42161,
                outputToken: address(token),
                sumOutput: 100,
                inputAmount: 110,
                inputToken: address(token),
                minOutput: 100
            })
        );

        vm.expectRevert();
        account.dispatch(order);
    }

    function test_dispatch_revertsWhenFillDeadlineTooSoon() public {
        uint32 fillDeadline = uint32(block.timestamp + 60); // only 60s, needs 5 min
        OnchainCrossChainOrder memory order = _buildCrossChainOrder(
            fillDeadline,
            DispatchOrder({
                salt: keccak256("too-soon"),
                destChainId: 42161,
                outputToken: address(token),
                sumOutput: 100,
                inputAmount: 110,
                inputToken: address(token),
                minOutput: 100
            })
        );

        Call[] memory calls = new Call[](1);
        calls[0] = Call({target: address(account), value: 0, data: abi.encodeCall(UnifiedAccount.dispatch, (order))});
        bytes32 salt = keccak256("too-soon-salt");

        bytes32 leafHash = _computeLeafHash(calls, salt);
        bytes memory sig = _signDigest(accountPk, MessageHashUtils.toEthSignedMessageHash(leafHash));

        vm.expectRevert();
        account.executeX(calls, salt, new bytes32[](0), sig);
    }

    function test_dispatch_withSourceCalls_executesBeforeDeposit() public {
        uint32 fillDeadline = uint32(block.timestamp + 10 minutes);
        OnchainCrossChainOrder memory order = _buildCrossChainOrder(
            fillDeadline,
            DispatchOrder({
                salt: keccak256("with-source"),
                destChainId: 42161,
                outputToken: address(token),
                sumOutput: 100,
                inputAmount: 110,
                inputToken: address(token),
                minOutput: 100
            })
        );

        // Build Call[] with source call before dispatch
        Call[] memory calls = new Call[](2);
        calls[0] = Call({target: address(target), value: 0, data: abi.encodeCall(MockTargetForAccount.ping, (777))});
        calls[1] = Call({target: address(account), value: 0, data: abi.encodeCall(UnifiedAccount.dispatch, (order))});
        bytes32 salt = keccak256("source-dispatch");

        bytes32 leafHash = _computeLeafHash(calls, salt);
        bytes memory sig = _signDigest(accountPk, MessageHashUtils.toEthSignedMessageHash(leafHash));

        account.executeX(calls, salt, new bytes32[](0), sig);

        assertEq(target.callCount(), 1);
        assertEq(target.lastValue(), 777);
        assertEq(spokePool.depositCallCount(), 1);
    }

    function test_dispatch_revertsOnInvalidOrderDataType() public {
        uint32 fillDeadline = uint32(block.timestamp + 10 minutes);
        OnchainCrossChainOrder memory order = OnchainCrossChainOrder({
            fillDeadline: fillDeadline,
            orderDataType: keccak256("WrongType()"), // wrong typehash
            orderData: abi.encode(
                DispatchOrder({
                    salt: keccak256("bad-type"),
                    destChainId: 42161,
                    outputToken: address(token),
                    sumOutput: 100,
                    inputAmount: 110,
                    inputToken: address(token),
                    minOutput: 100
                })
            )
        });

        Call[] memory calls = new Call[](1);
        calls[0] = Call({target: address(account), value: 0, data: abi.encodeCall(UnifiedAccount.dispatch, (order))});
        bytes32 salt = keccak256("bad-type-salt");

        bytes32 leafHash = _computeLeafHash(calls, salt);
        bytes memory sig = _signDigest(accountPk, MessageHashUtils.toEthSignedMessageHash(leafHash));

        vm.expectRevert();
        account.executeX(calls, salt, new bytes32[](0), sig);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    //  verifyMerkleRoot tests (callback from Accumulator)
    // ═══════════════════════════════════════════════════════════════════════════

    function test_verifyMerkleRoot_singleLeaf_validSignature() public view {
        // verifyMerkleRoot receives a struct hash (pre-domain) and wraps with _hashTypedDataV4
        bytes32 structHash = keccak256("some-struct-hash");
        bytes32 leafHash = _wrapWithDomain(structHash); // what the account computes internally
        bytes32 root = leafHash; // single leaf tree
        bytes memory sig = _signDigest(accountPk, MessageHashUtils.toEthSignedMessageHash(root));

        bytes4 result = account.verifyMerkleRoot(structHash, new bytes32[](0), sig);
        assertEq(result, IMerkleVerifier.verifyMerkleRoot.selector);
    }

    function test_verifyMerkleRoot_twoLeafTree_validProof() public view {
        bytes32 structHashA = keccak256("struct-A");
        bytes32 structHashB = keccak256("struct-B");
        bytes32 leafA = _wrapWithDomain(structHashA);
        bytes32 leafB = _wrapWithDomain(structHashB);
        bytes32 root = Hashes.commutativeKeccak256(leafA, leafB);

        bytes memory sig = _signDigest(accountPk, MessageHashUtils.toEthSignedMessageHash(root));

        bytes32[] memory proof = new bytes32[](1);
        proof[0] = leafB;

        bytes4 result = account.verifyMerkleRoot(structHashA, proof, sig);
        assertEq(result, IMerkleVerifier.verifyMerkleRoot.selector);
    }

    function test_verifyMerkleRoot_invalidSignature() public view {
        bytes32 structHash = keccak256("some-struct");
        bytes32 leafHash = _wrapWithDomain(structHash);
        bytes memory badSig = _signDigest(0xDEADBEEF, MessageHashUtils.toEthSignedMessageHash(leafHash));

        bytes4 result = account.verifyMerkleRoot(structHash, new bytes32[](0), badSig);
        assertEq(result, bytes4(0xffffffff));
    }

    function test_verifyMerkleRoot_invalidProof() public view {
        bytes32 structHash = keccak256("some-struct");
        bytes32 leafHash = _wrapWithDomain(structHash);
        bytes memory sig = _signDigest(accountPk, MessageHashUtils.toEthSignedMessageHash(leafHash));

        // Wrong proof element changes the root
        bytes32[] memory badProof = new bytes32[](1);
        badProof[0] = keccak256("wrong");

        bytes4 result = account.verifyMerkleRoot(structHash, badProof, sig);
        assertEq(result, bytes4(0xffffffff));
    }

    // ═══════════════════════════════════════════════════════════════════════════
    //  ERC-1271 tests
    // ═══════════════════════════════════════════════════════════════════════════

    function test_isValidSignature_validEOASignature() public view {
        bytes32 hash = keccak256("message");
        bytes memory sig = _signDigest(accountPk, hash);
        assertEq(account.isValidSignature(hash, sig), bytes4(0x1626ba7e));
    }

    function test_isValidSignature_invalidSignature() public view {
        bytes32 hash = keccak256("message");
        bytes memory badSig = _signDigest(0xDEADBEEF, hash);
        assertEq(account.isValidSignature(hash, badSig), bytes4(0xffffffff));
    }

    // ═══════════════════════════════════════════════════════════════════════════
    //  Helpers
    // ═══════════════════════════════════════════════════════════════════════════

    function _deployAccountAtSignerAddress(uint256 signerPk, bytes32 ctorQx, bytes32 ctorQy)
        internal
        returns (UnifiedAccount deployed)
    {
        UnifiedAccount impl = new UnifiedAccount(ctorQx, ctorQy);
        address signerAddress = vm.addr(signerPk);
        vm.etch(signerAddress, address(impl).code);
        deployed = UnifiedAccount(payable(signerAddress));
    }

    function _initializeAccount(UnifiedAccount a, bytes32 qx, bytes32 qy) internal {
        vm.prank(address(a));
        a.initialize(qx, qy, factory, ISpokePool(address(spokePool)));
    }

    function _signDigest(uint256 signerPk, bytes32 digest) internal pure returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPk, digest);
        return abi.encodePacked(r, s, v);
    }

    function _domainSeparator() internal view returns (bytes32) {
        return keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256(bytes("UnifiedAccount")),
                keccak256(bytes("1")),
                block.chainid,
                address(account)
            )
        );
    }

    /// @dev Computes the EIP-712 leaf hash for executeX, matching the contract's logic.
    function _computeLeafHash(Call[] memory calls, bytes32 salt) internal view returns (bytes32) {
        bytes32 structHash = keccak256(abi.encode(EXECUTEX_TYPEHASH, keccak256(abi.encode(calls)), salt));
        return _wrapWithDomain(structHash);
    }

    /// @dev Wraps a struct hash with the account's EIP-712 domain separator.
    ///      Mirrors `_hashTypedDataV4(structHash)` in the account contract.
    function _wrapWithDomain(bytes32 structHash) internal view returns (bytes32) {
        return keccak256(abi.encodePacked("\x19\x01", _domainSeparator(), structHash));
    }

    /// @dev Builds an ERC-7683 OnchainCrossChainOrder envelope from a DispatchOrder.
    function _buildCrossChainOrder(uint32 fillDeadline, DispatchOrder memory dispatchOrder)
        internal
        view
        returns (OnchainCrossChainOrder memory)
    {
        return OnchainCrossChainOrder({
            fillDeadline: fillDeadline,
            orderDataType: account.DISPATCH_ORDER_TYPEHASH(),
            orderData: abi.encode(dispatchOrder)
        });
    }
}
