// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import { Test, console2 } from "forge-std/Test.sol";
import { Deploy } from "../script/Deploy.s.sol";
import { DeploymentConfig } from "../script/DeploymentConfig.s.sol";
import { StakeManager } from "../contracts/StakeManager.sol";
import { StakeVault } from "../contracts/StakeVault.sol";
import { VaultFactory } from "../contracts/VaultFactory.sol";

contract StakeManagerTest is Test {
    DeploymentConfig internal deploymentConfig;
    StakeManager internal stakeManager;
    VaultFactory internal vaultFactory;
    StakeManager internal migrationStakeManager;

    address internal stakeToken;
    address internal deployer;
    address internal testUser = makeAddr("testUser");
    address internal testUser2 = makeAddr("testUser2");

    function setUp() public virtual {
        Deploy deployment = new Deploy();
        (vaultFactory, stakeManager, migrationStakeManager, deploymentConfig) = deployment.run();
        (deployer, stakeToken) = deploymentConfig.activeNetworkConfig();
    }

    function testDeployment() public {
        assertEq(stakeManager.owner(), deployer);
        assertEq(stakeManager.currentEpoch(), 0);
        assertEq(stakeManager.pendingReward(), 0);
        assertEq(stakeManager.totalSupplyMP(), 0);
        assertEq(stakeManager.totalSupplyBalance(), 0);
        assertEq(address(stakeManager.stakedToken()), stakeToken);
        assertEq(address(stakeManager.oldManager()), address(0));
        assertEq(stakeManager.totalSupply(), 0);
    }

    function _createTestVault(address owner) internal returns (StakeVault vault) {
        vm.prank(owner);
        vault = vaultFactory.createVault();

        if (!stakeManager.isVault(address(vault).codehash)) {
            vm.prank(deployer);
            stakeManager.setVault(address(vault).codehash);
        }
    }
}

contract StakeTest is StakeManagerTest {
    function setUp() public override {
        StakeManagerTest.setUp();
    }

    function test_RevertWhen_SenderIsNotVault() public {
        vm.expectRevert(StakeManager.StakeManager__SenderIsNotVault.selector);
        stakeManager.stake(100, 1);
    }

    function test_RevertWhen_InvalidLockupPeriod() public {
        // ensure user has funds
        deal(stakeToken, testUser, 1000);
        StakeVault userVault = _createTestVault(testUser);

        vm.startPrank(testUser);
        ERC20(stakeToken).approve(address(userVault), 100);

        uint256 lockTime = stakeManager.MIN_LOCKUP_PERIOD() - 1;
        vm.expectRevert(StakeManager.StakeManager__InvalidLockupPeriod.selector);
        userVault.stake(100, lockTime);

        lockTime = stakeManager.MAX_LOCKUP_PERIOD() + 1;
        vm.expectRevert(StakeManager.StakeManager__InvalidLockupPeriod.selector);
        userVault.stake(100, lockTime);
    }

    function test_StakeWithoutLockUpTimeMintsMultiplierPoints() public {
        // ensure user has funds
        deal(stakeToken, testUser, 1000);
        StakeVault userVault = _createTestVault(testUser);

        vm.startPrank(testUser);
        ERC20(stakeToken).approve(address(userVault), 100);

        // stake without lockup time
        userVault.stake(100, 0);

        (,, uint256 currentMP,,,,) = stakeManager.accounts(address(userVault));

        // total multiplier poitn supply
        assertEq(stakeManager.totalSupplyMP(), 100);
        // user multiplier points
        assertEq(currentMP, 100);

        userVault.unstake(100);

        // multiplierpoints are burned after unstaking
        (,,, currentMP,,,) = stakeManager.accounts(address(userVault));
        assertEq(stakeManager.totalSupplyMP(), 0);
        assertEq(currentMP, 0);
    }

    function test_updateLockUpTime() public { }

    function test_mintBonusMP() public { }

    function test_updateBonusMP() public { }

    function test_updateTotalSupplies() public { }
}

