// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import { Test, console } from "forge-std/Test.sol";
import { Deploy } from "../script/Deploy.s.sol";
import { DeploymentConfig } from "../script/DeploymentConfig.s.sol";
import { StakeManager } from "../contracts/StakeManager.sol";
import { StakeVault } from "../contracts/StakeVault.sol";
import { VaultFactory } from "../contracts/VaultFactory.sol";

contract StakeManagerTest is Test {
    DeploymentConfig internal deploymentConfig;
    StakeManager internal stakeManager;
    VaultFactory internal vaultFactory;

    address internal stakeToken;
    address internal deployer;
    address internal testUser = makeAddr("testUser");
    address internal testUser2 = makeAddr("testUser2");

    function setUp() public virtual {
        Deploy deployment = new Deploy();
        (vaultFactory, stakeManager, deploymentConfig) = deployment.run();
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

    function test_UnstakeShouldReturnFunds() public {
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

    function test_UnstakeShouldBurnMultiplierPoints() public {
        uint256 stakeAmount = 1000;
        uint256 percentToBurn = 90;
        deal(stakeToken, testUser, stakeAmount);
        StakeVault userVault = _createTestVault(testUser);

        vm.startPrank(testUser);
        ERC20(stakeToken).approve(address(userVault), stakeAmount);

        userVault.stake(stakeAmount, 0);

        assertEq(stakeManager.totalSupplyMP(), stakeAmount);
        for (uint256 i = 0; i < 53; i++) {
            vm.warp(stakeManager.epochEnd());
            stakeManager.executeAccount(address(userVault), i + 1);
        }
        (, uint256 balanceBefore, uint256 initialMPBefore, uint256 currentMPBefore,,,) =
            stakeManager.accounts(address(userVault));
        uint256 totalSupplyMPBefore = stakeManager.totalSupplyMP();
        uint256 unstakeAmount = stakeAmount * percentToBurn / 100;
        console.log("unstake", unstakeAmount);

        assertEq(ERC20(stakeToken).balanceOf(testUser), 0);
        userVault.unstake(unstakeAmount);
        vm.stopPrank();
        (, uint256 balanceAfter, uint256 initialMPAfter, uint256 currentMPAfter,,,) =
            stakeManager.accounts(address(userVault));

        uint256 totalSupplyMPAfter = stakeManager.totalSupplyMP();
        console.log("totalSupplyMPBefore", totalSupplyMPBefore);
        console.log("totalSupplyMPAfter", totalSupplyMPAfter);
        console.log("balanceBefore", balanceBefore);
        console.log("balanceAfter", balanceAfter);
        console.log("initialMPBefore", initialMPBefore);
        console.log("initialMPAfter", initialMPAfter);
        console.log("currentMPBefore", currentMPBefore);
        console.log("currentMPAfter", currentMPAfter);

        uint256 reducedInitialMp = (initialMPBefore * percentToBurn / 100);
        uint256 reducedCurrentMp = (currentMPBefore * percentToBurn / 100);
        assertEq(balanceAfter, balanceBefore - (balanceBefore * percentToBurn / 100));
        assertEq(initialMPAfter, initialMPBefore - reducedInitialMp);
        assertEq(currentMPAfter, currentMPBefore - reducedCurrentMp);
        assertEq(totalSupplyMPAfter, totalSupplyMPBefore - reducedCurrentMp);
        assertEq(ERC20(stakeToken).balanceOf(testUser), unstakeAmount);
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
}

contract ExecuteAccountTest is StakeManagerTest {
    StakeVault[] private userVaults;

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

    function _createStakingAccount(
        address owner,
        uint256 amount,
        uint256 lockTime
    )
        internal
        returns (StakeVault userVault)
    {
        deal(stakeToken, owner, amount);
        userVault = _createTestVault(owner);
        vm.startPrank(owner);
        ERC20(stakeToken).approve(address(userVault), amount);
        userVault.stake(amount, lockTime);
        vm.stopPrank();
    }

    function test_ExecuteAccountMintMP() public {
        uint256 stakeAmount = 10_000_000;
        deal(stakeToken, testUser, stakeAmount);

        userVaults.push(_createStakingAccount(makeAddr("testUser"), stakeAmount, 0));
        userVaults.push(_createStakingAccount(makeAddr("testUser2"), stakeAmount, 0));
        userVaults.push(_createStakingAccount(makeAddr("testUser3"), stakeAmount, 0));

        console.log("######### NOW", block.timestamp);
        console.log("# START EPOCH", stakeManager.currentEpoch());
        console.log("# PND_REWARDS", stakeManager.pendingReward());

        for (uint256 i = 0; i < 3; i++) {
            deal(stakeToken, address(stakeManager), 100 ether);
            vm.warp(stakeManager.epochEnd());
            console.log("######### NOW", block.timestamp);
            stakeManager.executeEpoch();
            console.log("##### NEW EPOCH", stakeManager.currentEpoch());
            console.log("# PND_REWARDS", stakeManager.pendingReward());

            for (uint256 j = 0; j < userVaults.length; j++) {
                (address rewardAddress,,, uint256 currentMPBefore, uint256 lastMintBefore,, uint256 epochBefore) =
                    stakeManager.accounts(address(userVaults[j]));
                uint256 rewardsBefore = ERC20(stakeToken).balanceOf(rewardAddress);
                console.log("-Vault number", j);
                console.log("--=====BEFORE=====");
                console.log("---### currentMP :", currentMPBefore);
                console.log("---#### lastMint :", lastMintBefore);
                console.log("---## user_epoch :", epochBefore);
                console.log("---##### rewards :", rewardsBefore);
                console.log("--=====AFTER======");
                stakeManager.executeAccount(address(userVaults[j]), epochBefore + 1);
                (,,, uint256 currentMP, uint256 lastMint,, uint256 epoch) =
                    stakeManager.accounts(address(userVaults[j]));
                uint256 rewards = ERC20(stakeToken).balanceOf(rewardAddress);
                console.log("---### deltaTime :", lastMint - lastMintBefore);
                console.log("---### currentMP :", currentMP);
                console.log("---#### lastMint :", lastMint);
                console.log("---## user_epoch :", epoch);
                console.log("---##### rewards :", rewards);
                console.log("--=======#=======");
                console.log("--# TOTAL_SUPPLY", stakeManager.totalSupply());
                console.log("--# PND_REWARDS", stakeManager.pendingReward());
                assertEq(lastMint, lastMintBefore + stakeManager.EPOCH_SIZE(), "must increaase lastMint");
                assertEq(epoch, epochBefore + 1, "must increase epoch");
                assertGt(currentMP, currentMPBefore, "must increase MPs");
                assertGt(rewards, rewardsBefore, "must increase rewards");
                lastMintBefore = lastMint;
                epochBefore = epoch;
                currentMPBefore = currentMP;
            }
        }
    }
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
