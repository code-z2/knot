// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {AccumulatorFactory} from "../src/AccumulatorFactory.sol";
import {Accumulator} from "../src/Accumulator.sol";

contract AccumulatorFactoryTest is Test {
    AccumulatorFactory factory;
    address treasury = address(0xBEEF);

    function setUp() public {
        factory = new AccumulatorFactory(treasury);
    }

    function test_computeAddressMatchesDeploy() public {
        address user = address(0xA11CE);
        address messenger = address(0xB0B);

        address expected = factory.computeAddress(user, messenger);
        vm.prank(user);
        address deployed = factory.deploy(messenger);

        assertEq(deployed, expected);
    }

    function test_deployUsesMsgSenderAsOwner() public {
        address user = address(0xB0B1);
        address messenger = address(0xCAFE);

        vm.prank(user);
        address deployed = factory.deploy(messenger);

        assertEq(Accumulator(payable(deployed)).owner(), user);
    }

    function test_computeAddressDiffersPerUser() public view {
        address messenger = address(0x1234);
        address userA = address(0xA1);
        address userB = address(0xB2);

        assertTrue(factory.computeAddress(userA, messenger) != factory.computeAddress(userB, messenger));
    }
}
