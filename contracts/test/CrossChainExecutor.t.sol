// SPDX-License-Identifier: MIT
pragma solidity ^0.8.33;

import {Test} from "forge-std/Test.sol";
import {AccountERC7579} from "openzeppelin-contracts/account/extensions/draft-AccountERC7579.sol";

import {CrossChainExecutor} from "../src/CrossChainExecutor.sol";
import {ICrossChainExecutor} from "../src/interfaces/ICrossChainExecutor.sol";
import {ISpokePool} from "../src/interfaces/ISpokePool.sol";
import {DispatchOrder, OnchainCrossChainOrder} from "../src/types/Structs.sol";

contract MockERC20ForExecutor {
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }
}

contract MockSpokePoolForExecutor is ISpokePool {
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

    function lastDepositMessage() external view returns (bytes memory) {
        return lastDeposit.message;
    }

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

contract ExecutorAccountMock is AccountERC7579 {
    constructor(address executor, bytes memory initData) {
        _installModule(2, executor, initData);
    }

    function dispatchOrder(ICrossChainExecutor executor, OnchainCrossChainOrder calldata order) external payable {
        executor.dispatch{value: msg.value}(order);
    }

    function uninstallExecutor(address executor) external {
        _uninstallModule(2, executor, "");
    }

    function _rawSignatureValidation(bytes32, bytes calldata) internal view override returns (bool) {
        return false;
    }
}

contract CrossChainExecutorTest is Test {
    CrossChainExecutor executor;
    ExecutorAccountMock account;
    MockSpokePoolForExecutor spokePool;
    MockERC20ForExecutor token;

    function setUp() public {
        executor = new CrossChainExecutor();
        spokePool = new MockSpokePoolForExecutor();
        token = new MockERC20ForExecutor();

        account = new ExecutorAccountMock(address(executor), abi.encode(address(spokePool)));

        vm.deal(address(account), 20 ether);
        token.mint(address(account), 1_000 ether);
    }

    function test_onInstall_setsConfig() public view {
        assertEq(executor.configOf(address(account)), address(spokePool));
    }

    function test_onInstall_revertsForZeroSpokePool() public {
        vm.expectRevert(CrossChainExecutor.InvalidSpokePool.selector);
        vm.prank(address(account));
        executor.onInstall(abi.encode(address(0)));
    }

    function test_onUninstall_clearsConfig() public {
        account.uninstallExecutor(address(executor));

        assertEq(executor.configOf(address(account)), address(0));
    }

    function test_dispatch_depositsToSpokePool() public {
        bytes32 salt = keccak256("dispatch-salt");
        uint32 fillDeadline = uint32(block.timestamp + 10 minutes);
        OnchainCrossChainOrder memory order = _buildCrossChainOrder(
            fillDeadline,
            DispatchOrder({
                salt: salt,
                destChainId: 42161,
                outputToken: address(token),
                sumOutput: 100,
                inputAmount: 110,
                inputToken: address(token),
                minOutput: 100,
                recipient: address(account)
            })
        );

        account.dispatchOrder(executor, order);

        assertEq(spokePool.depositCallCount(), 1);
        assertEq(token.allowance(address(account), address(spokePool)), 110);

        (
            bytes32 depositor,
            bytes32 recipient,
            bytes32 inputToken,
            bytes32 outputToken,
            uint256 inputAmount,
            uint256 outputAmount,
            uint256 destinationChainId,,,
            uint32 recordedFillDeadline,,
            bytes memory message,
            uint256 depositValue
        ) = spokePool.lastDeposit();

        assertEq(depositor, bytes32(uint256(uint160(address(account)))));
        assertEq(recipient, bytes32(uint256(uint160(address(account)))));
        assertEq(inputToken, bytes32(uint256(uint160(address(token)))));
        assertEq(outputToken, bytes32(uint256(uint160(address(token)))));
        assertEq(inputAmount, 110);
        assertEq(outputAmount, 100);
        assertEq(destinationChainId, 42161);
        assertEq(recordedFillDeadline, fillDeadline);
        assertEq(depositValue, 0);

        (
            bytes32 messageSalt,
            uint256 fromChainId,
            uint32 messageDeadline,
            address depositorAccount,
            uint256 sumOutput,
            address messageOutputToken
        ) = abi.decode(message, (bytes32, uint256, uint32, address, uint256, address));

        assertEq(messageSalt, salt);
        assertEq(fromChainId, block.chainid);
        assertEq(messageDeadline, fillDeadline);
        assertEq(depositorAccount, address(account));
        assertEq(sumOutput, 100);
        assertEq(messageOutputToken, address(token));
    }

    function test_dispatch_directBridge_omitsMessage() public {
        address directRecipient = address(0xBEEF);
        OnchainCrossChainOrder memory order = _buildCrossChainOrder(
            uint32(block.timestamp + 10 minutes),
            DispatchOrder({
                salt: keccak256("direct-bridge"),
                destChainId: 8453,
                outputToken: address(token),
                sumOutput: 100,
                inputAmount: 110,
                inputToken: address(token),
                minOutput: 90,
                recipient: directRecipient
            })
        );

        account.dispatchOrder(executor, order);

        (, bytes32 recipient,,,,,,,,,, bytes memory message,) = spokePool.lastDeposit();
        assertEq(recipient, bytes32(uint256(uint160(directRecipient))));
        assertEq(message.length, 0);
    }

    function test_dispatch_revertsWhenSaltReused() public {
        bytes32 salt = keccak256("salt-reused");
        OnchainCrossChainOrder memory order = _buildCrossChainOrder(
            uint32(block.timestamp + 10 minutes),
            DispatchOrder({
                salt: salt,
                destChainId: 42161,
                outputToken: address(token),
                sumOutput: 100,
                inputAmount: 110,
                inputToken: address(token),
                minOutput: 100,
                recipient: address(account)
            })
        );

        account.dispatchOrder(executor, order);

        vm.expectRevert(abi.encodeWithSelector(CrossChainExecutor.SaltAlreadyUsed.selector, salt));
        account.dispatchOrder(executor, order);
    }

    function test_dispatch_revertsWhenFillDeadlineTooSoon() public {
        OnchainCrossChainOrder memory order = _buildCrossChainOrder(
            uint32(block.timestamp + 60),
            DispatchOrder({
                salt: keccak256("too-soon"),
                destChainId: 42161,
                outputToken: address(token),
                sumOutput: 100,
                inputAmount: 110,
                inputToken: address(token),
                minOutput: 100,
                recipient: address(account)
            })
        );

        vm.expectRevert();
        account.dispatchOrder(executor, order);
    }

    function test_dispatch_revertsOnInvalidOrderDataType() public {
        OnchainCrossChainOrder memory order = OnchainCrossChainOrder({
            fillDeadline: uint32(block.timestamp + 10 minutes),
            orderDataType: keccak256("WrongType()"),
            orderData: abi.encode(
                DispatchOrder({
                    salt: keccak256("bad-type"),
                    destChainId: 42161,
                    outputToken: address(token),
                    sumOutput: 100,
                    inputAmount: 110,
                    inputToken: address(token),
                    minOutput: 100,
                    recipient: address(account)
                })
            )
        });

        vm.expectRevert();
        account.dispatchOrder(executor, order);
    }

    function test_dispatch_nativeDeposit_sendsValueWithoutApproval() public {
        OnchainCrossChainOrder memory order = _buildCrossChainOrder(
            uint32(block.timestamp + 10 minutes),
            DispatchOrder({
                salt: keccak256("native"),
                destChainId: 8453,
                outputToken: address(token),
                sumOutput: 100,
                inputAmount: 1 ether,
                inputToken: address(0),
                minOutput: 100,
                recipient: address(account)
            })
        );

        account.dispatchOrder{value: 1 ether}(executor, order);

        (,,,,,,,,,,,, uint256 depositValue) = spokePool.lastDeposit();
        assertEq(depositValue, 1 ether);
        assertEq(token.allowance(address(account), address(spokePool)), 0);
    }

    function _buildCrossChainOrder(uint32 fillDeadline, DispatchOrder memory dispatchOrder)
        internal
        view
        returns (OnchainCrossChainOrder memory)
    {
        return OnchainCrossChainOrder({
            fillDeadline: fillDeadline,
            orderDataType: executor.DISPATCH_ORDER_TYPEHASH(),
            orderData: abi.encode(dispatchOrder)
        });
    }
}
