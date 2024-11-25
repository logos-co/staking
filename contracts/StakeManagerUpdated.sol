// SPDX-License-Identifier: MIT

pragma solidity ^0.8.27;

import { StakeManager } from "./StakeManager.sol";
import { IStakeManagerUpdated } from "./interfaces/IStakeManagerUpdated.sol";
import { EpochMath } from "./EpochMath.sol";
import { ExpiredStakeStorage } from "./storage/ExpiredStakeStorage.sol";

contract StakeManagerUpdated is IStakeManagerUpdated, StakeManager {
    StakeManager public immutable PREVIOUS_MANAGER;

    error StakeManager__SenderIsNotPreviousStakeManager();

    /**
     * @notice Only callable from old manager.
     */
    modifier onlyPreviousManager() {
        if (msg.sender != address(PREVIOUS_MANAGER)) {
            revert StakeManager__SenderIsNotPreviousStakeManager();
        }
        _;
    }

    constructor(address _rewardToken, StakeManager _previousManager) StakeManager(_rewardToken) {
        PREVIOUS_MANAGER = _previousManager;
        EXPIRED_STAKE_STORAGE = _previousManager.EXPIRED_STAKE_STORAGE();
        START_TIME = _previousManager.START_TIME();
    }

    /**
     * @dev Overwrites _createStorage() frm EpochMath to prevent reinstantiation of the ExpiredStakeStorage, as it's
     * going to be reused from the PREVIOUS_MANAGER
     */
    function _createStorage() internal pure override returns (ExpiredStakeStorage) {
        return ExpiredStakeStorage(address(0));
    }

    /**
     * @dev Callable automatically from old StakeManager.startMigration(address)
     * @notice Initilizes migration process
     * @param _currentEpoch epoch of old manager
     * @param _totalMP MP supply on old manager
     * @param _totalStaked stake supply on old manager
     * @param _startTime start time of old manager
     */
    function migrationInitialize(
        uint256 _currentEpoch,
        uint256 _totalMP,
        uint256 _totalStaked,
        uint256 _startTime,
        uint256 _totalMPRate,
        uint256 _potentialMP,
        uint256 _currentEpochExpiredMP
    )
        external
        onlyPreviousManager
        noPendingMigration
    {
        if (currentEpoch > 0) {
            revert StakeManager__AlreadyProcessedEpochs();
        }
        if (_startTime != START_TIME) {
            revert StakeManager__InvalidMigration();
        }
        currentEpoch = _currentEpoch;
        totalMP = _totalMP;
        totalStaked = _totalStaked;
        totalMPRate = _totalMPRate;
        potentialMP = _potentialMP;
        currentEpochTotalExpiredMP = _currentEpochExpiredMP;
    }

    /**
     * @dev Only callable from old manager.
     * @notice Migrate account from old manager
     * @param _vault Account address
     * @param _account Account data
     * @param _acceptMigration If account should be stored or its MP/balance supply reduced
     */
    function migrateFrom(address _vault, bool _acceptMigration, Account memory _account) external onlyPreviousManager {
        if (_acceptMigration) {
            accounts[_vault] = _account;
        } else {
            totalMP -= _account.totalMP;
            totalStaked -= _account.balance;
        }
    }

    /**
     * @dev Only callable from old manager.
     * @notice Increase total MP from old manager
     * @param _amount amount MP increased on account after migration initialized
     */
    function increaseTotalMP(uint256 _amount) external onlyPreviousManager {
        totalMP += _amount;
    }
}
