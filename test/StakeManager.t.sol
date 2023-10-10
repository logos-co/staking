// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import { Test } from "forge-std/Test.sol";
import { Deploy } from "../script/Deploy.s.sol";
import { DeploymentConfig } from "../script/DeploymentConfig.s.sol";
import { StakeManager } from "../contracts/StakeManager.sol";
import { StakeVault } from "../contracts/StakeVault.sol";

contract StakeManagerTest is Test {
    DeploymentConfig internal deploymentConfig;
    StakeManager internal stakeManager;

    address internal stakeToken;
    address internal deployer;
    address internal testUser = makeAddr("testUser");

    function setUp() public virtual {
        Deploy deployment = new Deploy();
        (stakeManager, deploymentConfig) = deployment.run();
        (deployer, stakeToken) = deploymentConfig.activeNetworkConfig();
    }

    function testDeployment() public {
        assertEq(stakeManager.owner(), deployer);
        assertEq(stakeManager.currentEpoch(), 0);
        assertEq(stakeManager.pendingReward(), 0);
        assertEq(stakeManager.multiplierSupply(), 0);
        assertEq(stakeManager.stakeSupply(), 0);
        assertEq(address(stakeManager.stakedToken()), stakeToken);
        assertEq(address(stakeManager.oldManager()), address(0));
        assertEq(stakeManager.totalSupply(), 0);
    }

    function _createTestVault(address owner) internal returns (StakeVault vault) {
        vm.prank(owner);
        vault = new StakeVault(owner, ERC20(stakeToken), stakeManager);

        vm.prank(deployer);
        stakeManager.setVault(address(vault).codehash);
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
}

contract UnstakeTest is StakeManagerTest {
    function setUp() public override {
        StakeManagerTest.setUp();
    }

    function test_RevertWhen_SenderIsNotVault() public {
        vm.expectRevert(StakeManager.StakeManager__SenderIsNotVault.selector);
        stakeManager.unstake(100);
    }

    function test_RevertWhen_FundsLocked() public {
        // ensure user has funds
        deal(stakeToken, testUser, 1000);
        StakeVault userVault = _createTestVault(testUser);

        vm.startPrank(testUser);
        ERC20(stakeToken).approve(address(userVault), 100);

        uint256 lockTime = 1 days;
        userVault.stake(100, lockTime);

        vm.expectRevert(StakeManager.StakeManager__FundsLocked.selector);
        userVault.unstake(100);
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

    function test_RevertWhen_DecreasingLockTime() public {
        // ensure user has funds
        deal(stakeToken, testUser, 1000);
        StakeVault userVault = _createTestVault(testUser);

        vm.startPrank(testUser);
        // ensure user vault can spend user tokens
        ERC20(stakeToken).approve(address(userVault), 100);

        uint256 lockTime = 1 days;
        userVault.stake(100, lockTime);

        vm.expectRevert(StakeManager.StakeManager__DecreasingLockTime.selector);
        userVault.lock(1);
    }
}

contract LeaveTest is StakeManagerTest {
    function setUp() public override {
        StakeManagerTest.setUp();
    }

    function test_RevertWhen_SenderIsNotVault() public {
        vm.expectRevert(StakeManager.StakeManager__SenderIsNotVault.selector);
        stakeManager.leave();
    }

    function test_RevertWhen_NoPendingMigration() public {
        StakeVault userVault = _createTestVault(testUser);
        vm.prank(testUser);
        vm.expectRevert(StakeManager.StakeManager__NoPendingMigration.selector);
        userVault.leave();
    }
}

contract MigrateTest is StakeManagerTest {
    function setUp() public override {
        StakeManagerTest.setUp();
    }

    function test_RevertWhen_SenderIsNotVault() public {
        vm.expectRevert(StakeManager.StakeManager__SenderIsNotVault.selector);
        stakeManager.migrate();
    }

    function test_RevertWhen_NoPendingMigration() public {
        StakeVault userVault = _createTestVault(testUser);
        vm.prank(testUser);
        vm.expectRevert(StakeManager.StakeManager__NoPendingMigration.selector);
        userVault.updateManager();
    }
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

        uint256 lockTime = 1 days;
        userVault.stake(100, lockTime);

        uint256 currentEpoch = stakeManager.currentEpoch();

        vm.expectRevert(StakeManager.StakeManager__InvalidLimitEpoch.selector);
        stakeManager.executeAccount(address(userVault), currentEpoch + 1);
    }
}
