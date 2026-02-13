// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {AccumulatorFactory} from "../src/AccumulatorFactory.sol";
import {Accumulator} from "../src/Accumulator.sol";

contract AccumulatorFactoryTest is Test {
    AccumulatorFactory factory;

    function setUp() public {
        factory = new AccumulatorFactory();
    }

    function test_computeAddressMatchesDeploy() public {
        address user = address(0xA11CE);
        address spokePool = address(0xB0B);

        address expected = factory.computeAddress(user);
        vm.prank(user);
        address deployed = factory.deploy(spokePool);

        assertEq(deployed, expected);
    }

    function test_deployUsesMsgSenderAsOwner() public {
        address user = address(0xB0B1);
        address spokePool = address(0xCAFE);

        vm.prank(user);
        address deployed = factory.deploy(spokePool);

        assertEq(Accumulator(payable(deployed)).owner(), user);
    }

    function test_computeAddressDiffersPerUser() public view {
        address userA = address(0xA1);
        address userB = address(0xB2);

        assertTrue(factory.computeAddress(userA) != factory.computeAddress(userB));
    }

    function test_deployFromAccountInitialize() public {
        // Simulate the flow: account calls factory.deploy() during initialize
        address accountAddr = address(0xACC7);
        address spokePool = address(0x3E55);

        address predicted = factory.computeAddress(accountAddr);
        vm.prank(accountAddr);
        address deployed = factory.deploy(spokePool);

        assertEq(deployed, predicted);
        assertEq(Accumulator(payable(deployed)).owner(), accountAddr);
    }
}
