// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import { Test } from "forge-std/Test.sol";
import { Deploy } from "../script/Deploy.s.sol";
import { DeployBroken } from "./script/DeployBroken.s.sol";
import { DeploymentConfig } from "../script/DeploymentConfig.s.sol";
import { StakeManager } from "../contracts/StakeManager.sol";
import { StakeVault } from "../contracts/StakeVault.sol";
import { VaultFactory } from "../contracts/VaultFactory.sol";

contract StakeVaultTest is Test {
    StakeManager internal stakeManager;

    DeploymentConfig internal deploymentConfig;

    VaultFactory internal vaultFactory;

    StakeVault internal stakeVault;

    StakeVault internal stakeVault2;

    address internal deployer;

    address internal testUser = makeAddr("testUser");

    address internal testUser2 = makeAddr("testUser2");

    address internal stakeToken;

    function setUp() public virtual {
        Deploy deployment = new Deploy();
        (vaultFactory, stakeManager, deploymentConfig) = deployment.run();
        (deployer, stakeToken) = deploymentConfig.activeNetworkConfig();

        vm.prank(testUser);
        stakeVault = vaultFactory.createVault();

        vm.prank(testUser2);
        stakeVault2 = vaultFactory.createVault();
    }
}

contract StakedTokenTest is StakeVaultTest {
    function setUp() public override {
        StakeVaultTest.setUp();
    }

    function testStakeToken() public {
        assertEq(address(stakeVault.stakedToken()), stakeToken);
    }
}

contract DepositTest is StakeVaultTest {

    event Deposit(uint256 indexed amount);

    function setUp() public override {
        StakeVaultTest.setUp();
    }

    function test_RevertWhen_DepositAndDepositCoolingDown() public {
        deal(stakeToken, testUser, 1000);
        vm.startPrank(testUser);
        ERC20(stakeToken).approve(address(stakeVault), 100);
        stakeVault.deposit(100);
        vm.expectRevert(StakeVault.StakeVault__DepositCoolingDown.selector);
        stakeVault.deposit(100);
    }

    function test_Deposit() public {
        uint256 userFunds = 1000;
        uint256 depositAmount = 100;

        deal(stakeToken, testUser, userFunds);
        deal(stakeToken, testUser2, userFunds);

        // first user
        vm.startPrank(testUser);
        ERC20(stakeToken).approve(address(stakeVault), depositAmount);

        vm.expectEmit(true, true, true, true);
        emit Deposit(depositAmount);
        stakeVault.deposit(depositAmount);

        assertEq(ERC20(stakeToken).balanceOf(address(stakeVault)), depositAmount);
        assertEq(stakeVault.balance(), depositAmount);
        assertEq(stakeVault.depositCooldownUntil(), block.timestamp + stakeManager.DEPOSIT_COOLDOWN_PERIOD());
        // ensure funds haven't reached stake manager yet
        assertEq(stakeManager.totalSupply(), 0);
    }

    function test_DepositAfterCooldown() public {
        uint256 userFunds = 1000;
        uint256 depositAmount = 100;
        deal(stakeToken, testUser, userFunds);

        vm.startPrank(testUser);
        ERC20(stakeToken).approve(address(stakeVault), depositAmount);

        // make first deposit
        vm.expectEmit(true, true, true, true);
        emit Deposit(depositAmount);
        stakeVault.deposit(depositAmount);

        assertEq(ERC20(stakeToken).balanceOf(address(stakeVault)), depositAmount);
        assertEq(stakeVault.balance(), depositAmount);
        assertEq(stakeVault.depositCooldownUntil(), block.timestamp + stakeManager.DEPOSIT_COOLDOWN_PERIOD());
        assertEq(stakeManager.totalSupply(), 0);

        // wait for deposit cooldown to elapse
        vm.warp(stakeVault.depositCooldownUntil() + 1);

        ERC20(stakeToken).approve(address(stakeVault), depositAmount);

        // make second deposit after first deposit has cooled down
        vm.expectEmit(true, true, true, true);
        emit Deposit(depositAmount);
        stakeVault.deposit(depositAmount);

        assertEq(ERC20(stakeToken).balanceOf(address(stakeVault)), depositAmount * 2);
        assertEq(stakeVault.balance(), depositAmount * 2);
        assertEq(stakeVault.depositCooldownUntil(), block.timestamp + stakeManager.DEPOSIT_COOLDOWN_PERIOD());
        assertEq(stakeManager.totalSupply(), 0);
    }
}

