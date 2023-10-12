// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { StakeManager } from "./StakeManager.sol";

/**
 * @title StakeVault
 * @author Ricardo Guilherme Schmidt <ricardo3@status.im>
 * @notice Secures user stake
 */

contract StakeVault is Ownable {
    error StakeVault__MigrationNotAvailable();

    StakeManager private stakeManager;
    ERC20 immutable stakedToken;

    event Staked(address from, address to, uint256 _amount, uint256 time);

    constructor(address _owner, ERC20 _stakedToken, StakeManager _stakeManager) {
        _transferOwnership(_owner);
        stakedToken = _stakedToken;
        stakeManager = _stakeManager;
    }

    function stake(uint256 _amount, uint256 _time) external onlyOwner {
        stakedToken.transferFrom(msg.sender, address(this), _amount);
        stakeManager.stake(_amount, _time);

        emit Staked(msg.sender, address(this), _amount, _time);
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
        if (address(migrated) == address(0)) revert StakeVault__MigrationNotAvailable();
        stakeManager = migrated;
    }
}
