// SPDX-License-Identifier: MIT

pragma solidity 0.8.20;

import "./StakeManager.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
/**
 * @title StakeVault
 * @author Ricardo Guilherme Schmidt <ricardo3@status.im>
 * @notice Secures user stake
 */
contract StakeVault is Ownable {
    StakeManager stakeManager;
    ERC20 stakedToken;

    constructor(address _owner) {

    }

    function join(uint256 _amount, uint256 _time) external onlyOwner {
        stakedToken.transferFrom(msg.sender, address(this), _amount);
        stakeManager.join(_amount, _time);
    }

    function lock(uint256 _time) external onlyOwner {
        stakeManager.lock(_time);
    }

    function leave(uint256 _amount) external onlyOwner {
        stakeManager.leave(_amount);
        stakedToken.transferFrom(address(this), msg.sender, _amount);
    }

    function updateManager() external onlyOwner {
        StakeManager migrated = stakeManager.migrate();
        require(address(migrated) != address(0), "Migration not available.");
        stakeManager = migrated;
    }

}