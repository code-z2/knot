// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {GasTank} from "../src/gas-tank/GasTank.sol";
import {IGasTank} from "../src/interfaces/IGasTank.sol";
import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {MessageHashUtils} from "openzeppelin-contracts/utils/cryptography/MessageHashUtils.sol";

// ═══════════════════════════════════════════════════════════════════════════
//                             MOCK ERC20
// ═══════════════════════════════════════════════════════════════════════════

contract MockUSDC {
    string public name = "USD Coin";
    string public symbol = "USDC";
    uint8 public decimals = 6;

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        require(balanceOf[msg.sender] >= amount, "insufficient balance");
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        uint256 allowed = allowance[from][msg.sender];
        require(allowed >= amount, "insufficient allowance");
        require(balanceOf[from] >= amount, "insufficient balance");
        if (allowed != type(uint256).max) {
            allowance[from][msg.sender] = allowed - amount;
        }
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        return true;
    }
}

/// @dev A second ERC20 for sweep testing.
contract MockToken {
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        require(balanceOf[msg.sender] >= amount, "insufficient balance");
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        uint256 allowed = allowance[from][msg.sender];
        require(allowed >= amount, "insufficient allowance");
        require(balanceOf[from] >= amount, "insufficient balance");
        if (allowed != type(uint256).max) {
            allowance[from][msg.sender] = allowed - amount;
        }
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        return true;
    }
}

// ═══════════════════════════════════════════════════════════════════════════
//                              TEST SUITE
// ═══════════════════════════════════════════════════════════════════════════

