// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.19 <=0.9.0;

import { BaseScript } from "./Base.s.sol";
import { StakeManager } from "../contracts/StakeManager.sol";

contract DeployMigrationStakeManager is BaseScript {
    error DeployMigrationStakeManager_InvalidStakeTokenAddress();

    address public prevStakeManager;

    address public stakeToken;

    constructor(address _prevStakeManager, address _stakeToken) {
        prevStakeManager = _prevStakeManager;
        stakeToken = _stakeToken;
    }

    function run() public returns (StakeManager) {
        prevStakeManager = vm.envOr({ name: "PREV_STAKE_MANAGER", defaultValue: prevStakeManager });
        stakeToken = vm.envOr({ name: "STAKE_TOKEN_ADDRESS", defaultValue: stakeToken });

        if (stakeToken == address(0)) {
            revert DeployMigrationStakeManager_InvalidStakeTokenAddress();
        }

        vm.startBroadcast(broadcaster);
        StakeManager stakeManager = new StakeManager(stakeToken, prevStakeManager);
        vm.stopBroadcast();

        return stakeManager;
    }
}
