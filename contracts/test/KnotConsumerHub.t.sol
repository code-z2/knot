// SPDX-License-Identifier: MIT
pragma solidity ^0.8.33;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";

import {IKnotConsumerHub} from "../src/interfaces/IKnotConsumerHub.sol";
import {KnotConsumerHub} from "../src/KnotConsumerHub.sol";

contract KnotConsumerHubTest is Test {
    KnotConsumerHub hub;

    address executorModule = makeAddr("executorModule");
    address accumulatorModule = makeAddr("accumulatorModule");
    address stranger = makeAddr("stranger");
    address account = makeAddr("account");

    bytes32 constant FILL_ID = keccak256("fill-id");
    uint256 constant DESTINATION_CHAIN_ID = 42161;
    uint32 constant FILL_DEADLINE = 123456;

    function setUp() public {
        hub = new KnotConsumerHub(executorModule, accumulatorModule);
    }

    function test_constructor_revertsForZeroModule() public {
        vm.expectRevert(KnotConsumerHub.InvalidModule.selector);
        new KnotConsumerHub(address(0), accumulatorModule);
    }

    function test_registerIntent_onlyExecutorMayCall() public {
        vm.expectRevert(abi.encodeWithSelector(KnotConsumerHub.UnauthorizedExecutor.selector, stranger));
        vm.prank(stranger);
        hub.registerIntent(account, FILL_ID, DESTINATION_CHAIN_ID, FILL_DEADLINE);
    }

    function test_registerIntent_emitsOnce() public {
        vm.expectEmit(true, true, true, true, address(hub));
        emit IKnotConsumerHub.IntentRegistered(FILL_ID, account, DESTINATION_CHAIN_ID, block.chainid, FILL_DEADLINE);

        vm.prank(executorModule);
        hub.registerIntent(account, FILL_ID, DESTINATION_CHAIN_ID, FILL_DEADLINE);

        vm.recordLogs();
        vm.prank(executorModule);
        hub.registerIntent(account, FILL_ID, DESTINATION_CHAIN_ID, FILL_DEADLINE);
        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(entries.length, 0);
    }

    function test_reportFillReady_onlyAccumulatorMayCall() public {
        vm.expectRevert(abi.encodeWithSelector(KnotConsumerHub.UnauthorizedAccumulator.selector, stranger));
        vm.prank(stranger);
        hub.reportFillReady(account, FILL_ID);
    }

    function test_reportFillReady_emitsOnce() public {
        vm.expectEmit(true, true, true, true, address(hub));
        emit IKnotConsumerHub.FillReady(FILL_ID, account, block.chainid);

        vm.prank(accumulatorModule);
        hub.reportFillReady(account, FILL_ID);

        vm.recordLogs();
        vm.prank(accumulatorModule);
        hub.reportFillReady(account, FILL_ID);
        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(entries.length, 0);
    }

    function test_reportIntentExecuted_transitionsFromReady() public {
        vm.prank(accumulatorModule);
        hub.reportFillReady(account, FILL_ID);

        vm.expectEmit(true, true, true, true, address(hub));
        emit IKnotConsumerHub.IntentExecuted(FILL_ID, account, block.chainid);

        vm.prank(accumulatorModule);
        hub.reportIntentExecuted(account, FILL_ID);
    }

    function test_reportIntentDropped_ignoresConflictingTerminalUpdate() public {
        vm.prank(accumulatorModule);
        hub.reportIntentExecuted(account, FILL_ID);

        vm.recordLogs();
        vm.prank(accumulatorModule);
        hub.reportIntentDropped(account, FILL_ID);
        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(entries.length, 0);
    }

    function test_reportIntentStale_emitsFromNone() public {
        vm.expectEmit(true, true, true, true, address(hub));
        emit IKnotConsumerHub.IntentStale(FILL_ID, account, block.chainid);

        vm.prank(accumulatorModule);
        hub.reportIntentStale(account, FILL_ID);
    }
}
