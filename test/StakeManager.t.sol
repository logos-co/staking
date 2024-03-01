// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import { Test, console } from "forge-std/Test.sol";
import { Deploy } from "../script/Deploy.s.sol";
import { DeployMigrationStakeManager } from "../script/DeployMigrationStakeManager.s.sol";
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

    function _createStakingAccount(address owner, uint256 amount) internal returns (StakeVault userVault) {
        return _createStakingAccount(owner, amount, 0, amount);
    }

    function _createStakingAccount(
        address owner,
        uint256 amount,
        uint256 lockTime
    )
        internal
        returns (StakeVault userVault)
    {
        return _createStakingAccount(owner, amount, lockTime, amount);
    }

    function _createStakingAccount(
        address owner,
        uint256 amount,
        uint256 lockTime,
        uint256 mintAmount
    )
        internal
        returns (StakeVault userVault)
    {
        deal(stakeToken, owner, mintAmount);
        userVault = _createTestVault(owner);
        vm.startPrank(owner);
        ERC20(stakeToken).approve(address(userVault), mintAmount);
        userVault.stake(amount, lockTime);
        vm.stopPrank();
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
        vm.expectRevert(StakeManager.StakeManager__InvalidLockTime.selector);
        userVault.stake(100, lockTime);

        lockTime = stakeManager.MAX_LOCKUP_PERIOD() + 1;
        vm.expectRevert(StakeManager.StakeManager__InvalidLockTime.selector);
        userVault.stake(100, lockTime);
    }

    function test_StakeWithoutLockUpTimeMintsMultiplierPoints() public {
        uint256 stakeAmount = 100;
        StakeVault userVault = _createStakingAccount(testUser, stakeAmount, 0, stakeAmount * 10);

        (,, uint256 currentMP,,,,) = stakeManager.accounts(address(userVault));
        assertEq(stakeManager.totalSupplyMP(), stakeAmount, "total multiplier point supply");
        assertEq(currentMP, stakeAmount, "user multiplier points");

        vm.prank(testUser);
        userVault.unstake(stakeAmount);

        (,,, currentMP,,,) = stakeManager.accounts(address(userVault));
        assertEq(stakeManager.totalSupplyMP(), 0, "totalSupplyMP burned after unstaking");
        assertEq(currentMP, 0, "userMP burned after unstaking");
    }

    function test_restakeJustStake() public {
        uint256 stakeAmount = 100;
        uint256 stakeAmount2 = 50;
        uint256 mintAmount = stakeAmount * 10;
        StakeVault userVault = _createStakingAccount(testUser, stakeAmount, 0, mintAmount);
        StakeVault userVault2 =
            _createStakingAccount(testUser2, stakeAmount, stakeManager.MIN_LOCKUP_PERIOD(), mintAmount);

        vm.prank(testUser);
        userVault.stake(stakeAmount2, 0);
        vm.prank(testUser2);
        userVault2.stake(stakeAmount2, 0);

        (, uint256 balance,, uint256 currentMP,,,) = stakeManager.accounts(address(userVault));
        assertEq(balance, stakeAmount + stakeAmount2, "account balance");
        assertEq(currentMP, stakeAmount + stakeAmount2, "account MP");
        (, balance,, currentMP,,,) = stakeManager.accounts(address(userVault2));
        assertEq(balance, stakeAmount + stakeAmount2, "account 2 balance");
        assertGt(currentMP, stakeAmount + stakeAmount2, "account 2 MP");

        vm.warp(stakeManager.epochEnd());

        vm.prank(testUser);
        userVault.stake(stakeAmount2, 0);
        vm.prank(testUser2);
        userVault2.stake(stakeAmount2, 0);

        (, balance,, currentMP,,,) = stakeManager.accounts(address(userVault));
        assertEq(balance, stakeAmount + stakeAmount2 + stakeAmount2, "account balance 2");
        assertGt(currentMP, stakeAmount + stakeAmount2 + stakeAmount2, "account MP 2");
        (, balance,, currentMP,,,) = stakeManager.accounts(address(userVault2));
        assertEq(balance, stakeAmount + stakeAmount2 + stakeAmount2, "account 2 balance 2");
        assertGt(currentMP, stakeAmount + stakeAmount2 + stakeAmount2, "account 2 MP 2");
    }

    function test_restakeJustLock() public {
        uint256 lockToIncrease = stakeManager.MIN_LOCKUP_PERIOD();
        uint256 stakeAmount = 100;
        uint256 stakeAmount2 = 50;
        uint256 mintAmount = stakeAmount * 10;
        StakeVault userVault = _createStakingAccount(testUser, stakeAmount, 0, mintAmount);
        StakeVault userVault2 = _createStakingAccount(testUser2, stakeAmount, lockToIncrease, mintAmount);
        vm.prank(testUser);
        userVault.stake(0, lockToIncrease);
        vm.prank(testUser2);
        userVault2.stake(0, lockToIncrease);

        (, uint256 balance,, uint256 currentMP,,,) = stakeManager.accounts(address(userVault));
        assertEq(balance, stakeAmount, "account balance");
        assertGt(currentMP, stakeAmount, "account MP");
        (, balance,, currentMP,,,) = stakeManager.accounts(address(userVault2));
        assertEq(balance, stakeAmount, "account 2 balance");
        assertGt(currentMP, stakeAmount, "account 2 MP");

        vm.warp(stakeManager.epochEnd());

        vm.prank(testUser);
        userVault.stake(0, lockToIncrease);
        vm.prank(testUser2);
        userVault2.stake(0, lockToIncrease);

        (, balance,, currentMP,,,) = stakeManager.accounts(address(userVault));
        assertEq(balance, stakeAmount, "account balance 2");
        assertGt(currentMP, stakeAmount, "account MP 2");
        (, balance,, currentMP,,,) = stakeManager.accounts(address(userVault2));
        assertEq(balance, stakeAmount, "account 2 balance 2");
        assertGt(currentMP, stakeAmount, "account 2 MP 2");
    }

    function test_restakeStakeAndLock() public {
        uint256 lockToIncrease = stakeManager.MIN_LOCKUP_PERIOD();
        uint256 stakeAmount = 100;
        uint256 stakeAmount2 = 50;
        uint256 mintAmount = stakeAmount * 10;
        StakeVault userVault = _createStakingAccount(testUser, stakeAmount, 0, mintAmount);
        StakeVault userVault2 = _createStakingAccount(testUser2, stakeAmount, lockToIncrease, mintAmount);

        vm.prank(testUser);
        userVault.stake(stakeAmount2, lockToIncrease);
        vm.prank(testUser2);
        userVault2.stake(stakeAmount2, lockToIncrease);

        (, uint256 balance,, uint256 currentMP,,,) = stakeManager.accounts(address(userVault));
        assertEq(balance, stakeAmount + stakeAmount2, "account balance");
        assertGt(currentMP, stakeAmount + stakeAmount2, "account MP");
        (, balance,, currentMP,,,) = stakeManager.accounts(address(userVault2));
        assertEq(balance, stakeAmount + stakeAmount2, "account 2 balance");
        assertGt(currentMP, stakeAmount + stakeAmount2, "account 2 MP");

        vm.warp(stakeManager.epochEnd());

        vm.prank(testUser);
        userVault.stake(stakeAmount2, lockToIncrease);
        vm.prank(testUser2);
        userVault2.stake(stakeAmount2, lockToIncrease);

        (, balance,, currentMP,,,) = stakeManager.accounts(address(userVault));
        assertEq(balance, stakeAmount + stakeAmount2 + stakeAmount2, "account balance 2");
        assertGt(currentMP, stakeAmount + stakeAmount2 + stakeAmount2, "account MP 2");
        (, balance,, currentMP,,,) = stakeManager.accounts(address(userVault2));
        assertEq(balance, stakeAmount + stakeAmount2 + stakeAmount2, "account 2 balance 2");
        assertGt(currentMP, stakeAmount + stakeAmount2 + stakeAmount2, "account 2 MP 2");
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
        uint256 lockTime = stakeManager.MIN_LOCKUP_PERIOD();
        uint256 stakeAmount = 100;
        uint256 mintAmount = stakeAmount * 10;
        StakeVault userVault = _createStakingAccount(testUser, stakeAmount, lockTime, mintAmount);

        vm.prank(testUser);
        vm.expectRevert(StakeManager.StakeManager__FundsLocked.selector);
        userVault.unstake(1);

        vm.prank(testUser);
        vm.expectRevert(StakeManager.StakeManager__FundsLocked.selector);
        userVault.unstake(stakeAmount);
    }

    function test_UnstakeShouldReturnFund_NoLockUp() public {
        uint256 lockTime = 0;
        uint256 stakeAmount = 100;
        uint256 mintAmount = stakeAmount * 10;
        StakeVault userVault = _createStakingAccount(testUser, stakeAmount, lockTime, mintAmount);
        assertEq(ERC20(stakeToken).balanceOf(testUser), 900);

        vm.prank(testUser);
        userVault.unstake(100);

        assertEq(stakeManager.totalSupplyBalance(), 0);
        assertEq(ERC20(stakeToken).balanceOf(address(userVault)), 0);
        assertEq(ERC20(stakeToken).balanceOf(testUser), 1000);
    }

    function test_UnstakeShouldReturnFund_WithLockUp() public {
        uint256 lockTime = stakeManager.MIN_LOCKUP_PERIOD();
        uint256 stakeAmount = 100;
        uint256 mintAmount = stakeAmount * 10;
        StakeVault userVault = _createStakingAccount(testUser, stakeAmount, lockTime, mintAmount);
        assertEq(ERC20(stakeToken).balanceOf(testUser), 900);

        vm.warp(block.timestamp + lockTime + 1);

        vm.prank(testUser);
        userVault.unstake(100);

        assertEq(stakeManager.totalSupplyBalance(), 0);
        assertEq(ERC20(stakeToken).balanceOf(address(userVault)), 0);
        assertEq(ERC20(stakeToken).balanceOf(testUser), 1000);
    }

    function test_UnstakeShouldBurnMultiplierPoints() public {
        uint256 percentToBurn = 90;
        uint256 stakeAmount = 100;
        StakeVault userVault = _createStakingAccount(testUser, stakeAmount);

        vm.startPrank(testUser);

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

        assertEq(balanceAfter, balanceBefore - (balanceBefore * percentToBurn / 100));
        assertEq(initialMPAfter, initialMPBefore - (initialMPBefore * percentToBurn / 100));
        assertEq(currentMPAfter, currentMPBefore - (currentMPBefore * percentToBurn / 100));
        assertEq(totalSupplyMPAfter, totalSupplyMPBefore - (currentMPBefore * percentToBurn / 100));
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
        vm.expectRevert(StakeManager.StakeManager__InvalidLockTime.selector);
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
        uint256 lockTime = 0;
        uint256 stakeAmount = 100;
        uint256 mintAmount = stakeAmount * 10;
        StakeVault userVault = _createStakingAccount(testUser, stakeAmount, lockTime, mintAmount);
        vm.startPrank(testUser);

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
        uint256 lockTime = 0;
        uint256 stakeAmount = 100;
        uint256 mintAmount = stakeAmount * 10;
        StakeVault userVault = _createStakingAccount(testUser, stakeAmount, lockTime, mintAmount);
        vm.startPrank(testUser);

        vm.expectRevert(StakeManager.StakeManager__NoPendingMigration.selector);
        userVault.acceptMigration();
        vm.stopPrank();
    }

    function increaseEpoch(uint256 epochNumber) internal { }
}

