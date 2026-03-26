// SPDX-License-Identifier: MIT
pragma solidity ^0.8.33;

import {Test} from "forge-std/Test.sol";
import {VmSafe} from "forge-std/Vm.sol";
import {
    MODULE_TYPE_VALIDATOR,
    MODULE_TYPE_EXECUTOR,
    MODULE_TYPE_FALLBACK
} from "openzeppelin-contracts/interfaces/draft-IERC7579.sol";
import {
    ERC7579Utils,
    CallType,
    ExecType,
    Mode,
    ModePayload,
    ModeSelector
} from "openzeppelin-contracts/account/utils/draft-ERC7579Utils.sol";

import {KnotAccount} from "../src/KnotAccount.sol";
import {MerkleValidator} from "../src/MerkleValidator.sol";
import {CrossChainExecutor} from "../src/CrossChainExecutor.sol";
import {AccumulatorModule} from "../src/AccumulatorModule.sol";
import {IAccumulatorModule} from "../src/interfaces/IAccumulatorModule.sol";
import {KnotConsumerHub} from "../src/KnotConsumerHub.sol";

contract KnotAccountTest is Test {
    KnotAccount internal account;
    MerkleValidator internal validator;
    CrossChainExecutor internal executor;
    AccumulatorModule internal accumulator;
    KnotConsumerHub internal hub;

    address internal spokePool;
    uint256 internal signerPk;
    bytes32 internal signerQx;
    bytes32 internal signerQy;

    function setUp() public {
        signerPk = 11;
        (uint256 qxRaw, uint256 qyRaw) = vm.publicKeyP256(signerPk);
        signerQx = bytes32(qxRaw);
        signerQy = bytes32(qyRaw);

        spokePool = makeAddr("spokePool");

        validator = new MerkleValidator();
        executor = new CrossChainExecutor();
        accumulator = new AccumulatorModule();
        hub = new KnotConsumerHub(address(executor), address(accumulator));

        account = new KnotAccount();
    }

    // ═══════════════════════════════════════════════════════════════════════════
    //                              HELPERS
    // ═══════════════════════════════════════════════════════════════════════════

    function _initialize() internal {
        vm.prank(address(account.entryPoint()));
        account.initialize(
            address(validator),
            abi.encode(signerQx, signerQy),
            address(executor),
            abi.encode(spokePool, address(hub)),
            address(accumulator),
            abi.encode(spokePool, address(hub))
        );
    }

    // ═══════════════════════════════════════════════════════════════════════════
    //                        INITIALIZE — MODULE INSTALL
    // ═══════════════════════════════════════════════════════════════════════════

    function test_initialize_installsValidator() public {
        _initialize();

        (bytes32 qx, bytes32 qy) = validator.publicKeyOf(address(account));
        assertEq(qx, signerQx, "validator qx mismatch");
        assertEq(qy, signerQy, "validator qy mismatch");
    }

    function test_initialize_installsExecutor() public {
        _initialize();

        address configuredSpokePool = executor.configOf(address(account));
        assertEq(configuredSpokePool, spokePool, "executor spokePool mismatch");
    }

    function test_initialize_installsAccumulator() public {
        _initialize();

        address configuredSpokePool = accumulator.spokePools(address(account));
        assertEq(configuredSpokePool, spokePool, "accumulator spokePool mismatch");
    }

    function test_initialize_installsFallbackHandlers() public {
        _initialize();

        // Verify fallback handlers are installed by checking module installation
        assertTrue(
            account.isModuleInstalled(
                MODULE_TYPE_FALLBACK,
                address(accumulator),
                abi.encodePacked(IAccumulatorModule.handleV3AcrossMessage.selector)
            ),
            "handleV3AcrossMessage fallback not installed"
        );
        assertTrue(
            account.isModuleInstalled(
                MODULE_TYPE_FALLBACK, address(accumulator), abi.encodePacked(IAccumulatorModule.executeIntent.selector)
            ),
            "executeIntent fallback not installed"
        );
        assertTrue(
            account.isModuleInstalled(
                MODULE_TYPE_FALLBACK, address(accumulator), abi.encodePacked(IAccumulatorModule.markStale.selector)
            ),
            "markStale fallback not installed"
        );
    }

    // ═══════════════════════════════════════════════════════════════════════════
    //                    INITIALIZE — REVERT CASES
    // ═══════════════════════════════════════════════════════════════════════════

    function test_initialize_revertsIfValidatorIsZero() public {
        vm.prank(address(account.entryPoint()));
        vm.expectRevert(KnotAccount.InvalidModule.selector);
        account.initialize(
            address(0),
            abi.encode(signerQx, signerQy),
            address(executor),
            abi.encode(spokePool, address(hub)),
            address(accumulator),
            abi.encode(spokePool, address(hub))
        );
    }

    function test_initialize_revertsIfExecutorIsZero() public {
        vm.prank(address(account.entryPoint()));
        vm.expectRevert(KnotAccount.InvalidModule.selector);
        account.initialize(
            address(validator),
            abi.encode(signerQx, signerQy),
            address(0),
            abi.encode(spokePool, address(hub)),
            address(accumulator),
            abi.encode(spokePool, address(hub))
        );
    }

    function test_initialize_revertsIfAccumulatorIsZero() public {
        vm.prank(address(account.entryPoint()));
        vm.expectRevert(KnotAccount.InvalidModule.selector);
        account.initialize(
            address(validator),
            abi.encode(signerQx, signerQy),
            address(executor),
            abi.encode(spokePool, address(hub)),
            address(0),
            abi.encode(spokePool, address(hub))
        );
    }

    function test_initialize_revertsOnDoubleInit() public {
        _initialize();

        vm.prank(address(account.entryPoint()));
        vm.expectRevert();
        account.initialize(
            address(validator),
            abi.encode(signerQx, signerQy),
            address(executor),
            abi.encode(spokePool, address(hub)),
            address(accumulator),
            abi.encode(spokePool, address(hub))
        );
    }

    // ═══════════════════════════════════════════════════════════════════════════
    //                    INITIALIZE — ACCESS CONTROL
    // ═══════════════════════════════════════════════════════════════════════════

    function test_initialize_revertsFromUnauthorizedCaller() public {
        address unauthorized = makeAddr("unauthorized");
        vm.prank(unauthorized);
        vm.expectRevert();
        account.initialize(
            address(validator),
            abi.encode(signerQx, signerQy),
            address(executor),
            abi.encode(spokePool, address(hub)),
            address(accumulator),
            abi.encode(spokePool, address(hub))
        );
    }

    // ═══════════════════════════════════════════════════════════════════════════
    //                              ACCOUNT ID
    // ═══════════════════════════════════════════════════════════════════════════

    function test_accountId() public view {
        assertEq(account.accountId(), "knot.KnotAccount.v2.0.0");
    }

    // ═══════════════════════════════════════════════════════════════════════════
    //                                MEMO
    // ═══════════════════════════════════════════════════════════════════════════

    function test_execute_emitsMemoWhenNonZero() public {
        _initialize();

        bytes32 memo = keccak256("test-memo");
        bytes32 mode = Mode.unwrap(
            ERC7579Utils.encodeMode(
                ERC7579Utils.CALLTYPE_SINGLE,
                ExecType.wrap(0x00),
                ModeSelector.wrap(bytes4(0)),
                ModePayload.wrap(bytes22(0))
            )
        );

        // Encode a no-op single call (call to self with no value and empty data)
        bytes memory executionCalldata = abi.encodePacked(address(account), uint256(0), bytes(""));

        vm.prank(address(account.entryPoint()));
        vm.expectEmit(true, false, false, false, address(account));
        emit KnotAccount.Memo(memo);
        account.execute(mode, executionCalldata, memo);
    }

    function test_execute_noMemoEventWhenZero() public {
        _initialize();

        bytes32 mode = Mode.unwrap(
            ERC7579Utils.encodeMode(
                ERC7579Utils.CALLTYPE_SINGLE,
                ExecType.wrap(0x00),
                ModeSelector.wrap(bytes4(0)),
                ModePayload.wrap(bytes22(0))
            )
        );

        // Encode a no-op single call
        bytes memory executionCalldata = abi.encodePacked(address(account), uint256(0), bytes(""));

        vm.prank(address(account.entryPoint()));
        vm.recordLogs();
        account.execute(mode, executionCalldata, bytes32(0));

        VmSafe.Log[] memory logs = vm.getRecordedLogs();
        bytes32 memoTopic = KnotAccount.Memo.selector;
        for (uint256 i; i < logs.length; i++) {
            if (logs[i].topics.length > 0) {
                assertTrue(logs[i].topics[0] != memoTopic, "Memo event should not be emitted for zero memo");
            }
        }
    }

    function test_execute_withMemoDelegatesToStandardExecute() public {
        _initialize();

        // Prepare a call that transfers ETH to a recipient
        address recipient = makeAddr("recipient");
        uint256 amount = 1 ether;
        vm.deal(address(account), amount);

        bytes32 mode = Mode.unwrap(
            ERC7579Utils.encodeMode(
                ERC7579Utils.CALLTYPE_SINGLE,
                ExecType.wrap(0x00),
                ModeSelector.wrap(bytes4(0)),
                ModePayload.wrap(bytes22(0))
            )
        );

        bytes memory executionCalldata = abi.encodePacked(recipient, amount, bytes(""));
        bytes32 memo = keccak256("transfer-memo");

        vm.prank(address(account.entryPoint()));
        account.execute(mode, executionCalldata, memo);

        assertEq(recipient.balance, amount, "recipient should have received ETH");
    }
}