contract WithdrawTest is StakeVaultTest {

    event Withdraw(uint256 indexed amount);

    uint256 internal stakeAmount = 100;
    uint256 internal userFunds = 1000;

    function setUp() public override {
        StakeVaultTest.setUp();
        deal(stakeToken, testUser, userFunds);

        vm.startPrank(testUser);
        ERC20(stakeToken).approve(address(stakeVault), stakeAmount);
        stakeVault.deposit(stakeAmount);
    }

    function test_RevertWhen_WithdrawInsufficientFunds() public {
        vm.startPrank(testUser);
        vm.expectRevert(StakeVault.StakeVault__InsufficientFunds.selector);
        stakeVault.withdraw(stakeAmount + 1);
    }

    function test_Withdraw() public {
        vm.startPrank(testUser);
        vm.expectEmit(true, true, true, true);
        emit Withdraw(stakeAmount);
        stakeVault.withdraw(stakeAmount);

        assertEq(stakeVault.balance(), 0);
        assertEq(ERC20(stakeToken).balanceOf(address(stakeVault)), 0);
        assertEq(ERC20(stakeToken).balanceOf(testUser), userFunds);
    }

    function test_WithdrawLessAmountThanAvailable() public {
        uint256 remainingAmount = 50;
        vm.startPrank(testUser);
        vm.expectEmit(true, true, true, true);
        emit Withdraw(stakeAmount - remainingAmount);
        stakeVault.withdraw(stakeAmount - remainingAmount);

        assertEq(stakeVault.balance(), remainingAmount);
        assertEq(ERC20(stakeToken).balanceOf(address(stakeVault)), remainingAmount);
        assertEq(ERC20(stakeToken).balanceOf(testUser), userFunds - remainingAmount);
    }
}

contract StakeTest is StakeVaultTest {

    event Staked(address from, uint256 indexed amount, uint256 indexed time);

    uint256 internal userFunds = 1000;
    uint256 internal stakeAmount = 100;

    function setUp() public override {
        StakeVaultTest.setUp();
        deal(stakeToken, testUser, userFunds);
    }

    function test_RevertWhen_StakeAndDepositCoolingDown() public {
        vm.startPrank(testUser);
        ERC20(stakeToken).approve(address(stakeVault), stakeAmount);
        stakeVault.deposit(stakeAmount);

        vm.expectRevert(StakeVault.StakeVault__DepositCoolingDown.selector);
        stakeVault.stake(stakeAmount);
    }

    function test_RevertWhen_StakeAndInsufficientFunds() public {
        vm.startPrank(testUser);
        vm.expectRevert(StakeVault.StakeVault__InsufficientFunds.selector);
        stakeVault.stake(stakeAmount + 1);

        // do another one, this time with deposited funds (but too little)
        vm.startPrank(testUser);
        ERC20(stakeToken).approve(address(stakeVault), stakeAmount);
        stakeVault.deposit(stakeAmount);

        // make sure deposit cooldown has passed
        vm.warp(stakeVault.depositCooldownUntil() + 1);

        vm.expectRevert(StakeVault.StakeVault__InsufficientFunds.selector);
        stakeVault.stake(stakeAmount + 1);
    }

    function test_Stake() public {
        vm.startPrank(testUser);
        ERC20(stakeToken).approve(address(stakeVault), stakeAmount);
        stakeVault.deposit(stakeAmount);

        // make sure deposit cooldown has passed
        vm.warp(stakeVault.depositCooldownUntil() + 1);

        vm.expectEmit(true, true, true, true);
        emit Staked(address(stakeVault), stakeAmount, 0);
        stakeVault.stake(stakeAmount);

        assertEq(stakeVault.balance(), stakeAmount);
        assertEq(ERC20(stakeToken).balanceOf(address(stakeVault)), stakeAmount);
        assertEq(ERC20(stakeToken).balanceOf(testUser), userFunds - stakeAmount);
        assertEq(stakeManager.totalSupply(), stakeAmount);
    }
}

// contract StakeTest is StakeVaultTest {
//     function setUp() public override {
//         DeployBroken deployment = new DeployBroken();
//         (vaultFactory, stakeManager, stakeToken) = deployment.run();
//
//         vm.prank(testUser);
//         stakeVault = vaultFactory.createVault();
//     }
//
//     // function test_RevertWhen_StakeTokenTransferFails() public {
//     //     // ensure user has funds
//     //     deal(stakeToken, testUser, 1000);
//     //
//     //     vm.startPrank(address(testUser));
//     //     ERC20(stakeToken).approve(address(stakeVault), 100);
//     //     vm.expectRevert(StakeVault.StakeVault__StakingFailed.selector);
//     //     stakeVault.stake(100, 0);
//     // }
// }