contract UnstakeTest is StakeManagerTest {
    function setUp() public override {
        StakeManagerTest.setUp();
    }

    function test_RevertWhen_SenderIsNotVault() public {
        vm.expectRevert(StakeManager.StakeManager__SenderIsNotVault.selector);
        stakeManager.unstake(1);
    }

    function test_RevertWhen_FundsLocked() public {
        // ensure user has funds
        deal(stakeToken, testUser, 1000);
        StakeVault userVault = _createTestVault(testUser);

        vm.startPrank(testUser);
        ERC20(stakeToken).approve(address(userVault), 100);

        uint256 lockTime = stakeManager.MIN_LOCKUP_PERIOD();
        userVault.stake(100, lockTime);

        vm.expectRevert(StakeManager.StakeManager__FundsLocked.selector);
        userVault.unstake(1);
    }

    function test_UnstakeShouldReturnFund_NoLockUp() public {
        // ensure user has funds
        deal(stakeToken, testUser, 1000);
        StakeVault userVault = _createTestVault(testUser);

        vm.startPrank(testUser);
        ERC20(stakeToken).approve(address(userVault), 100);

        userVault.stake(100, 0);
        assertEq(ERC20(stakeToken).balanceOf(testUser), 900);

        userVault.unstake(100);

        assertEq(stakeManager.totalSupplyBalance(), 0);
        assertEq(ERC20(stakeToken).balanceOf(address(userVault)), 0);
        assertEq(ERC20(stakeToken).balanceOf(testUser), 1000);
    }

    function test_UnstakeShouldReturnFund_WithLockUp() public {
        // ensure user has funds
        deal(stakeToken, testUser, 1000);
        StakeVault userVault = _createTestVault(testUser);

        vm.startPrank(testUser);
        ERC20(stakeToken).approve(address(userVault), 100);

        uint256 lockTime = stakeManager.MIN_LOCKUP_PERIOD();
        userVault.stake(100, lockTime);
        assertEq(ERC20(stakeToken).balanceOf(testUser), 900);

        vm.warp(block.timestamp + lockTime + 1);

        userVault.unstake(100);

        assertEq(stakeManager.totalSupplyBalance(), 0);
        assertEq(ERC20(stakeToken).balanceOf(address(userVault)), 0);
        assertEq(ERC20(stakeToken).balanceOf(testUser), 1000);
    }
}

contract LockTest is StakeManagerTest {
    function setUp() public override {
        StakeManagerTest.setUp();
    }

    function test_RevertWhen_SenderIsNotVault() public {
        vm.expectRevert(StakeManager.StakeManager__SenderIsNotVault.selector);
        stakeManager.lock(100);
    }

    function test_RevertWhen_InvalidLockupPeriod() public {
        // ensure user has funds
        deal(stakeToken, testUser, 1000);
        StakeVault userVault = _createTestVault(testUser);

        vm.startPrank(testUser);
        // ensure user vault can spend user tokens
        ERC20(stakeToken).approve(address(userVault), 100);

        uint256 lockTime = stakeManager.MAX_LOCKUP_PERIOD() + 1;
        vm.expectRevert(StakeManager.StakeManager__InvalidLockupPeriod.selector);
        userVault.stake(100, lockTime);
    }
}

contract LeaveTest is StakeManagerTest {
    function setUp() public override {
        StakeManagerTest.setUp();
    }

    function test_RevertWhen_SenderIsNotVault() public {
        vm.expectRevert(StakeManager.StakeManager__SenderIsNotVault.selector);
        stakeManager.migrateTo(false);
    }

    function test_RevertWhen_NoPendingMigration() public {
        deal(stakeToken, testUser, 1000);
        StakeVault userVault = _createTestVault(testUser);

        vm.startPrank(testUser);
        ERC20(stakeToken).approve(address(userVault), 100);

        // stake without lockup time
        userVault.stake(100, 0);

        vm.expectRevert(StakeManager.StakeManager__NoPendingMigration.selector);
        userVault.acceptMigration();

        vm.expectRevert(StakeManager.StakeManager__NoPendingMigration.selector);
        userVault.leave();
        vm.stopPrank();
    }
}

contract MigrateTest is StakeManagerTest {
    function setUp() public override {
        StakeManagerTest.setUp();
    }

    function test_RevertWhen_SenderIsNotVault() public {
        vm.expectRevert(StakeManager.StakeManager__SenderIsNotVault.selector);
        stakeManager.migrateTo(true);
    }

    function test_RevertWhen_NoPendingMigration() public {
        deal(stakeToken, testUser, 1000);
        StakeVault userVault = _createTestVault(testUser);

        vm.startPrank(testUser);
        ERC20(stakeToken).approve(address(userVault), 100);
        // stake without lockup time
        userVault.stake(100, 0);

        vm.expectRevert(StakeManager.StakeManager__NoPendingMigration.selector);
        userVault.acceptMigration();
        vm.stopPrank();
    }

    function increaseEpoch(uint256 epochNumber) internal { }
}

contract ExecuteAccountTest is StakeManagerTest {
    function setUp() public override {
        StakeManagerTest.setUp();
    }

    function test_RevertWhen_InvalidLimitEpoch() public {
        deal(stakeToken, testUser, 1000);
        StakeVault userVault = _createTestVault(testUser);

        vm.startPrank(testUser);
        ERC20(stakeToken).approve(address(userVault), 100);

        uint256 lockTime = stakeManager.MIN_LOCKUP_PERIOD();
        userVault.stake(100, lockTime);

        uint256 currentEpoch = stakeManager.currentEpoch();

        vm.expectRevert(StakeManager.StakeManager__InvalidLimitEpoch.selector);
        stakeManager.executeAccount(address(userVault), currentEpoch + 1);
    }

    function test_ExecuteAccountMintMP() public {
        uint256 stakeAmount = 10_000_000;
        deal(stakeToken, testUser, stakeAmount);
        StakeVault userVault = _createTestVault(testUser);
        vm.startPrank(testUser);
        ERC20(stakeToken).approve(address(userVault), stakeAmount);
        userVault.stake(stakeAmount, 0);
        
        vm.warp(stakeManager.epochEnd()-1);
        stakeManager.executeAccount(address(userVault), stakeManager.currentEpoch());

        
        for (uint256 i = 0; i < 54; i++) {
            vm.warp(stakeManager.epochEnd());
            stakeManager.executeAccount(address(userVault), stakeManager.currentEpoch());
            console2.log("current epoch", stakeManager.currentEpoch());
            console2.log("account MP", stakeManager.getAccount(address(userVault)).currentMP);
        }
    }

    function test_UpdateEpoch() public { }
    function test_PayRewards() public { }

    function test_MintMPLimit() public { }
}

