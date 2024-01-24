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

    error StakeVault__StakingFailed();

    error StakeVault__UnstakingFailed();

    StakeManager private stakeManager;

    ERC20 public immutable STAKED_TOKEN;

    event Staked(address from, address to, uint256 _amount, uint256 time);

    constructor(address _owner, ERC20 _stakedToken, StakeManager _stakeManager) {
        _transferOwnership(_owner);
        STAKED_TOKEN = _stakedToken;
        stakeManager = _stakeManager;
    }

    function stake(uint256 _amount, uint256 _time) external onlyOwner {
        bool success = STAKED_TOKEN.transferFrom(msg.sender, address(this), _amount);
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
        bool success = STAKED_TOKEN.transfer(msg.sender, _amount);
        if (!success) {
            revert StakeVault__UnstakingFailed();
        }
    }

    function leave() external onlyOwner {
        stakeManager.migrateTo(false);
        STAKED_TOKEN.transferFrom(address(this), msg.sender, STAKED_TOKEN.balanceOf(address(this)));
    }

    /**
     * @notice Opt-in migration to a new StakeManager contract.
     */
    function acceptMigration() external onlyOwner {
        StakeManager migrated = stakeManager.migrateTo(true);
        if (address(migrated) == address(0)) revert StakeVault__MigrationNotAvailable();
        stakeManager = migrated;
    }

    function stakedToken() external view returns (ERC20) {
        return STAKED_TOKEN;
    }
}