contract MigrationInitializeTest is StakeManagerTest {
    function setUp() public override {
        StakeManagerTest.setUp();
    }

    function test_RevertWhen_MigrationPending() public {
        // first, create 2nd and 3rd generation stake manager
        vm.startPrank(deployer);
        StakeManager secondStakeManager = new StakeManager(stakeToken, address(stakeManager));
        StakeManager thirdStakeManager = new StakeManager(stakeToken, address(secondStakeManager));

        // first, ensure `secondStakeManager` is in migration mode itself
        secondStakeManager.startMigration(thirdStakeManager);
        vm.stopPrank();

        uint256 currentEpoch = stakeManager.currentEpoch();
        uint256 totalMP = stakeManager.totalSupplyMP();
        uint256 totalBalance = stakeManager.totalSupplyBalance();

        // `stakeManager` calling `migrationInitialize` while the new stake manager is
        // in migration itself, should revert
        vm.prank(address(stakeManager));
        vm.expectRevert(StakeManager.StakeManager__PendingMigration.selector);
        secondStakeManager.migrationInitialize(currentEpoch, totalMP, totalBalance, 0);
    }
}

contract ExecuteAccountTest is StakeManagerTest {
    StakeVault[] private userVaults;

    function setUp() public override {
        StakeManagerTest.setUp();
    }

    function test_RevertWhen_InvalidLimitEpoch() public {
        uint256 lockTime = stakeManager.MIN_LOCKUP_PERIOD();
        uint256 stakeAmount = 100;
        uint256 mintAmount = stakeAmount * 10;
        StakeVault userVault = _createStakingAccount(testUser, stakeAmount, lockTime, mintAmount);
        vm.startPrank(testUser);

        uint256 currentEpoch = stakeManager.currentEpoch();

        vm.expectRevert(StakeManager.StakeManager__InvalidLimitEpoch.selector);
        stakeManager.executeAccount(address(userVault), currentEpoch + 1);
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

    function test_ShouldNotMintMoreThanCap() public { }

    function internal_logAccount(address vault) internal {
        (
            address rewardAddress,
            uint256 balance,
            uint256 initialMP,
            uint256 currentMP,
            uint256 lastMint,
            uint256 lockUntil,
            uint256 epoch
        ) = stakeManager.accounts(vault);
        console.log("===============");
        console.log("rewardAddress :", rewardAddress);
        console.log("##### balance :", balance);
        console.log("### initialMP :", initialMP);
        console.log("### currentMP :", currentMP);
        console.log("#### lastMint :", lastMint);
        console.log("### lockUntil :", lockUntil);
        console.log("####### epoch :", epoch);
        console.log("===============");
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
        uint256 lockTime = 0;
        uint256 stakeAmount = 100;
        uint256 mintAmount = stakeAmount * 10;

        StakeVault userVault = _createStakingAccount(testUser, stakeAmount, lockTime, mintAmount);
        StakeVault user2Vault = _createStakingAccount(testUser2, stakeAmount, lockTime, mintAmount);

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
        uint256 lockTime = stakeManager.MIN_LOCKUP_PERIOD();
        uint256 stakeAmount = 100;
        uint256 mintAmount = stakeAmount * 10;
        StakeVault userVault = _createStakingAccount(testUser, stakeAmount, lockTime, mintAmount);
        vm.startPrank(testUser);

        // unstaking should fail as lockup time isn't over yet
        vm.expectRevert(StakeManager.StakeManager__FundsLocked.selector);
        userVault.unstake(100);

        // fast forward 12 weeks
        skip(lockTime + 1);

        userVault.unstake(100);
        assertEq(ERC20(stakeToken).balanceOf(address(userVault)), 0);
        assertEq(stakeManager.totalSupplyBalance(), 0);
    }
}

contract DeployMigrationStakeManagerTest is StakeManagerTest {
    StakeManager internal newStakeManager;

    function setUp() public virtual override {
        super.setUp();
        DeployMigrationStakeManager deployment = new DeployMigrationStakeManager(address(stakeManager), stakeToken);
        newStakeManager = deployment.run();
    }

    function testNewDeployment() public {
        assertEq(newStakeManager.owner(), deployer);
        assertEq(newStakeManager.currentEpoch(), 0);
        assertEq(newStakeManager.pendingReward(), 0);
        assertEq(newStakeManager.totalSupplyMP(), 0);
        assertEq(newStakeManager.totalSupplyBalance(), 0);
        assertEq(address(newStakeManager.stakedToken()), stakeToken);
        assertEq(address(newStakeManager.oldManager()), address(stakeManager));
        assertEq(newStakeManager.totalSupply(), 0);
    }
}

contract ExecuteEpochTest is DeployMigrationStakeManagerTest {
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
        stakeManager.startMigration(newStakeManager);
        assertEq(address(stakeManager.migration()), address(newStakeManager));

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
