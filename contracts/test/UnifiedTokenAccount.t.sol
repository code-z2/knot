// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {UnifiedTokenAccount} from "../src/UnifiedTokenAccount.sol";
import {Call, ChainCalls} from "../src/types/Structs.sol";
import {IAccumulator} from "../src/interfaces/IAccumulator.sol";
import {ERC4337Utils} from "openzeppelin-contracts/account/utils/draft-ERC4337Utils.sol";
import {IEntryPointNonces} from "openzeppelin-contracts/interfaces/draft-IERC4337.sol";

contract MockTarget {
    uint256 public last;

    function set(uint256 value) external {
        last = value;
    }

    function fail() external pure {
        revert("fail");
    }
}

contract MockAccumulator is IAccumulator {
    bytes32 public last;

    function approve(bytes32 intentHash) external {
        last = intentHash;
    }
}

contract UnifiedTokenAccountTest is Test {
    UnifiedTokenAccount account;
    MockTarget target;
    MockAccumulator accumulator;
    address entryPoint;

    function setUp() public {
        uint256 privateKey = 1;
        (uint256 qx, uint256 qy) = vm.publicKeyP256(privateKey);
        account = new UnifiedTokenAccount(bytes32(qx), bytes32(qy));
        target = new MockTarget();
        accumulator = new MockAccumulator();
        entryPoint = address(ERC4337Utils.ENTRYPOINT_V09);
    }

    function _mockNonce(uint256 nonce) internal {
        vm.mockCall(
            entryPoint,
            abi.encodeWithSelector(IEntryPointNonces.getNonce.selector, address(account), uint192(0)),
            abi.encode(nonce)
        );
    }

    function test_executeSingle() public {
        vm.prank(entryPoint);
        account.execute(address(target), 0, abi.encodeWithSignature("set(uint256)", 123));

        assertEq(target.last(), 123);
    }

    function test_executeRevertsWithTargetError() public {
        vm.prank(entryPoint);
        vm.expectRevert(bytes("fail"));
        account.execute(address(target), 0, abi.encodeWithSignature("fail()"));
    }

    function test_executeBatchRevertsWithExecuteError() public {
        Call[] memory calls = new Call[](2);
        calls[0] = Call({target: address(target), value: 0, data: abi.encodeWithSignature("set(uint256)", 1)});
        calls[1] = Call({target: address(target), value: 0, data: abi.encodeWithSignature("fail()")});

        bytes memory nestedError = abi.encodeWithSignature("Error(string)", "fail");
        bytes memory expected =
            abi.encodeWithSelector(UnifiedTokenAccount.ExecuteError.selector, uint256(1), nestedError);

        vm.prank(entryPoint);
        vm.expectRevert(expected);
        account.executeBatch(calls);
    }

    function test_executeChainCallsExecutesMatchingChain() public {
        Call[] memory calls = new Call[](1);
        calls[0] = Call({target: address(target), value: 0, data: abi.encodeWithSignature("set(uint256)", 77)});

        ChainCalls[] memory bundles = new ChainCalls[](2);
        bundles[0] = ChainCalls({chainId: block.chainid + 1, calls: calls});
        bundles[1] = ChainCalls({chainId: block.chainid, calls: calls});

        vm.prank(entryPoint);
        account.executeChainCalls(abi.encode(bundles));

        assertEq(target.last(), 77);
    }

    function test_registerJobApprovesAccumulator() public {
        bytes32 jobId = keccak256("job");
        uint256 nonce = 42;
        _mockNonce(nonce);

        uint256 salt = (nonce << 60) | block.chainid;
        bytes32 expected = keccak256(abi.encode(salt, jobId));

        vm.prank(entryPoint);
        account.registerJob(jobId, address(accumulator));

        assertEq(accumulator.last(), expected);
    }

    function test_initializeUpdatesSigner() public {
        uint256 privateKey = 2;
        (uint256 qx, uint256 qy) = vm.publicKeyP256(privateKey);

        vm.prank(entryPoint);
        account.initialize(bytes32(qx), bytes32(qy));

        (bytes32 storedX, bytes32 storedY) = account.signer();
        assertEq(storedX, bytes32(qx));
        assertEq(storedY, bytes32(qy));
    }

    function test_isValidSignatureBranches() public {
        bytes32 digest = keccak256("data");
        bytes memory emptySig = "";

        bytes4 resultExternal = account.isValidSignature(digest, emptySig);
        assertEq(resultExternal, bytes4(0xffffffff));

        vm.prank(address(account));
        bytes4 resultSelf = account.isValidSignature(digest, emptySig);
        assertEq(resultSelf, bytes4(0xffffffff));
    }
}