contract UserFlowsTest is StakeManagerTest {
    function setUp() public override {
        StakeManagerTest.setUp();
    }

    function test_StakedSupplyShouldIncreaseAndDecreaseAgain() public {
        // ensure users have funds
        deal(stakeToken, testUser, 1000);
        deal(stakeToken, testUser2, 1000);

        StakeVault userVault = _createTestVault(testUser);
        StakeVault user2Vault = _createTestVault(testUser2);

        vm.startPrank(testUser);
        // approve user vault to spend user tokens
        ERC20(stakeToken).approve(address(userVault), 100);
        userVault.stake(100, 0);
        vm.stopPrank();

        vm.startPrank(testUser2);
        ERC20(stakeToken).approve(address(user2Vault), 100);
        user2Vault.stake(100, 0);
        vm.stopPrank();

        assertEq(ERC20(stakeToken).balanceOf(address(userVault)), 100);
        assertEq(ERC20(stakeToken).balanceOf(address(user2Vault)), 100);
        assertEq(stakeManager.totalSupplyBalance(), 200);

        vm.startPrank(testUser);
        userVault.unstake(100);
        assertEq(ERC20(stakeToken).balanceOf(address(userVault)), 0);
        assertEq(stakeManager.totalSupplyBalance(), 100);

        vm.startPrank(testUser2);
        user2Vault.unstake(100);
        assertEq(ERC20(stakeToken).balanceOf(address(user2Vault)), 0);
        assertEq(stakeManager.totalSupplyBalance(), 0);
    }

    function test_StakeWithLockUpTimeLocksStake() public {
        // ensure users have funds
        deal(stakeToken, testUser, 1000);

        StakeVault userVault = _createTestVault(testUser);

        vm.startPrank(testUser);
        // approve user vault to spend user tokens
        ERC20(stakeToken).approve(address(userVault), 100);

        // stake with lockup time of 12 weeks
        userVault.stake(100, 12 weeks);

        // unstaking should fail as lockup time isn't over yet
        vm.expectRevert(StakeManager.StakeManager__FundsLocked.selector);
        userVault.unstake(100);

        // fast forward 12 weeks
        skip(12 weeks + 1);

        userVault.unstake(100);
        assertEq(ERC20(stakeToken).balanceOf(address(userVault)), 0);
        assertEq(stakeManager.totalSupplyBalance(), 0);
    }
}

contract ExecuteEpochTest is StakeManagerTest {
    function setUp() public override {
        StakeManagerTest.setUp();
    }

    //currentEpoch can only increase if time stakeManager.epochEnd().
    function test_ExecuteEpochShouldNotIncreaseEpochBeforeEnd() public {
        assertEq(stakeManager.currentEpoch(), 0);

        vm.warp(stakeManager.epochEnd() - 1);
        stakeManager.executeEpoch();
        assertEq(stakeManager.currentEpoch(), 0);
    }

    function test_ExecuteEpochShouldNotIncreaseEpochInMigration() public {
        assertEq(stakeManager.currentEpoch(), 0);

        assertEq(address(stakeManager.migration()), address(0));
        vm.prank(deployer);
        stakeManager.startMigration(migrationStakeManager);
        assertEq(address(stakeManager.migration()), address(migrationStakeManager));

        vm.warp(stakeManager.epochEnd());
        vm.expectRevert(StakeManager.StakeManager__PendingMigration.selector);
        stakeManager.executeEpoch();
        assertEq(stakeManager.currentEpoch(), 0);
    }

    //currentEpoch can only increase.
    function test_ExecuteEpochShouldIncreaseEpoch() public {
        assertEq(stakeManager.currentEpoch(), 0);

        vm.warp(stakeManager.epochEnd());
        stakeManager.executeEpoch();
        assertEq(stakeManager.currentEpoch(), 1);
    }

    //invariant: stakeManager balanceOf stakeToken > pendingReward
    function test_ExecuteEpochShouldIncreasePendingReward() public {
        assertEq(stakeManager.pendingReward(), 0);
        assertEq(stakeManager.epochReward(), 0);
        deal(stakeToken, address(stakeManager), 1);
        assertEq(stakeManager.pendingReward(), 0);
        assertEq(stakeManager.epochReward(), 1);
        vm.warp(stakeManager.epochEnd());
        stakeManager.executeEpoch();
        assertEq(stakeManager.pendingReward(), 1);
        assertEq(stakeManager.epochReward(), 0);
    }
}
