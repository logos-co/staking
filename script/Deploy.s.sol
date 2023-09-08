// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.19 <=0.9.0;

import { BaseScript } from "./Base.s.sol";
import { DeploymentConfig } from "./DeploymentConfig.s.sol";
import { StakeManager } from "../contracts/StakeManager.sol";

contract Deploy is BaseScript {
    function run() public returns (StakeManager, DeploymentConfig) {
        DeploymentConfig deploymentConfig = new DeploymentConfig(broadcaster);
        (address token,) = deploymentConfig.activeNetworkConfig();

        vm.startBroadcast(broadcaster);
        StakeManager stakeManager = new StakeManager(token, address(0));
        vm.stopBroadcast();

        return (stakeManager, deploymentConfig);
    }
}
