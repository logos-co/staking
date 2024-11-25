// SPDX-License-Identifier: MIT

pragma solidity ^0.8.27;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

import { ExpiredStakeStorage } from "./storage/ExpiredStakeStorage.sol";
import { TrustedCodehashAccess } from "./access/TrustedCodehashAccess.sol";
import { IStakeManager } from "./interfaces/IStakeManager.sol";
import { EpochMath } from "./EpochMath.sol";
import { StakeMath } from "./StakeMath.sol";
import { StakeVault } from "./StakeVault.sol";
import { IStakeManagerUpdated } from "./interfaces/IStakeManagerUpdated.sol";

contract StakeManager is StakeMath, EpochMath, TrustedCodehashAccess, IStakeManager {
    error StakeManager__NoPendingMigration();
    error StakeManager__PendingMigration();
    error StakeManager__InvalidLimitEpoch();
    error StakeManager__AccountNotInitialized();
    error StakeManager__InvalidMigration();
    error StakeManager__AlreadyProcessedEpochs();
    error StakeManager__AlreadyStaked();

    mapping(address index => Account value) public accounts;

    uint256 public totalMP;
    uint256 public totalStaked;

    IStakeManagerUpdated public migration;
    IERC20 public immutable REWARD_TOKEN;
    IERC20 public immutable STAKING_TOKEN;

    modifier onlyAccountInitialized(address account) {
        if (accounts[account].lockUntil == 0) {
            revert StakeManager__AccountNotInitialized();
        }
        _;
    }

    /**
     * @notice Only callable when migration is not initialized.
     */
    modifier noPendingMigration() {
        if (address(migration) != address(0)) {
            revert StakeManager__PendingMigration();
        }
        _;
    }

    /**
     * @notice Only callable when migration is initialized.
     */
    modifier onlyPendingMigration() {
        if (address(migration) == address(0)) {
            revert StakeManager__NoPendingMigration();
        }
        _;
    }

    constructor(address _rewardToken) EpochMath(block.timestamp) {
        REWARD_TOKEN = IERC20(_rewardToken);
        STAKING_TOKEN = IERC20(_rewardToken);
    }

    /**
     * @notice Increases balance of msg.sender;
     * @param _amount Amount of balance being staked.
     * @param _seconds Seconds of lockup time. 0 means no lockup.
     *
     * @dev Reverts when resulting locked time is not in range of [MIN_LOCKUP_PERIOD, MAX_LOCKUP_PERIOD]
     * @dev Reverts when amount staked results in less than 1 MP per epoch.
     */
    function stake(uint256 _amount, uint256 _seconds) external onlyTrustedCodehash noPendingMigration {
        _finalizeEpoch(newEpoch());
        Account storage account = accounts[msg.sender];
        if (account.lastMint == 0) {
            account.lastMint = block.timestamp;
            account.epoch = currentEpoch;
            account.rewardAddress = StakeVault(msg.sender).owner();
        } else {
            _processAccount(account, currentEpoch);
        }

        (uint256 _deltaMpTotal, uint256 _newMaxMP, uint256 _newLockEnd) =
            _calculateStake(account.balance, account.maxMP, account.lockUntil, block.timestamp, _amount, _seconds);

        account.maxMP = _newMaxMP;
        account.balance += _amount;
        account.lockUntil = _newLockEnd;
        account.totalMP += _deltaMpTotal;
        totalMP += _deltaMpTotal;
        totalStaked += _amount;
        if (account.startTime > 0) {
            _reducePredictiedMP(account.startTime, account.balance);
            if (_amount > 0) {
                account.startTime = _calculateNewStartTime(account.balance, account.totalMP, _newMaxMP, block.timestamp);
            }
        } else {
            account.startTime = block.timestamp;
        }
        _increasePredictedMP(account.startTime, account.balance, account.maxMP, account.totalMP);
    }

    /**
     * @notice Unstakes a certain `_amount`.
     * @param _amount Amount to unstake.
     * @dev Reverts when remaining amount staked results in less than 1 MP per epoch.
     * @dev Reverts when trying to unstake locked account
     */
    function unstake(uint256 _amount)
        external
        onlyTrustedCodehash
        onlyAccountInitialized(msg.sender)
        noPendingMigration
    {
        _finalizeEpoch(newEpoch());
        Account storage account = accounts[msg.sender];
        if (_amount > account.balance) {
            revert StakeManager__InsufficientFunds();
        }
        if (account.lockUntil > block.timestamp) {
            revert StakeManager__FundsLocked();
        }
        uint256 newBalance = account.balance - _amount;
        if (newBalance > 0 && newBalance < MIN_BALANCE) {
            revert StakeManager__StakeIsTooLow();
        }

        _processAccount(account, currentEpoch);

        uint256 reducedTotalMP = Math.mulDiv(_amount, account.totalMP, account.balance);

        totalStaked -= _amount;
        totalMP -= reducedTotalMP;

        _reducePredictiedMP(account.startTime, account.balance);
        if (newBalance == 0) {
            delete accounts[msg.sender];
        } else {
            account.maxMP -= Math.mulDiv(_amount, account.maxMP, account.balance);
            account.totalMP -= reducedTotalMP;
            account.balance = newBalance;
            if (account.totalMP < account.maxMP) {
                _increasePredictedMP(account.startTime, account.balance, account.maxMP, account.totalMP);
            }
        }
    }

    /**
     * @notice Locks entire balance for more amount of time.
     * @param _secondsIncrease Seconds to increase in locked time. If stake is unlocked, increases from
     * block.timestamp.
     *
     * @dev Reverts when resulting locked time is not in range of [MIN_LOCKUP_PERIOD, MAX_LOCKUP_PERIOD]
     */
    function lock(uint256 _secondsIncrease)
        external
        onlyTrustedCodehash
        onlyAccountInitialized(msg.sender)
        noPendingMigration
    {
        _finalizeEpoch(newEpoch());
        Account storage account = accounts[msg.sender];
        _processAccount(account, currentEpoch);
        uint256 lockUntil = account.lockUntil;
        uint256 deltaTime;
        if (lockUntil < block.timestamp) {
            //if unlocked, increase from now
            lockUntil = block.timestamp + _secondsIncrease;
            deltaTime = _secondsIncrease;
        } else {
            //if locked, increase from lock until
            lockUntil += _secondsIncrease;
            deltaTime = lockUntil - block.timestamp;
        }
        //checks if the lock time is in range
        if (deltaTime < MIN_LOCKUP_PERIOD || deltaTime > MAX_LOCKUP_PERIOD) {
            revert StakeManager__InvalidLockTime();
        }
        //mints bonus multiplier points for seconds increased
        uint256 bonusMP = _accruedMP(account.balance, _secondsIncrease);

        //update account storage
        account.lockUntil = lockUntil;
        account.maxMP += bonusMP;
        account.totalMP += bonusMP;
        //update global storage
        totalMP += bonusMP;
    }

    /**
     * @notice Release rewards for current epoch and increase epoch to latest epoch.
     */
    function executeEpoch() external noPendingMigration {
        _finalizeEpoch(newEpoch());
    }

    /**
     * @notice Release rewards for current epoch and increase epoch up to _limitEpoch
     * @param _limitEpoch Until what epoch it should be executed
     */
    function executeEpoch(uint256 _limitEpoch) external noPendingMigration {
        if (newEpoch() < _limitEpoch) {
            revert StakeManager__InvalidLimitEpoch();
        }
        _finalizeEpoch(_limitEpoch);
    }

    /**
     * @notice Execute rewards for account until last possible epoch reached
     * @param _vault Referred account
     */
    function executeAccount(address _vault) external onlyAccountInitialized(_vault) {
        if (address(migration) == address(0)) {
            _finalizeEpoch(newEpoch());
        }
        _processAccount(accounts[_vault], currentEpoch);
    }

    /**
     * @notice Execute rewards for account until limit has reached
     * @param _vault Referred account
     * @param _limitEpoch Until what epoch it should be executed
     */
    function executeAccount(address _vault, uint256 _limitEpoch) external onlyAccountInitialized(_vault) {
        if (address(migration) == address(0)) {
            if (newEpoch() < _limitEpoch) {
                revert StakeManager__InvalidLimitEpoch();
            }
            _finalizeEpoch(_limitEpoch);
        }
        _processAccount(accounts[_vault], _limitEpoch);
    }

    /**
     * @notice starts migration to new StakeManager
     * @param _migration new StakeManager
     */
    function startMigration(IStakeManagerUpdated _migration) external onlyOwner noPendingMigration {
        _finalizeEpoch(newEpoch());
        if (address(_migration) == address(this) || address(_migration) == address(0)) {
            revert StakeManager__InvalidMigration();
        }
        migration = _migration;
        REWARD_TOKEN.transfer(address(migration), epochReward());
        EXPIRED_STAKE_STORAGE.transferOwnership(address(_migration));
        migration.migrationInitialize(
            currentEpoch, totalMP, totalStaked, START_TIME, totalMPRate, potentialMP, currentEpochTotalExpiredMP
        );
    }

    /**
     * @notice Transfer current epoch funds for migrated manager
     */
    function transferNonPending() external onlyPendingMigration {
        REWARD_TOKEN.transfer(address(migration), epochReward());
    }

    /**
     * @notice Migrate account to new manager.
     * @param _acceptMigration true if wants to migrate, false if wants to leave
     */
    function migrateTo(bool _acceptMigration)
        internal
        onlyTrustedCodehash
        onlyAccountInitialized(msg.sender)
        onlyPendingMigration
        returns (IStakeManagerUpdated newManager)
    {
        _processAccount(accounts[msg.sender], currentEpoch);
        Account memory account = accounts[msg.sender];
        totalMP -= account.totalMP;
        totalStaked -= account.balance;
        delete accounts[msg.sender];
        migration.migrateFrom(msg.sender, _acceptMigration, account);
        return migration;
    }

    /**
     * @notice Account accepts an update to new contract
     * @return _migrated new manager
     */
    function acceptUpdate() external returns (IStakeManagerUpdated _migrated) {
        return migrateTo(true);
    }

    /**
     * @notice Account leaves contract in case of a contract breach
     * @return _leaveAccepted true if accepted
     */
    function leave() external returns (bool _leaveAccepted) {
        migrateTo(false);
        return true;
    }

    /**
     * @notice Process account until limit has reached
     * @param account Account to process
     * @param _limitEpoch Until what epoch it should be executed
     */
    function _processAccount(Account storage account, uint256 _limitEpoch) private {
        if (_limitEpoch > currentEpoch) {
            revert StakeManager__InvalidLimitEpoch();
        }
        uint256 userReward;
        uint256 userEpoch = account.epoch;
        uint256 mpDifference = account.totalMP;
        while (userEpoch < _limitEpoch) {
            Epoch storage iEpoch = epochs[userEpoch];
            //mint multiplier points to that epoch
            _mintMP(account, getEpochStartTime(userEpoch + 1), iEpoch);
            uint256 userSupply = account.balance + account.totalMP;
            uint256 userEpochReward = Math.mulDiv(userSupply, iEpoch.epochReward, iEpoch.totalSupply);
            userReward += userEpochReward;
            iEpoch.epochReward -= userEpochReward;
            iEpoch.totalSupply -= userSupply;
            if (iEpoch.totalSupply == 0) {
                pendingReward -= iEpoch.epochReward;
                delete epochs[userEpoch];
            }
            userEpoch++;
        }
        account.epoch = userEpoch;
        if (userReward > 0) {
            pendingReward -= userReward;
            REWARD_TOKEN.transfer(account.rewardAddress, userReward);
        }
        if (address(migration) != address(0)) {
            mpDifference = account.totalMP - mpDifference;
            migration.increaseTotalMP(mpDifference);
        }
    }

    /**
     * @notice Mint multiplier points for given account and epoch
     * @param account Account earning multiplier points
     * @param processTime amount of time of multiplier points
     * @param epoch Epoch to increment total supply
     */
    function _mintMP(Account storage account, uint256 processTime, Epoch storage epoch) private {
        uint256 accruedMP = _accruedMP(account.balance, processTime - account.lastMint);
        if (accruedMP + account.totalMP > account.maxMP) {
            accruedMP = account.maxMP - account.totalMP; //how much left to reach cap
        }
        //update storage
        account.lastMint = processTime;
        account.totalMP += accruedMP;
        totalMP += accruedMP;

        //mp estimation
        epoch.potentialMP -= accruedMP;
        potentialMP -= accruedMP;
    }

    /**
     * @notice Returns account balance
     * @param _vault Account address
     * @return _balance account balance
     */
    function getStakedBalance(address _vault) external view returns (uint256 _balance) {
        return accounts[_vault].balance;
    }

    /**
     * @notice Calculates multiplier points to mint for given balance and time
     * @param _balance balance of account
     * @param _deltaTime time difference
     * @return mp multiplier points to mint
     */
    function calculateMP(uint256 _balance, uint256 _deltaTime) public pure returns (uint256 mp) {
        return _accruedMP(_balance, _deltaTime);
    }

    /**
     * @notice Returns total of multiplier points and balance,
     * and the pending MPs that would be minted if all accounts were processed
     * @return _totalSupply current total supply
     */
    function totalSupply() public view override returns (uint256 _totalSupply) {
        return totalMP + totalStaked + potentialMP;
    }

    /**
     * @notice Returns total of multiplier points and balance
     * @return _totalSupply current total supply
     */
    function totalSupplyMinted() public view returns (uint256 _totalSupply) {
        return totalMP + totalStaked;
    }

    /**
     * @notice Returns funds available for current epoch
     * @return _epochReward current epoch reward
     */
    function epochReward() public view override returns (uint256 _epochReward) {
        return REWARD_TOKEN.balanceOf(address(this)) - pendingReward;
    }
}
