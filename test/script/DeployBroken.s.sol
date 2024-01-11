// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import { BaseScript } from "../../script/Base.s.sol";
import { StakeManager } from "../../contracts/StakeManager.sol";
import { VaultFactory } from "../../contracts/VaultFactory.sol";
import { BrokenERC20 } from "../mocks/BrokenERC20.s.sol";

contract DeployBroken is BaseScript {
    function run() public returns (VaultFactory, StakeManager, address) {
        BrokenERC20 token = new BrokenERC20();

        vm.startBroadcast(broadcaster);
        StakeManager stakeManager = new StakeManager(address(token), address(0));
        VaultFactory vaultFactory = new VaultFactory(address(stakeManager));
        vm.stopBroadcast();

        return (vaultFactory, stakeManager, address(token));
    }
}
