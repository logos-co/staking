// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import { Test } from "forge-std/Test.sol";
import { Deploy } from "../script/Deploy.s.sol";
import { DeploymentConfig } from "../script/DeploymentConfig.s.sol";
import { StakeManager } from "../contracts/StakeManager.sol";

contract StakeManagerTest is Test {
    address internal deployer;

    DeploymentConfig internal deploymentConfig;
    StakeManager internal stakeManager;

    function setUp() public virtual {
        Deploy deployment = new Deploy();
        (stakeManager, deploymentConfig) = deployment.run();
        (deployer,) = deploymentConfig.activeNetworkConfig();
    }

    function testDeployment() public {
        assertEq(stakeManager.owner(), deployer);
        assertEq(stakeManager.totalSupply(), 0);
    }
}
