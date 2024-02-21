// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import { Test } from "forge-std/Test.sol";
import { Deploy } from "../script/Deploy.s.sol";
import { DeploymentConfig } from "../script/DeploymentConfig.s.sol";

import { StakeManager } from "../contracts/StakeManager.sol";
import { StakeVault } from "../contracts/StakeVault.sol";
import { VaultFactory } from "../contracts/VaultFactory.sol";

contract VaultFactoryTest is Test {
    DeploymentConfig internal deploymentConfig;

    StakeManager internal stakeManager;

    VaultFactory internal vaultFactory;

    StakeManager internal migrationStakeManager;

    address internal deployer;

    address internal stakedToken;

    address internal testUser = makeAddr("testUser");

    function setUp() public virtual {
        Deploy deployment = new Deploy();
        (vaultFactory, stakeManager, migrationStakeManager, deploymentConfig) = deployment.run();
        (deployer, stakedToken) = deploymentConfig.activeNetworkConfig();
    }

    function testDeployment() public {
        assertEq(address(vaultFactory.stakeManager()), address(stakeManager));
    }
}

contract SetStakeManagerTest is VaultFactoryTest {
    function setUp() public override {
        VaultFactoryTest.setUp();
    }

    function test_RevertWhen_InvalidStakeManagerAddress() public {
        vm.startPrank(deployer);
        vm.expectRevert(VaultFactory.VaultFactory__InvalidStakeManagerAddress.selector);
        vaultFactory.setStakeManager(address(0));

        vm.expectRevert(VaultFactory.VaultFactory__InvalidStakeManagerAddress.selector);
        vaultFactory.setStakeManager(address(stakeManager));
    }

    function test_SetStakeManager() public {
        vm.prank(deployer);
        vaultFactory.setStakeManager(address(this));
        assertEq(address(vaultFactory.stakeManager()), address(this));
    }
}

contract CreateVaultTest is VaultFactoryTest {
    event VaultCreated(address indexed vault, address indexed owner);

    function setUp() public override {
        VaultFactoryTest.setUp();
    }

    function test_createVault() public {
        vm.prank(testUser);
        vm.expectEmit(false, false, false, false);
        emit VaultCreated(makeAddr("some address"), testUser);
        StakeVault vault = vaultFactory.createVault();
        assertEq(vault.owner(), testUser);
        assertEq(address(vault.stakedToken()), address(stakedToken));
    }
}
