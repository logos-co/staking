// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import { Test, console } from "forge-std/Test.sol";
import { Deploy } from "../script/Deploy.s.sol";
import { DeployMigrationStakeManager } from "../script/DeployMigrationStakeManager.s.sol";
import { DeploymentConfig } from "../script/DeploymentConfig.s.sol";
import { TrustedCodehashAccess, StakeManager, ExpiredStakeStorage } from "../contracts/StakeManager.sol";
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
        assertEq(address(stakeManager.previousManager()), address(0));
        assertEq(stakeManager.totalSupply(), 0);
    }

    function _createTestVault(address owner) internal returns (StakeVault vault) {
        vm.prank(owner);
        vault = vaultFactory.createVault();

        if (!stakeManager.isTrustedCodehash(address(vault).codehash)) {
            vm.prank(deployer);
            stakeManager.setTrustedCodehash(address(vault).codehash, true);
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
    function test_RevertWhen_SenderIsNotVault() public {
        vm.expectRevert(TrustedCodehashAccess.TrustedCodehashAccess__UnauthorizedCodehash.selector);
        stakeManager.stake(100, 1);
    }

    function test_StakeWithLockBonusMP() public {
        uint256 stakeAmount = 10_000;
        uint256 lockTime = stakeManager.MIN_LOCKUP_PERIOD();

        StakeVault userVault = _createStakingAccount(testUser, stakeAmount, 0, stakeAmount);

        (, uint256 balance, uint256 bonusMP, uint256 totalMP,,,,) = stakeManager.accounts(address(userVault));
        assertEq(balance, stakeAmount, "balance of user vault should be equal to stake amount after stake");
        assertEq(bonusMP, stakeAmount, "bonusMP of user vault should be equal to stake amount after stake if no lock");
        assertEq(totalMP, bonusMP, "totalMP of user vault should be equal to bonusMP after stake if no epochs passed");

        vm.prank(testUser);
        userVault.lock(lockTime);
        uint256 estimatedBonusMp = stakeAmount + stakeManager.calculateMPToMint(stakeAmount, lockTime);

        (, balance, bonusMP, totalMP,,,,) = stakeManager.accounts(address(userVault));
        assertEq(balance, stakeAmount, "balance of user vault should be equal to stake amount after lock");
        assertEq(bonusMP, estimatedBonusMp, "bonusMP of user vault should be equal to estimated bonusMP after lock");
        assertEq(totalMP, bonusMP, "totalMP of user vault should be equal to bonusMP after lock if no epochs passed");

        StakeVault userVault2 = _createStakingAccount(testUser, stakeAmount, lockTime, stakeAmount);

        (, balance, bonusMP, totalMP,,,,) = stakeManager.accounts(address(userVault2));
        assertEq(balance, stakeAmount, "balance of user vault should be equal to stake amount after stake locked");
        assertEq(
            bonusMP, estimatedBonusMp, "bonusMP of user vault should be equal to estimated bonusMP after stake locked"
        );
        assertEq(
            totalMP, bonusMP, "totalMP of user vault should be equal to bonusMP after stake locked if no epochs passed"
        );
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

    function test_RevertWhen_StakeIsTooLow() public {
        StakeVault userVault = _createTestVault(testUser);
        vm.startPrank(testUser);
        vm.expectRevert(StakeManager.StakeManager__StakeIsTooLow.selector);
        userVault.stake(0, 0);
    }

    function test_RevertWhen_Restake() public {
        // ensure user has funds
        deal(stakeToken, testUser, 1000);
        StakeVault userVault = _createTestVault(testUser);
        vm.startPrank(testUser);
        ERC20(stakeToken).approve(address(userVault), 1000);

        userVault.stake(100, 0);
        vm.expectRevert(StakeManager.StakeManager__AlreadyStaked.selector);
        userVault.stake(100, 0);
    }

    function test_RevertWhen_RestakeWithLock() public {
        uint256 lockToIncrease = stakeManager.MIN_LOCKUP_PERIOD();
        // ensure user has funds
        deal(stakeToken, testUser, 1000);
        StakeVault userVault = _createTestVault(testUser);
        vm.startPrank(testUser);
        ERC20(stakeToken).approve(address(userVault), 1000);

        userVault.stake(100, lockToIncrease);
        vm.expectRevert(StakeManager.StakeManager__AlreadyStaked.selector);
        userVault.stake(100, 0);
    }

    function test_StakeWithoutLockUpTimeMintsMultiplierPoints() public {
        uint256 stakeAmount = 54;
        StakeVault userVault = _createStakingAccount(testUser, stakeAmount, 0, stakeAmount);

        (,, uint256 totalMP,,,,,) = stakeManager.accounts(address(userVault));
        assertEq(stakeManager.totalSupplyMP(), stakeAmount, "total multiplier point supply");
        assertEq(totalMP, stakeAmount, "user multiplier points");

        vm.prank(testUser);
        userVault.unstake(stakeAmount);

        (,,, totalMP,,,,) = stakeManager.accounts(address(userVault));
        assertEq(stakeManager.totalSupplyMP(), 0, "totalSupplyMP burned after unstaking");
        assertEq(totalMP, 0, "userMP burned after unstaking");
    }
}

contract UnstakeTest is StakeManagerTest {
    function test_RevertWhen_SenderIsNotVault() public {
        vm.expectRevert(TrustedCodehashAccess.TrustedCodehashAccess__UnauthorizedCodehash.selector);
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
        (, uint256 balanceBefore, uint256 bonusMPBefore, uint256 totalMPBefore,,,,) =
            stakeManager.accounts(address(userVault));
        uint256 totalSupplyMPBefore = stakeManager.totalSupplyMP();
        uint256 unstakeAmount = stakeAmount * percentToBurn / 100;
        console.log("unstake", unstakeAmount);

        assertEq(ERC20(stakeToken).balanceOf(testUser), 0);
        userVault.unstake(unstakeAmount);
        (, uint256 balanceAfter, uint256 bonusMPAfter, uint256 totalMPAfter,,,,) =
            stakeManager.accounts(address(userVault));

        uint256 totalSupplyMPAfter = stakeManager.totalSupplyMP();
        console.log("totalSupplyMPBefore", totalSupplyMPBefore);
        console.log("totalSupplyMPAfter", totalSupplyMPAfter);
        console.log("balanceBefore", balanceBefore);
        console.log("balanceAfter", balanceAfter);
        console.log("bonusMPBefore", bonusMPBefore);
        console.log("bonusMPAfter", bonusMPAfter);
        console.log("totalMPBefore", totalMPBefore);
        console.log("totalMPAfter", totalMPAfter);

        assertEq(balanceAfter, balanceBefore - (balanceBefore * percentToBurn / 100));
        assertEq(bonusMPAfter, bonusMPBefore - (bonusMPBefore * percentToBurn / 100));
        assertEq(totalMPAfter, totalMPBefore - (totalMPBefore * percentToBurn / 100));
        assertEq(totalSupplyMPAfter, totalSupplyMPBefore - (totalMPBefore * percentToBurn / 100));
        assertEq(ERC20(stakeToken).balanceOf(testUser), unstakeAmount);
    }

    function test_RevertWhen_AmountMoreThanBalance() public {
        uint256 stakeAmount = 1000;
        StakeVault userVault = _createStakingAccount(testUser, stakeAmount);
        vm.startPrank(testUser);
        vm.expectRevert(StakeManager.StakeManager__InsufficientFunds.selector);
        userVault.unstake(stakeAmount + 1);
    }
}

contract LockTest is StakeManagerTest {
    function test_RevertWhen_SenderIsNotVault() public {
        vm.expectRevert(TrustedCodehashAccess.TrustedCodehashAccess__UnauthorizedCodehash.selector);
        stakeManager.lock(100);
    }

    function test_NewLockupPeriod() public {
        StakeVault userVault = _createStakingAccount(testUser, 1000);

        uint256 lockTime = stakeManager.MAX_LOCKUP_PERIOD();
        vm.startPrank(testUser);
        userVault.lock(lockTime);

        (, uint256 balance, uint256 bonusMP, uint256 totalMP,,,,) = stakeManager.accounts(address(userVault));

        console.log("balance", balance);
        console.log("bonusMP", bonusMP);
        console.log("totalMP", totalMP);
    }

    function test_RevertWhen_InvalidNewLockupPeriod() public {
        StakeVault userVault = _createStakingAccount(testUser, 1000);

        uint256 lockTime = stakeManager.MAX_LOCKUP_PERIOD() + 1;
        vm.startPrank(testUser);
        vm.expectRevert(StakeManager.StakeManager__InvalidLockTime.selector);
        userVault.lock(lockTime);
    }

    function test_UpdateLockupPeriod() public {
        uint256 minLockup = stakeManager.MIN_LOCKUP_PERIOD();
        StakeVault userVault = _createStakingAccount(testUser, 1000, minLockup, 1000);

        vm.warp(block.timestamp + stakeManager.MIN_LOCKUP_PERIOD() - 1);
        stakeManager.executeAccount(address(userVault), 1);
        (, uint256 balance, uint256 bonusMP, uint256 totalMP,, uint256 lockUntil,,) =
            stakeManager.accounts(address(userVault));

        vm.startPrank(testUser);
        userVault.lock(minLockup - 1);
        (, balance, bonusMP, totalMP,, lockUntil,,) = stakeManager.accounts(address(userVault));

        assertEq(lockUntil, block.timestamp + minLockup);

        vm.warp(block.timestamp + stakeManager.MIN_LOCKUP_PERIOD());
        userVault.lock(minLockup);
    }

    function test_RevertWhen_InvalidUpdateLockupPeriod() public {
        uint256 minLockup = stakeManager.MIN_LOCKUP_PERIOD();
        StakeVault userVault = _createStakingAccount(testUser, 1000, minLockup, 1000);

        vm.warp(block.timestamp + stakeManager.MIN_LOCKUP_PERIOD());
        stakeManager.executeAccount(address(userVault), 1);

        (,,,,, uint256 lockUntil,,) = stakeManager.accounts(address(userVault));
        console.log(lockUntil);
        vm.startPrank(testUser);
        vm.expectRevert(StakeManager.StakeManager__InvalidLockTime.selector);
        userVault.lock(minLockup - 1);
    }

    function test_ShouldIncreaseBonusMP() public {
        uint256 stakeAmount = 100;
        uint256 lockTime = stakeManager.MAX_LOCKUP_PERIOD();
        StakeVault userVault = _createStakingAccount(testUser, stakeAmount);
        (, uint256 balance, uint256 bonusMP, uint256 totalMP,,,,) = stakeManager.accounts(address(userVault));
        uint256 totalSupplyMPBefore = stakeManager.totalSupplyMP();

        vm.startPrank(testUser);
        userVault.lock(lockTime);

        //solhint-disable-next-line max-line-length
        (, uint256 newBalance, uint256 newBonusMP, uint256 newCurrentMP,,,,) = stakeManager.accounts(address(userVault));
        uint256 totalSupplyMPAfter = stakeManager.totalSupplyMP();
        assertGt(totalSupplyMPAfter, totalSupplyMPBefore, "totalSupplyMP");
        assertGt(newBonusMP, bonusMP, "bonusMP");
        assertGt(newCurrentMP, totalMP, "totalMP");
        assertEq(newBalance, balance, "balance");
    }
}

contract LeaveTest is StakeManagerTest {
    function test_RevertWhen_SenderIsNotVault() public {
        vm.expectRevert(TrustedCodehashAccess.TrustedCodehashAccess__UnauthorizedCodehash.selector);
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
    function test_RevertWhen_SenderIsNotVault() public {
        vm.expectRevert(TrustedCodehashAccess.TrustedCodehashAccess__UnauthorizedCodehash.selector);
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
        vm.stopPrank();

        // first, ensure `secondStakeManager` is in migration mode itself
        ExpiredStakeStorage db = stakeManager.expiredStakeStorage();
        vm.prank(address(stakeManager));
        db.transferOwnership(address(secondStakeManager));

        vm.prank(address(deployer));
        secondStakeManager.startMigration(thirdStakeManager);

        uint256 currentEpoch = stakeManager.currentEpoch();
        uint256 totalMP = stakeManager.totalSupplyMP();
        uint256 totalBalance = stakeManager.totalSupplyBalance();

        // `stakeManager` calling `migrationInitialize` while the new stake manager is
        // in migration itself, should revert
        vm.prank(address(stakeManager));
        vm.expectRevert(StakeManager.StakeManager__PendingMigration.selector);
        secondStakeManager.migrationInitialize(currentEpoch, totalMP, totalBalance, 0, 0, 0, 0);
    }
}

contract ExecuteAccountTest is StakeManagerTest {
    StakeVault[] private userVaults;

    function test_RevertWhen_InvalidLimitEpoch() public {
        uint256 lockTime = stakeManager.MIN_LOCKUP_PERIOD();
        uint256 stakeAmount = 100;
        uint256 mintAmount = stakeAmount * 10;
        StakeVault userVault = _createStakingAccount(testUser, stakeAmount, lockTime, mintAmount);
        vm.startPrank(testUser);

        uint256 currentEpoch = stakeManager.currentEpoch();

        vm.expectRevert(StakeManager.StakeManager__InvalidLimitEpoch.selector);
        stakeManager.executeEpoch(currentEpoch + 1);

        vm.expectRevert(StakeManager.StakeManager__InvalidLimitEpoch.selector);
        stakeManager.executeAccount(address(userVault), currentEpoch + 1);

        vm.warp(stakeManager.epochEnd() - 1);

        vm.expectRevert(StakeManager.StakeManager__InvalidLimitEpoch.selector);
        stakeManager.executeEpoch(currentEpoch + 1);

        vm.expectRevert(StakeManager.StakeManager__InvalidLimitEpoch.selector);
        stakeManager.executeAccount(address(userVault), currentEpoch + 1);

        vm.warp(stakeManager.epochEnd());

        stakeManager.executeAccount(address(userVault), currentEpoch + 1);
        stakeManager.executeEpoch(currentEpoch + 1);

        currentEpoch++;

        vm.expectRevert(StakeManager.StakeManager__InvalidLimitEpoch.selector);
        stakeManager.executeEpoch(currentEpoch + 1);

        vm.expectRevert(StakeManager.StakeManager__InvalidLimitEpoch.selector);
        stakeManager.executeAccount(address(userVault), currentEpoch + 1);

        vm.warp(stakeManager.epochEnd() + stakeManager.EPOCH_SIZE() - 1);

        vm.expectRevert(StakeManager.StakeManager__InvalidLimitEpoch.selector);
        stakeManager.executeEpoch(currentEpoch + 2);

        vm.expectRevert(StakeManager.StakeManager__InvalidLimitEpoch.selector);
        stakeManager.executeAccount(address(userVault), currentEpoch + 2);

        stakeManager.executeAccount(address(userVault), currentEpoch + 1);
        stakeManager.executeEpoch(currentEpoch + 1);

        currentEpoch++;

        vm.expectRevert(StakeManager.StakeManager__InvalidLimitEpoch.selector);
        stakeManager.executeEpoch(currentEpoch + 1);

        vm.expectRevert(StakeManager.StakeManager__InvalidLimitEpoch.selector);
        stakeManager.executeAccount(address(userVault), currentEpoch + 1);
    }

    //Stake, pass epoch, execute epoch, passEpoch, executeEpoch, executeAccount, verify amount of MPs, totalMPs, etc.
    function test_ExecuteAccountLimit() public {
        uint256 stakeAmount = 10_000_000;
        deal(stakeToken, testUser, stakeAmount);
        userVaults.push(_createStakingAccount(makeAddr("testUser"), stakeAmount, 0));

        (,,, uint256 totalMP, uint256 lastMint,, uint256 epoch,) = stakeManager.accounts(address(userVaults[0]));
        vm.warp(stakeManager.epochEnd());
        stakeManager.executeEpoch();
        vm.warp(stakeManager.epochEnd());

        //expected MP is, the starting totalMP + the calculatedMPToMint of user balance for one EPOCH_SIZE multiplied by
        // 2.
        uint256 expectedMP = totalMP + (stakeManager.calculateMPToMint(stakeAmount, stakeManager.EPOCH_SIZE()) * 2);
        stakeManager.executeAccount(address(userVaults[0]), stakeManager.currentEpoch() + 1);
        (,,, totalMP, lastMint,, epoch,) = stakeManager.accounts(address(userVaults[0]));

        assertEq(totalMP, expectedMP, "totalMP is not what the contract itself predicted");
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
                //solhint-disable-next-line max-line-length
                (address rewardAddress,,, uint256 totalMPBefore, uint256 lastMintBefore,, uint256 epochBefore,) =
                    stakeManager.accounts(address(userVaults[j]));
                uint256 rewardsBefore = ERC20(stakeToken).balanceOf(rewardAddress);
                console.log("-Vault number", j);
                console.log("--=====BEFORE=====");
                console.log("---### totalMP :", totalMPBefore);
                console.log("---#### lastMint :", lastMintBefore);
                console.log("---## user_epoch :", epochBefore);
                console.log("---##### rewards :", rewardsBefore);
                console.log("--=====AFTER======");
                stakeManager.executeAccount(address(userVaults[j]), epochBefore + 1);
                //solhint-disable-next-line max-line-length
                (,,, uint256 totalMP, uint256 lastMint,, uint256 epoch,) = stakeManager.accounts(address(userVaults[j]));
                uint256 rewards = ERC20(stakeToken).balanceOf(rewardAddress);
                console.log("---### deltaTime :", lastMint - lastMintBefore);
                console.log("---### totalMP :", totalMP);
                console.log("---#### lastMint :", lastMint);
                console.log("---## user_epoch :", epoch);
                console.log("---##### rewards :", rewards);
                console.log("--=======#=======");
                console.log("--# TOTAL_SUPPLY", stakeManager.totalSupply());
                console.log("--# PND_REWARDS", stakeManager.pendingReward());
                assertEq(lastMint, lastMintBefore + stakeManager.EPOCH_SIZE(), "must increaase lastMint");
                assertEq(epoch, epochBefore + 1, "must increase epoch");
                assertGt(totalMP, totalMPBefore, "must increase MPs");
                assertGt(rewards, rewardsBefore, "must increase rewards");
                lastMintBefore = lastMint;
                epochBefore = epoch;
                totalMPBefore = totalMP;
            }
        }
    }

    function test_ShouldNotMintMoreThanCap() public {
        uint256 stakeAmount = 10_000_000_000;

        uint256 epochsAmountToReachCap = stakeManager.calculateMPToMint(
            stakeAmount, stakeManager.MAX_BOOST() * stakeManager.YEAR()
        ) / stakeManager.calculateMPToMint(stakeAmount, stakeManager.EPOCH_SIZE());

        deal(stakeToken, testUser, stakeAmount);

        userVaults.push(_createStakingAccount(makeAddr("testUser"), stakeAmount, 0));

        vm.warp(stakeManager.epochEnd() - (stakeManager.EPOCH_SIZE() - 1));
        userVaults.push(_createStakingAccount(makeAddr("testUser2"), stakeAmount, 0));

        vm.warp(stakeManager.epochEnd() - (stakeManager.EPOCH_SIZE() - 2));
        userVaults.push(_createStakingAccount(makeAddr("testUser3"), stakeAmount, 0));

        vm.warp(stakeManager.epochEnd() - ((stakeManager.EPOCH_SIZE() / 4) * 3));
        userVaults.push(_createStakingAccount(makeAddr("testUser4"), stakeAmount, 0));

        vm.warp(stakeManager.epochEnd() - ((stakeManager.EPOCH_SIZE() / 4) * 2));
        userVaults.push(_createStakingAccount(makeAddr("testUser5"), stakeAmount, 0));

        vm.warp(stakeManager.epochEnd() - ((stakeManager.EPOCH_SIZE() / 4) * 1));
        userVaults.push(_createStakingAccount(makeAddr("testUser6"), stakeAmount, 0));

        vm.warp(stakeManager.epochEnd() - 2);
        userVaults.push(_createStakingAccount(makeAddr("testUser7"), stakeAmount, 0));

        vm.warp(stakeManager.epochEnd() - 1);
        userVaults.push(_createStakingAccount(makeAddr("testUser8"), stakeAmount, 0));

        for (uint256 i = 0; i <= epochsAmountToReachCap; i++) {
            deal(stakeToken, address(stakeManager), 100 ether);
            vm.warp(stakeManager.epochEnd());
            stakeManager.executeEpoch();
            for (uint256 j = 0; j < userVaults.length; j++) {
                (address rewardAddress,,, uint256 totalMPBefore, uint256 lastMintBefore,, uint256 epochBefore,) =
                    stakeManager.accounts(address(userVaults[j]));
                uint256 rewardsBefore = ERC20(stakeToken).balanceOf(rewardAddress);

                stakeManager.executeAccount(address(userVaults[j]), epochBefore + 1);
                //solhint-disable-next-line max-line-length
                (,,, uint256 totalMP, uint256 lastMint,, uint256 epoch,) = stakeManager.accounts(address(userVaults[j]));
                uint256 rewards = ERC20(stakeToken).balanceOf(rewardAddress);
                assertEq(epoch, epochBefore + 1, "must increase epoch");
                assertGt(totalMP, totalMPBefore, "must increase MPs");
                assertGt(rewards, rewardsBefore, "must increase rewards");
                lastMintBefore = lastMint;
                epochBefore = epoch;
                totalMPBefore = totalMP;
            }
        }

        for (uint256 i = 0; i < 100; i++) {
            deal(stakeToken, address(stakeManager), 100 ether);
            vm.warp(stakeManager.epochEnd());
            stakeManager.executeEpoch();
            for (uint256 j = 0; j < userVaults.length; j++) {
                (address rewardAddress,,, uint256 totalMPBefore, uint256 lastMintBefore,, uint256 epochBefore,) =
                    stakeManager.accounts(address(userVaults[j]));
                uint256 rewardsBefore = ERC20(stakeToken).balanceOf(rewardAddress);

                stakeManager.executeAccount(address(userVaults[j]), epochBefore + 1);
                //solhint-disable-next-line max-line-length
                (,,, uint256 totalMP, uint256 lastMint,, uint256 epoch,) = stakeManager.accounts(address(userVaults[j]));
                uint256 rewards = ERC20(stakeToken).balanceOf(rewardAddress);
                assertEq(lastMint, lastMintBefore + stakeManager.EPOCH_SIZE(), "must increaase lastMint");
                assertEq(epoch, epochBefore + 1, "must increase epoch");
                // MPs will still be minted in mpLimitEpoch + 1 when accounts
                // started staking at any point *inside* of an epoch, so we
                // only perform the assert below one epoch after *that*
                if (i > 0) {
                    assertEq(totalMP, totalMPBefore, "must NOT increase MPs");
                }
                assertGt(rewards, rewardsBefore, "must increase rewards");
                lastMintBefore = lastMint;
                epochBefore = epoch;
                totalMPBefore = totalMP;
            }
        }
    }
}

contract UserFlowsTest is StakeManagerTest {
    StakeVault[] private userVaults;

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

    function test_PendingMPToBeMintedCannotBeGreaterThanTotalSupplyMP(
        uint8 randomStakeMultiplier,
        uint128 randomStakeAddition
    )
        public
    {
        uint8 accountNum = 5;
        uint256 minimumPossibleStake = 53; //less than this the stake per epoch of the account would be 0
        uint256 baseStakeAmount =
            (minimumPossibleStake * (uint256(randomStakeMultiplier) + 1)) + uint256(randomStakeAddition);
        uint256 epochsAmountToReachCap = 0;
        for (uint256 i = 0; i <= accountNum; i++) {
            uint256 thisAccStake = baseStakeAmount + (i * (10 ^ i * baseStakeAmount)); //changes the amount of stake of
                // each account so we have mixed amounts of stake
            userVaults.push(
                _createStakingAccount(makeAddr(string(abi.encode(keccak256(abi.encode(accountNum))))), thisAccStake, 0)
            );
            uint256 thisAccReachCapIn = stakeManager.calculateMPToMint(
                thisAccStake, stakeManager.MAX_BOOST() * stakeManager.YEAR()
            ) / stakeManager.calculateMPToMint(thisAccStake, stakeManager.EPOCH_SIZE());
            if (thisAccReachCapIn > epochsAmountToReachCap) {
                epochsAmountToReachCap = thisAccReachCapIn; //uses the amount to reach cap from the account that takes
                    // longer to reach cap
            }
        }

        //tests up to epochs to reach MAX_BOOST + 10 epochs
        for (uint256 i = 0; i < epochsAmountToReachCap + 10; i++) {
            vm.warp(stakeManager.epochEnd());
            stakeManager.executeEpoch();
            uint256 pendingMPToBeMintedBefore = stakeManager.pendingMPToBeMinted();
            uint256 totalSupplyMP = stakeManager.totalSupplyMP();
            for (uint256 j = 0; j < userVaults.length; j++) {
                (,,, uint256 totalMPBefore, uint256 lastMintBefore,, uint256 epochBefore,) =
                    stakeManager.accounts(address(userVaults[j]));

                stakeManager.executeAccount(address(userVaults[j]), epochBefore + 1);
            }
            uint256 pendingMPToBeMintedAfter = stakeManager.pendingMPToBeMinted();

            assertEq(pendingMPToBeMintedBefore + totalSupplyMP, stakeManager.totalSupplyMP());
            assertEq(pendingMPToBeMintedAfter, 0);
        }
    }
}

contract MigrationStakeManagerTest is StakeManagerTest {
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
        assertEq(address(newStakeManager.previousManager()), address(stakeManager));
        assertEq(newStakeManager.totalSupply(), 0);
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
}

contract ExecuteEpochTest is MigrationStakeManagerTest {
    function test_ExecuteEpochNewEpoch() public {
        uint256 firstEpochEnd = stakeManager.epochEnd();
        assertEq(stakeManager.currentEpoch(), 0, "Epoch not 0 at start of test");
        assertEq(stakeManager.newEpoch(), 0, "New epoch not 0 at start of test");
        stakeManager.executeEpoch();
        assertEq(stakeManager.currentEpoch(), 0, "Epoch should not increase if no time passed since start");

        vm.warp(firstEpochEnd - 1);
        assertEq(stakeManager.newEpoch(), 0, "New epoch not 0 if 1 second before epoch end");
        stakeManager.executeEpoch();
        assertEq(stakeManager.currentEpoch(), 0, "Epoch should not increase if 1 second before epoch end");

        vm.warp(firstEpochEnd);
        assertEq(stakeManager.newEpoch(), 1, "New epoch should be 1 if exactly at epochEnd");
        stakeManager.executeEpoch();
        assertEq(stakeManager.currentEpoch(), 1, "Current epoch should increased to 1 if exactly at epochEnd of 0");

        vm.warp(firstEpochEnd + 1);
        assertEq(stakeManager.newEpoch(), 1, "New epoch should be 1 if 1 second after epochend of 1");
        stakeManager.executeEpoch();
        assertEq(stakeManager.currentEpoch(), 1, "Current epoch should increase if 1 second after epochend of 1");

        vm.warp(firstEpochEnd + (stakeManager.EPOCH_SIZE() * 99));
        assertEq(stakeManager.newEpoch(), 100);
        stakeManager.executeEpoch();
        assertEq(stakeManager.currentEpoch(), 100);
    }

    function test_ExecuteEpochExecuteEpochAfterEnd() public {
        StakeVault userVault = _createStakingAccount(makeAddr("testUser"), 100_000, 0);

        vm.warp(stakeManager.epochEnd() + (stakeManager.EPOCH_SIZE() / 2));
        stakeManager.executeEpoch();
        stakeManager.executeAccount(address(userVault), stakeManager.currentEpoch());
        vm.warp(stakeManager.epochEnd());

        stakeManager.executeEpoch();
        stakeManager.executeAccount(address(userVault), stakeManager.currentEpoch());

        vm.warp(stakeManager.epochEnd() + (stakeManager.EPOCH_SIZE() * 2));
        stakeManager.executeEpoch();
        stakeManager.executeAccount(address(userVault), stakeManager.currentEpoch());
    }

    function test_ExecuteEpochExecuteEpochExecuteAccountAfterManyEpochs() public {
        StakeVault userVault = _createStakingAccount(makeAddr("testUser"), 100_000, 0);

        for (uint256 i = 0; i < 10; i++) {
            vm.warp(stakeManager.epochEnd());
            stakeManager.executeEpoch();
        }
        stakeManager.executeAccount(address(userVault), stakeManager.currentEpoch());
    }

    function test_ExecuteEpochExecuteEpochExecuteAccountAfterManyEpochsJumoMany() public {
        StakeVault userVault = _createStakingAccount(makeAddr("testUser"), 100_000, 0);

        for (uint256 i = 0; i < 10; i++) {
            vm.warp(stakeManager.epochEnd());
        }
        stakeManager.executeEpoch();
        stakeManager.executeAccount(address(userVault), stakeManager.currentEpoch());
    }

    function test_ExecuteEpochExecuteAccountAfterManyEpochsJumoMany() public {
        StakeVault userVault = _createStakingAccount(makeAddr("testUser"), 100_000, 0);

        for (uint256 i = 0; i < 10; i++) {
            vm.warp(stakeManager.epochEnd());
        }
        stakeManager.executeAccount(address(userVault));
    }

    function test_ExecuteEpochExecuteEpochExecuteAccountAfterManyEpochsWithBrokenTime() public {
        StakeVault userVault = _createStakingAccount(makeAddr("testUser"), 100_000, 0);

        for (uint256 i = 0; i < 10; i++) {
            vm.warp(stakeManager.epochEnd() + (stakeManager.EPOCH_SIZE() / 10 - i));
            stakeManager.executeEpoch();
        }
        stakeManager.executeAccount(address(userVault), stakeManager.currentEpoch());
    }

    function test_ExecuteEpochExecuteEpochExecuteAccountAfterManyEpochsWithBrokenTimeJumpMany() public {
        StakeVault userVault = _createStakingAccount(makeAddr("testUser"), 100_000, 0);

        for (uint256 i = 0; i < 10; i++) {
            vm.warp(stakeManager.epochEnd() + (stakeManager.EPOCH_SIZE() / 10 - i));
        }
        stakeManager.executeEpoch();
        stakeManager.executeAccount(address(userVault), stakeManager.currentEpoch());
    }

    function test_ExecuteEpochExecuteAccountAfterManyEpochsWithBrokenTimeJumpMany() public {
        StakeVault userVault = _createStakingAccount(makeAddr("testUser"), 100_000, 0);

        for (uint256 i = 0; i < 10; i++) {
            vm.warp(stakeManager.epochEnd() + (stakeManager.EPOCH_SIZE() / 10 - i));
        }
        stakeManager.executeAccount(address(userVault));
    }

    function test_ExecuteEpochExecuteAccountAfterEpochEnd() public {
        StakeVault userVault = _createStakingAccount(makeAddr("testUser"), 100_000, 0);

        vm.warp(stakeManager.epochEnd() + (stakeManager.EPOCH_SIZE() / 2));
        stakeManager.executeAccount(address(userVault), stakeManager.currentEpoch());

        vm.warp(stakeManager.epochEnd());
        stakeManager.executeAccount(address(userVault), stakeManager.currentEpoch());

        vm.warp(stakeManager.epochEnd() + (stakeManager.EPOCH_SIZE() * 2));
        stakeManager.executeAccount(address(userVault), stakeManager.currentEpoch());
    }

    function test_ExecuteEpochExecuteAccountAfterManyEpochsWithBrokenTime() public {
        StakeVault userVault = _createStakingAccount(makeAddr("testUser"), 100_000, 0);

        for (uint256 i = 0; i < 10; i++) {
            vm.warp(stakeManager.epochEnd() + (stakeManager.EPOCH_SIZE() / 10 - i));
            stakeManager.executeAccount(address(userVault), stakeManager.currentEpoch());
        }
    }

    function test_ExecuteEpochShouldNotIncreaseEpochBeforeEnd() public {
        assertEq(stakeManager.currentEpoch(), 0);

        vm.warp(stakeManager.epochEnd() - 1);
        stakeManager.executeEpoch();
        assertEq(stakeManager.currentEpoch(), 0);
    }

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
