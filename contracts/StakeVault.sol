// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import "./StakeManager.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
/**
 * @title StakeVault
 * @author Ricardo Guilherme Schmidt <ricardo3@status.im>
 * @notice Secures user stake
 */
contract StakeVault is Ownable {
    StakeManager stakeManager;
    ERC20 stakedToken;

    constructor(address _owner) {
        _transferOwnership(_owner);
    }

    function stake(uint256 _amount, uint256 _time) external onlyOwner {
        stakedToken.transferFrom(msg.sender, address(this), _amount);
        stakeManager.stake(_amount, _time);
    }

    function lock(uint256 _time) external onlyOwner {
        stakeManager.lock(_time);
    }

    function unstake(uint256 _amount) external onlyOwner {
        stakeManager.unstake(_amount);
        stakedToken.transferFrom(address(this), msg.sender, _amount);
    }

    function leave() external onlyOwner {
        stakeManager.leave();
        stakedToken.transferFrom(address(this), msg.sender, stakedToken.balanceOf(address(this)));
    }

    /**
     * @notice Opt-in migration to a new StakeManager contract.
     */
    function updateManager() external onlyOwner {
        StakeManager migrated = stakeManager.migrate();
        require(address(migrated) != address(0), "Migration not available.");
        stakeManager = migrated;
    }

}