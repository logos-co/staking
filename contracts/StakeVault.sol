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

    constructor(address _owner) public {
        owner = _owner;
    }

    function join(uint256 _amount, uint256 _time) external onlyOwner {
        stakedToken.transferFrom(msg.sender, address(this), amount);
        stakeManager.join(amount, _time);
    }

    function lock(uint256 _time) external onlyOwner {
        stakeManager.lock(_time);
    }

    function leave(uint256 _amount) external onlyOwner {
        stakeManager.leave(amount);
        stakedToken.transferFrom(address(this), msg.sender, amount);
    }

    function updateManager() external onlyOwner {
        address migrated = stakeManager.migrate();
        require(migrated != address(0), "Migration not available.");
        stakeManager = migrated;
    }

}