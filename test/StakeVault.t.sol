// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import { Test } from "forge-std/Test.sol";
import { Deploy } from "../script/Deploy.s.sol";
import { DeploymentConfig } from "../script/DeploymentConfig.s.sol";
import { StakeManager } from "../contracts/StakeManager.sol";
import { StakeVault } from "../contracts/StakeVault.sol";

contract StakeVaultTest is Test {
    StakeManager internal stakeManager;

    DeploymentConfig internal deploymentConfig;

    StakeVault internal stakeVault;

    address internal deployer;

    address internal testUser = makeAddr("testUser");

    address internal stakeToken;

    function setUp() public virtual {
        Deploy deployment = new Deploy();
        (stakeManager, deploymentConfig) = deployment.run();
        (deployer, stakeToken) = deploymentConfig.activeNetworkConfig();

        vm.prank(testUser);
        stakeVault = new StakeVault(testUser, ERC20(stakeToken), stakeManager);
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
