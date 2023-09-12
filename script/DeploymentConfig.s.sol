//// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.19 <=0.9.0;

import { Script } from "forge-std/Script.sol";
import { MockERC20 } from "../test/mocks/MockERC20.sol";

contract DeploymentConfig is Script {
    error DeploymentConfig_InvalidDeployerAddress();
    error DeploymentConfig_NoConfigForChain(uint256);

    struct NetworkConfig {
        address deployer;
        address token;
    }

    NetworkConfig public activeNetworkConfig;

    address private deployer;

    constructor(address _broadcaster) {
        if (block.chainid == 31_337) {
            activeNetworkConfig = getOrCreateAnvilEthConfig(_broadcaster);
        } else {
            revert DeploymentConfig_NoConfigForChain(block.chainid);
        }
        if (_broadcaster == address(0)) revert DeploymentConfig_InvalidDeployerAddress();
        deployer = _broadcaster;
    }

    function getOrCreateAnvilEthConfig(address _deployer) public returns (NetworkConfig memory) {
        vm.startBroadcast();
        MockERC20 token = new MockERC20();
        vm.stopBroadcast();
        return NetworkConfig({ token: address(token), deployer: _deployer });
    }

    // This function is a hack to have it excluded by `forge coverage` until
    // https://github.com/foundry-rs/foundry/issues/2988 is fixed.
    // See: https://github.com/foundry-rs/foundry/issues/2988#issuecomment-1437784542
    // for more info.
    // solhint-disable-next-line
    function test() public { }
}
