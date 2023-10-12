// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.19 <=0.9.0;

import { BaseScript } from "./Base.s.sol";
import { DeploymentConfig } from "./DeploymentConfig.s.sol";
import { StakeManager } from "../contracts/StakeManager.sol";
import { VaultFactory } from "../contracts/VaultFactory.sol";

contract Deploy is BaseScript {
    function run() public returns (VaultFactory, StakeManager, DeploymentConfig) {
        DeploymentConfig deploymentConfig = new DeploymentConfig(broadcaster);
        (, address token) = deploymentConfig.activeNetworkConfig();

        vm.startBroadcast(broadcaster);
        StakeManager stakeManager = new StakeManager(token, address(0));
        VaultFactory vaultFactory = new VaultFactory(address(stakeManager));
        vm.stopBroadcast();

        return (vaultFactory, stakeManager, deploymentConfig);
    }
}
