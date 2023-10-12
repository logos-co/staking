// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import { Test } from "forge-std/Test.sol";
import { Deploy } from "../script/Deploy.s.sol";
import { DeploymentConfig } from "../script/DeploymentConfig.s.sol";
import { StakeManager } from "../contracts/StakeManager.sol";
import { StakeVault } from "../contracts/StakeVault.sol";
import { VaultFactory } from "../contracts/VaultFactory.sol";

contract StakeVaultTest is Test {
    StakeManager internal stakeManager;

    DeploymentConfig internal deploymentConfig;

    VaultFactory internal vaultFactory;

    StakeVault internal stakeVault;

    address internal deployer;

    address internal testUser = makeAddr("testUser");

    address internal stakeToken;

    function setUp() public virtual {
        Deploy deployment = new Deploy();
        (vaultFactory, stakeManager, deploymentConfig) = deployment.run();
        (deployer, stakeToken) = deploymentConfig.activeNetworkConfig();

        vm.prank(testUser);
        stakeVault = vaultFactory.createVault();
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