contract GasTankTest is Test {
    GasTank public tank;
    MockUSDC public usdc;
    MockToken public otherToken;

    address public owner;
    uint256 public cosignerKey;
    address public cosigner;
    address public recipient;
    address public paymaster;

    // EIP-712 constants — must match GasTank
    bytes32 private constant WITHDRAW_TYPEHASH =
        keccak256("Withdraw(uint256 amount,address to,uint256 nonce,uint256 deadline)");

    function setUp() public {
        owner = makeAddr("owner");
        (cosigner, cosignerKey) = makeAddrAndKey("cosigner");
        recipient = makeAddr("recipient");
        paymaster = makeAddr("paymaster");

        usdc = new MockUSDC();
        otherToken = new MockToken();

        tank = new GasTank(owner, cosigner, address(usdc));

        // Fund owner with USDC for deposits
        usdc.mint(owner, 100_000e6);
    }

    // ═══════════════════════════════════════════════════════════════════════
    //                           HELPERS
    // ═══════════════════════════════════════════════════════════════════════

    function _depositAs(address from, uint256 amount) internal {
        vm.startPrank(from);
        usdc.approve(address(tank), amount);
        tank.deposit(amount);
        vm.stopPrank();
    }

    function _signWithdraw(uint256 amount, address to, uint256 nonce, uint256 deadline)
        internal
        view
        returns (bytes memory)
    {
        bytes32 structHash = keccak256(abi.encode(WITHDRAW_TYPEHASH, amount, to, nonce, deadline));
        bytes32 digest = _hashTypedDataV4(structHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(cosignerKey, digest);
        return abi.encodePacked(r, s, v);
    }

    /// @dev Reconstruct the EIP-712 digest exactly as the GasTank does.
    function _hashTypedDataV4(bytes32 structHash) internal view returns (bytes32) {
        bytes32 domainSeparator = keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256("KnotGasTank"),
                keccak256("1"),
                block.chainid,
                address(tank)
            )
        );
        return MessageHashUtils.toTypedDataHash(domainSeparator, structHash);
    }

    // ═══════════════════════════════════════════════════════════════════════
    //                         CONSTRUCTOR
    // ═══════════════════════════════════════════════════════════════════════

    function test_Constructor() public view {
        assertEq(tank.OWNER(), owner);
        assertEq(tank.COSIGNER(), cosigner);
        assertEq(address(tank.USDC()), address(usdc));
        assertEq(tank.FORCED_DELAY(), 4 hours);
        assertEq(tank.withdrawNonce(), 0);
    }

    // ═══════════════════════════════════════════════════════════════════════
    //                            DEPOSIT
    // ═══════════════════════════════════════════════════════════════════════

    function test_Deposit() public {
        _depositAs(owner, 1000e6);
        assertEq(usdc.balanceOf(address(tank)), 1000e6);
    }

    function test_Deposit_FromAnyone() public {
        address alice = makeAddr("alice");
        usdc.mint(alice, 500e6);

        _depositAs(alice, 500e6);
        assertEq(usdc.balanceOf(address(tank)), 500e6);
    }

    function test_Deposit_EmitsEvent() public {
        vm.startPrank(owner);
        usdc.approve(address(tank), 1000e6);

        vm.expectEmit(true, false, false, true);
        emit IGasTank.Deposited(owner, 1000e6);
        tank.deposit(1000e6);
        vm.stopPrank();
    }

    function test_Deposit_DirectTransfer() public {
        // Direct ERC20 transfer (no deposit function) — balance still tracked
        vm.prank(owner);
        usdc.transfer(address(tank), 500e6);
        assertEq(usdc.balanceOf(address(tank)), 500e6);
    }

    function testFuzz_Deposit(uint256 amount) public {
        amount = bound(amount, 1, 100_000e6);
        _depositAs(owner, amount);
        assertEq(usdc.balanceOf(address(tank)), amount);
    }

    // ═══════════════════════════════════════════════════════════════════════
    //                        INSTANT WITHDRAWAL
    // ═══════════════════════════════════════════════════════════════════════

    function test_Withdraw() public {
        _depositAs(owner, 5000e6);

        uint256 deadline = block.timestamp + 1 hours;
        bytes memory sig = _signWithdraw(1000e6, recipient, 0, deadline);

        vm.prank(owner);
        tank.withdraw(1000e6, recipient, deadline, sig);

        assertEq(usdc.balanceOf(recipient), 1000e6);
        assertEq(usdc.balanceOf(address(tank)), 4000e6);
        assertEq(tank.withdrawNonce(), 1);
    }

    function test_Withdraw_EmitsEvent() public {
        _depositAs(owner, 5000e6);

        uint256 deadline = block.timestamp + 1 hours;
        bytes memory sig = _signWithdraw(1000e6, recipient, 0, deadline);

        vm.expectEmit(true, false, false, true);
        emit IGasTank.Withdrawn(recipient, 1000e6);

        vm.prank(owner);
        tank.withdraw(1000e6, recipient, deadline, sig);
    }

    function test_Withdraw_IncrementsNonce() public {
        _depositAs(owner, 5000e6);

        // First withdrawal at nonce 0
        uint256 deadline = block.timestamp + 1 hours;
        bytes memory sig0 = _signWithdraw(1000e6, recipient, 0, deadline);
        vm.prank(owner);
        tank.withdraw(1000e6, recipient, deadline, sig0);
        assertEq(tank.withdrawNonce(), 1);

        // Second withdrawal at nonce 1
        bytes memory sig1 = _signWithdraw(1000e6, recipient, 1, deadline);
        vm.prank(owner);
        tank.withdraw(1000e6, recipient, deadline, sig1);
        assertEq(tank.withdrawNonce(), 2);
    }

    function test_RevertWhen_Withdraw_NotOwner() public {
        _depositAs(owner, 5000e6);

        uint256 deadline = block.timestamp + 1 hours;
        bytes memory sig = _signWithdraw(1000e6, recipient, 0, deadline);

        vm.prank(makeAddr("stranger"));
        vm.expectRevert(IGasTank.NotOwner.selector);
        tank.withdraw(1000e6, recipient, deadline, sig);
    }

    function test_RevertWhen_Withdraw_DeadlineExpired() public {
        _depositAs(owner, 5000e6);

        uint256 deadline = block.timestamp + 1 hours;
        bytes memory sig = _signWithdraw(1000e6, recipient, 0, deadline);

        vm.warp(deadline + 1);
        vm.prank(owner);
        vm.expectRevert(IGasTank.DeadlineExpired.selector);
        tank.withdraw(1000e6, recipient, deadline, sig);
    }

    function test_RevertWhen_Withdraw_InvalidCosignerSig() public {
        _depositAs(owner, 5000e6);

        uint256 deadline = block.timestamp + 1 hours;
        // Sign with wrong nonce → invalid signature for the nonce the contract expects
        bytes memory wrongSig = _signWithdraw(1000e6, recipient, 999, deadline);

        vm.prank(owner);
        vm.expectRevert(IGasTank.InvalidCosignerSignature.selector);
        tank.withdraw(1000e6, recipient, deadline, wrongSig);
    }

    function test_RevertWhen_Withdraw_ReplayOldNonce() public {
        _depositAs(owner, 5000e6);

        uint256 deadline = block.timestamp + 1 hours;
        bytes memory sig0 = _signWithdraw(1000e6, recipient, 0, deadline);

        // First use succeeds
        vm.prank(owner);
        tank.withdraw(1000e6, recipient, deadline, sig0);

        // Replay with same signature fails (nonce is now 1)
        vm.prank(owner);
        vm.expectRevert(IGasTank.InvalidCosignerSignature.selector);
        tank.withdraw(1000e6, recipient, deadline, sig0);
    }

    function test_RevertWhen_Withdraw_WrongAmount() public {
        _depositAs(owner, 5000e6);

        uint256 deadline = block.timestamp + 1 hours;
        bytes memory sig = _signWithdraw(1000e6, recipient, 0, deadline);

        // Try to withdraw different amount than what was signed
        vm.prank(owner);
        vm.expectRevert(IGasTank.InvalidCosignerSignature.selector);
        tank.withdraw(2000e6, recipient, deadline, sig);
    }

    // ═══════════════════════════════════════════════════════════════════════
    //                        FORCED WITHDRAWAL
    // ═══════════════════════════════════════════════════════════════════════

    function test_ForcedWithdrawal_FullLifecycle() public {
        _depositAs(owner, 5000e6);

        // Initiate
        vm.prank(owner);
        tank.initiateForced(3000e6);

        (uint128 amount, uint64 unlockTime) = tank.pendingWithdrawal();
        assertEq(amount, 3000e6);
        assertEq(unlockTime, block.timestamp + 4 hours);

        // Wait 4 hours
        vm.warp(block.timestamp + 4 hours);

        // Claim
        vm.prank(owner);
        tank.claimForced(recipient);

        assertEq(usdc.balanceOf(recipient), 3000e6);
        assertEq(usdc.balanceOf(address(tank)), 2000e6);

        // Pending cleared
        (amount, unlockTime) = tank.pendingWithdrawal();
        assertEq(amount, 0);
        assertEq(unlockTime, 0);
    }

    function test_ForcedWithdrawal_EmitsEvents() public {
        _depositAs(owner, 5000e6);

        uint256 expectedUnlock = block.timestamp + 4 hours;

        vm.expectEmit(false, false, false, true);
        emit IGasTank.ForcedInitiated(3000e6, expectedUnlock);

        vm.prank(owner);
        tank.initiateForced(3000e6);

        vm.warp(expectedUnlock);

        vm.expectEmit(true, false, false, true);
        emit IGasTank.ForcedClaimed(recipient, 3000e6);

        vm.prank(owner);
        tank.claimForced(recipient);
    }

    function test_ForcedWithdrawal_ClaimReducedByDebit() public {
        _depositAs(owner, 5000e6);

        // Initiate forced withdrawal for full balance
        vm.prank(owner);
        tank.initiateForced(5000e6);

        // During the 4h window, cosigner debits outstanding gas fees
        vm.prank(cosigner);
        tank.debit(2000e6, paymaster);

        // After timelock, user claims — gets min(5000, 3000) = 3000
        vm.warp(block.timestamp + 4 hours);
        vm.prank(owner);
        tank.claimForced(recipient);

        assertEq(usdc.balanceOf(recipient), 3000e6);
        assertEq(usdc.balanceOf(paymaster), 2000e6);
    }

    function test_ForcedWithdrawal_Cancel() public {
        _depositAs(owner, 5000e6);

        vm.prank(owner);
        tank.initiateForced(3000e6);

        vm.expectEmit(false, false, false, false);
        emit IGasTank.ForcedCancelled();

        vm.prank(owner);
        tank.cancelForced();

        (uint128 amount,) = tank.pendingWithdrawal();
        assertEq(amount, 0);

        // Balance untouched
        assertEq(usdc.balanceOf(address(tank)), 5000e6);
    }

    function test_RevertWhen_InitiateForced_NotOwner() public {
        vm.prank(makeAddr("stranger"));
        vm.expectRevert(IGasTank.NotOwner.selector);
        tank.initiateForced(1000e6);
    }

    function test_RevertWhen_InitiateForced_AlreadyPending() public {
        _depositAs(owner, 5000e6);

        vm.prank(owner);
        tank.initiateForced(1000e6);

        vm.prank(owner);
        vm.expectRevert(IGasTank.ForcedAlreadyPending.selector);
        tank.initiateForced(2000e6);
    }

    function test_RevertWhen_ClaimForced_NoPending() public {
        vm.prank(owner);
        vm.expectRevert(IGasTank.NoForcedPending.selector);
        tank.claimForced(recipient);
    }

    function test_RevertWhen_ClaimForced_StillLocked() public {
        _depositAs(owner, 5000e6);

        vm.prank(owner);
        tank.initiateForced(1000e6);

        // Try to claim before timelock expires
        vm.warp(block.timestamp + 3 hours);
        vm.prank(owner);
        vm.expectRevert(IGasTank.ForcedStillLocked.selector);
        tank.claimForced(recipient);
    }

    function test_RevertWhen_ClaimForced_NotOwner() public {
        _depositAs(owner, 5000e6);

        vm.prank(owner);
        tank.initiateForced(1000e6);

        vm.warp(block.timestamp + 4 hours);
        vm.prank(makeAddr("stranger"));
        vm.expectRevert(IGasTank.NotOwner.selector);
        tank.claimForced(recipient);
    }

    function test_RevertWhen_CancelForced_NotOwner() public {
        _depositAs(owner, 5000e6);

        vm.prank(owner);
        tank.initiateForced(1000e6);

        vm.prank(makeAddr("stranger"));
        vm.expectRevert(IGasTank.NotOwner.selector);
        tank.cancelForced();
    }

    // ═══════════════════════════════════════════════════════════════════════
    //                         COSIGNER DEBIT
    // ═══════════════════════════════════════════════════════════════════════

    function test_Debit() public {
        _depositAs(owner, 5000e6);

        vm.prank(cosigner);
        tank.debit(1500e6, paymaster);

        assertEq(usdc.balanceOf(paymaster), 1500e6);
        assertEq(usdc.balanceOf(address(tank)), 3500e6);
    }

    function test_Debit_EmitsEvent() public {
        _depositAs(owner, 5000e6);

        vm.expectEmit(false, true, false, true);
        emit IGasTank.Debited(1500e6, paymaster);

        vm.prank(cosigner);
        tank.debit(1500e6, paymaster);
    }

    function test_Debit_ToPaymaster() public {
        _depositAs(owner, 5000e6);

        // Cosigner directs debit to paymaster address
        vm.prank(cosigner);
        tank.debit(1000e6, paymaster);
        assertEq(usdc.balanceOf(paymaster), 1000e6);
    }

    function test_RevertWhen_Debit_NotCosigner() public {
        _depositAs(owner, 5000e6);

        vm.prank(owner);
        vm.expectRevert(IGasTank.NotCosigner.selector);
        tank.debit(1000e6, paymaster);
    }

    function testFuzz_Debit(uint256 depositAmount, uint256 debitAmount) public {
        depositAmount = bound(depositAmount, 1, 100_000e6);
        debitAmount = bound(debitAmount, 1, depositAmount);

        _depositAs(owner, depositAmount);

        vm.prank(cosigner);
        tank.debit(debitAmount, paymaster);

        assertEq(usdc.balanceOf(paymaster), debitAmount);
        assertEq(usdc.balanceOf(address(tank)), depositAmount - debitAmount);
    }

    // ═══════════════════════════════════════════════════════════════════════
    //                          TOKEN SWEEP
    // ═══════════════════════════════════════════════════════════════════════

    function test_Sweep() public {
        // Send non-USDC token to tank by mistake
        otherToken.mint(address(tank), 1000e18);

        vm.prank(owner);
        tank.sweep(address(otherToken), recipient);

        assertEq(otherToken.balanceOf(recipient), 1000e18);
        assertEq(otherToken.balanceOf(address(tank)), 0);
    }

    function test_Sweep_EmitsEvent() public {
        otherToken.mint(address(tank), 500e18);

        vm.expectEmit(true, true, false, true);
        emit IGasTank.Swept(address(otherToken), recipient, 500e18);

        vm.prank(owner);
        tank.sweep(address(otherToken), recipient);
    }

    function test_RevertWhen_Sweep_NotOwner() public {
        otherToken.mint(address(tank), 1000e18);

        vm.prank(makeAddr("stranger"));
        vm.expectRevert(IGasTank.NotOwner.selector);
        tank.sweep(address(otherToken), recipient);
    }

    function test_RevertWhen_Sweep_USDC() public {
        _depositAs(owner, 1000e6);

        vm.prank(owner);
        vm.expectRevert(IGasTank.CannotSweepUSDC.selector);
        tank.sweep(address(usdc), recipient);
    }

    // ═══════════════════════════════════════════════════════════════════════
    //                       CREATE2 DEPLOYMENT
    // ═══════════════════════════════════════════════════════════════════════

    function test_Create2_AddressPrediction() public {
        address expectedOwner = makeAddr("create2user");
        bytes32 salt = keccak256(abi.encode("knot-gas-tank-v1", expectedOwner));

        bytes memory initCode =
            abi.encodePacked(type(GasTank).creationCode, abi.encode(expectedOwner, cosigner, address(usdc)));

        // Predict address
        address predicted = _computeCreate2(address(this), salt, initCode);

        // Deploy via CREATE2
        address deployed;
        assembly {
            deployed := create2(0, add(initCode, 0x20), mload(initCode), salt)
        }

        assertEq(deployed, predicted);
        assertEq(GasTank(deployed).OWNER(), expectedOwner);
        assertEq(GasTank(deployed).COSIGNER(), cosigner);
    }

    function test_Create2_PreDeploymentBalance() public {
        address expectedOwner = makeAddr("predeployuser");
        bytes32 salt = keccak256(abi.encode("knot-gas-tank-v1", expectedOwner));

        bytes memory initCode =
            abi.encodePacked(type(GasTank).creationCode, abi.encode(expectedOwner, cosigner, address(usdc)));

        address predicted = _computeCreate2(address(this), salt, initCode);

        // Send USDC to predicted address BEFORE deployment
        usdc.mint(predicted, 2000e6);
        assertEq(usdc.balanceOf(predicted), 2000e6);

        // Deploy
        address deployed;
        assembly {
            deployed := create2(0, add(initCode, 0x20), mload(initCode), salt)
        }

        // Balance accessible after deployment
        assertEq(usdc.balanceOf(deployed), 2000e6);
        assertEq(deployed, predicted);
    }

    function test_Create2_PermissionlessDeploy() public {
        // Anyone can deploy for any user — constructor args are deterministic
        address expectedOwner = makeAddr("anyuser");
        address deployer = makeAddr("anydeployer");

        bytes memory initCode =
            abi.encodePacked(type(GasTank).creationCode, abi.encode(expectedOwner, cosigner, address(usdc)));

        bytes32 salt = keccak256(abi.encode("knot-gas-tank-v1", expectedOwner));

        vm.prank(deployer);
        address deployed;
        assembly {
            deployed := create2(0, add(initCode, 0x20), mload(initCode), salt)
        }

        // Owner is the user, not the deployer
        assertEq(GasTank(deployed).OWNER(), expectedOwner);
    }

    // ═══════════════════════════════════════════════════════════════════════
    //                     INTEGRATION SCENARIOS
    // ═══════════════════════════════════════════════════════════════════════

    function test_Integration_DepositWithdrawDebit() public {
        // 1. Owner deposits 10,000 USDC
        _depositAs(owner, 10_000e6);

        // 2. Cosigner debits 500 USDC for gas at end of billing cycle
        vm.prank(cosigner);
        tank.debit(500e6, paymaster);

        // 3. Owner withdraws 5,000 USDC (co-signed)
        uint256 deadline = block.timestamp + 1 hours;
        bytes memory sig = _signWithdraw(5000e6, recipient, 0, deadline);

        vm.prank(owner);
        tank.withdraw(5000e6, recipient, deadline, sig);

        // Assertions
        assertEq(usdc.balanceOf(address(tank)), 4500e6); // 10000 - 500 - 5000
        assertEq(usdc.balanceOf(paymaster), 500e6);
        assertEq(usdc.balanceOf(recipient), 5000e6);
    }

    function test_Integration_ForcedWithdrawal_DebitDuringWindow() public {
        _depositAs(owner, 10_000e6);

        // 1. Owner initiates forced withdrawal for full balance
        vm.prank(owner);
        tank.initiateForced(10_000e6);

        // 2. During 4h window, cosigner debits outstanding gas fees
        vm.warp(block.timestamp + 1 hours);
        vm.prank(cosigner);
        tank.debit(3000e6, paymaster);

        // 3. After timelock, user claims — gets 7000 (min of 10000 requested, 7000 available)
        vm.warp(block.timestamp + 3 hours);
        vm.prank(owner);
        tank.claimForced(recipient);

        assertEq(usdc.balanceOf(recipient), 7000e6);
        assertEq(usdc.balanceOf(paymaster), 3000e6);
        assertEq(usdc.balanceOf(address(tank)), 0);
    }

    // ═══════════════════════════════════════════════════════════════════════
    //                            HELPERS
    // ═══════════════════════════════════════════════════════════════════════

    function _computeCreate2(address deployer, bytes32 salt, bytes memory initCode) internal pure returns (address) {
        return address(uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff), deployer, salt, keccak256(initCode))))));
    }
}
