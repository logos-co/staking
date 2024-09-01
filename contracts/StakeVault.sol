// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import { Ownable } from "@openzeppelin/contracts/access/AccessControl.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { StakeManager } from "./StakeManager.sol";

/**
 * @title StakeVault
 * @author Ricardo Guilherme Schmidt <ricardo3@status.im>
 * @notice Secures user stake
 */
contract StakeVault is AccessControl {
    error StakeVault__MigrationNotAvailable();

    error StakeVault__StakingFailed();

    error StakeVault__UnstakingFailed();

    error StakeVault__InvalidStakeManagerAddress();

    StakeManager private stakeManager;
    VaultManager public vaultManager;
    ERC20 public immutable STAKED_TOKEN;
    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");

    event Staked(address from, address to, uint256 _amount, uint256 time);

    constructor(address _owner, StakeManager _stakeManager, VaultManager _vaultManager) {
        _grantRole(DEFAULT_ADMIN_ROLE, _owner);
        _setRoleAdmin(MANAGER_ROLE, DEFAULT_ADMIN_ROLE);
        _grantRole(MANAGER_ROLE, _owner);

        if(address(_stakeManager) == address(0)) {
            revert StakeVault__InvalidStakeManagerAddress();
        }

        if(address(_vaultManager) == address(0)) {
            _grantRole(MANAGER_ROLE, _vaultManager);
        }
        
        STAKED_TOKEN = _stakeManager.stakedToken();
        stakeManager = _stakeManager;
        vaultManager = _vaultManager;
    }

    function stake(uint256 _amount, uint256 _time) external hasRole(MANAGER_ROLE) {
        bool success = STAKED_TOKEN.transferFrom(msg.sender, address(this), _amount);
        if (!success) {
            revert StakeVault__StakingFailed();
        }
        stakeManager.stake(_amount, _time);

        emit Staked(msg.sender, address(this), _amount, _time);
    }

    function lock(uint256 _time) external hasRole(MANAGER_ROLE) {
        stakeManager.lock(_time);
    }

    function unstake(uint256 _amount, address _receiver) external hasRole(MANAGER_ROLE) {
        stakeManager.unstake(_amount);
        bool success = STAKED_TOKEN.transfer(_receiver, _amount);
        if (!success) {
            revert StakeVault__UnstakingFailed();
        }
    }

    function leave(address _receiver) external hasRole(MANAGER_ROLE) {
        stakeManager.migrateTo(false);
        STAKED_TOKEN.transfer(_receiver, STAKED_TOKEN.balanceOf(address(this)));
    }

    /**
     * @notice Opt-in migration to a new StakeManager contract.
     */
    function acceptMigration() external hasRole(MANAGER_ROLE) {
        StakeManager migrated = stakeManager.migrateTo(true);
        if (address(migrated) == address(0)) revert StakeVault__MigrationNotAvailable();
        stakeManager = migrated;
    }

    function stakedToken() external view returns (ERC20) {
        return STAKED_TOKEN;
    }
}
