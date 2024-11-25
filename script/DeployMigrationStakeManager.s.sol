// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.27 <=0.9.0;

import { BaseScript } from "./Base.s.sol";
import { StakeManager } from "../contracts/StakeManager.sol";
import { StakeManagerUpdated } from "../contracts/StakeManagerUpdated.sol";

contract DeployMigrationStakeManager is BaseScript {
    error DeployMigrationStakeManager_InvalidStakeTokenAddress();
    error DeployMigrationStakeManager_InvalidStakeManagerAddress();

    address public prevStakeManager;

    address public stakeToken;

    constructor(address _prevStakeManager, address _stakeToken) {
        prevStakeManager = _prevStakeManager;
        stakeToken = _stakeToken;
    }

    function run() public returns (StakeManagerUpdated) {
        prevStakeManager = vm.envOr({ name: "PREV_STAKE_MANAGER", defaultValue: prevStakeManager });
        stakeToken = vm.envOr({ name: "STAKING_TOKEN_ADDRESS", defaultValue: stakeToken });

        if (prevStakeManager == address(0)) {
            revert DeployMigrationStakeManager_InvalidStakeManagerAddress();
        }

        if (stakeToken == address(0)) {
            revert DeployMigrationStakeManager_InvalidStakeTokenAddress();
        }

        vm.startBroadcast(broadcaster);
        StakeManagerUpdated stakeManager = new StakeManagerUpdated(stakeToken, StakeManager(prevStakeManager));
        vm.stopBroadcast();

        return stakeManager;
    }
}
