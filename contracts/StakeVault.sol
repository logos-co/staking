// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IStakeManager } from "./IStakeManager.sol";

/**
 * @title StakeVault
 * @author Ricardo Guilherme Schmidt <ricardo3@status.im>
 * @notice Secures user stake
 */
contract StakeVault is Ownable {
    error StakeVault__MigrationNotAvailable();

    error StakeVault__StakingFailed();

    error StakeVault__UnstakingFailed();

    IStakeManager private stakeManager;

    IERC20 public immutable stakedToken;

    event Staked(address from, address to, uint256 _amount, uint256 time);

    constructor(address _owner, IERC20 _stakedToken, IStakeManager _stakeManager) {
        _transferOwnership(_owner);
        stakedToken = _stakedToken;
        stakeManager = _stakeManager;
    }

    function stake(uint256 _amount, uint256 _time) external onlyOwner {
        bool success = stakedToken.transferFrom(msg.sender, address(this), _amount);
        if (!success) {
            revert StakeVault__StakingFailed();
        }
        stakeManager.stake(_amount, _time);

        emit Staked(msg.sender, address(this), _amount, _time);
    }

    function lock(uint256 _time) external onlyOwner {
        stakeManager.lock(_time);
    }

    function unstake(uint256 _amount) external onlyOwner {
        stakeManager.unstake(_amount);
        bool success = stakedToken.transfer(msg.sender, _amount);
        if (!success) {
            revert StakeVault__UnstakingFailed();
        }
    }

    function leave() external onlyOwner {
        if (stakeManager.leave()) {
            stakedToken.transferFrom(address(this), msg.sender, stakedToken.balanceOf(address(this)));
        }
    }

    /**
     * @notice Opt-in migration to a new IStakeManager contract.
     */
    function acceptMigration() external onlyOwner {
        IStakeManager migrated = stakeManager.acceptUpdate();
        if (address(migrated) == address(0)) revert StakeVault__MigrationNotAvailable();
        stakeManager = migrated;
    }
}
