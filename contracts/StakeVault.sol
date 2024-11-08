// SPDX-License-Identifier: MIT

pragma solidity ^0.8.26;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IStakeManager } from "./IStakeManager.sol";
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

    IStakeManager private stakeManager;

    IERC20 public immutable STAKING_TOKEN;

    event Staked(address from, address to, uint256 _amount, uint256 time);

    constructor(address _owner, IERC20 _STAKING_TOKEN, IStakeManager _stakeManager) {
        _transferOwnership(_owner);
        STAKING_TOKEN = _STAKING_TOKEN;
        stakeManager = _stakeManager;
    }

    function stake(uint256 _amount, uint256 _time) external onlyOwner {
        bool success = STAKING_TOKEN.transferFrom(msg.sender, address(this), _amount);
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
        bool success = STAKING_TOKEN.transfer(msg.sender, _amount);
        if (!success) {
            revert StakeVault__UnstakingFailed();
        }
    }

    function leave() external onlyOwner {
        if (StakeManager(stakeManager).leave()) {
            STAKING_TOKEN.transferFrom(address(this), msg.sender, STAKING_TOKEN.balanceOf(address(this)));
        }
    }

    /**
     * @notice Opt-in migration to a new IStakeManager contract.
     */
    function acceptMigration() external onlyOwner {
        IStakeManager migrated = StakeManager(stakeManager).acceptUpdate();
        if (address(migrated) == address(0)) revert StakeVault__MigrationNotAvailable();
        stakeManager = migrated;
    }
}
