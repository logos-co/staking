// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

import { TrustedCodehashAccess } from "./access/TrustedCodehashAccess.sol";
import { ExpiredStakeStorage } from "./storage/ExpiredStakeStorage.sol";
import { IStakeManager } from "./IStakeManager.sol";
import { MultiplierPointMath } from "./MultiplierPointMath.sol";
import { StakeVault } from "./StakeVault.sol";

contract StakeManager is IStakeManager, MultiplierPointMath, TrustedCodehashAccess {
    error StakeManager__NoPendingMigration();
    error StakeManager__PendingMigration();
    error StakeManager__SenderIsNotPreviousStakeManager();
    error StakeManager__InvalidLimitEpoch();
    error StakeManager__AccountNotInitialized();
    error StakeManager__InvalidMigration();
    error StakeManager__AlreadyProcessedEpochs();
    error StakeManager__AlreadyStaked();

    struct Account {
        address rewardAddress;
        uint256 balance;
        uint256 bonusMP;
        uint256 totalMP;
        uint256 lastMint;
        uint256 lockUntil;
        uint256 epoch;
        uint256 mpLimitEpoch;
    }

    struct Epoch {
        uint256 epochReward;
        uint256 totalSupply;
        uint256 potentialMP;
    }

    uint256 public constant EPOCH_SIZE = 1 weeks;
    uint256 public constant MIN_LOCKUP_PERIOD = 2 weeks;
    uint256 public constant MAX_LOCKUP_PERIOD = 4 * YEAR; // 4 years

    mapping(address index => Account value) public accounts;
    mapping(uint256 index => Epoch value) public epochs;

    uint256 public currentEpoch;
    uint256 public pendingReward;
    uint256 public immutable startTime;

    uint256 public potentialMP;
    uint256 public totalMP;
    uint256 public totalStaked;
    uint256 public totalMPPerEpoch;

    ExpiredStakeStorage public expiredStakeStorage;

    uint256 public currentEpochTotalExpiredMP;

    StakeManager public migration;
    StakeManager public immutable previousManager;
    IERC20 public immutable rewardToken;

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

    /**
     * @notice Only callable from old manager.
     */
    modifier onlyPreviousManager() {
        if (msg.sender != address(previousManager)) {
            revert StakeManager__SenderIsNotPreviousStakeManager();
        }
        _;
    }

    /**
     * @notice Release rewards for current epoch and increase epoch up to _limitEpoch
     * @param _limitEpoch Until what epoch it should be executed
     */
    function finalizeEpoch(uint256 _limitEpoch) private {
        uint256 tempCurrentEpoch = currentEpoch;
        while (tempCurrentEpoch < _limitEpoch) {
            Epoch storage thisEpoch = epochs[tempCurrentEpoch];
            uint256 expiredMP = expiredStakeStorage.getExpiredMP(tempCurrentEpoch);
            if (expiredMP > 0) {
                totalMPPerEpoch -= expiredMP;
                expiredStakeStorage.deleteExpiredMP(tempCurrentEpoch);
            }
            uint256 epochPotentialMP = totalMPPerEpoch;
            if (tempCurrentEpoch == currentEpoch) {
                epochPotentialMP -= currentEpochTotalExpiredMP;
                currentEpochTotalExpiredMP = 0;
                thisEpoch.epochReward = epochReward();
                pendingReward += thisEpoch.epochReward;
            }

            potentialMP += epochPotentialMP;
            thisEpoch.potentialMP = epochPotentialMP;
            thisEpoch.totalSupply = totalSupply();
            tempCurrentEpoch++;
        }
        currentEpoch = tempCurrentEpoch;
    }

    constructor(address _REWARD_TOKEN, address _previousManager) {
        startTime = (_previousManager == address(0)) ? block.timestamp : StakeManager(_previousManager).startTime();
        previousManager = StakeManager(_previousManager);
        rewardToken = IERC20(_REWARD_TOKEN);
        if (address(previousManager) != address(0)) {
            expiredStakeStorage = previousManager.expiredStakeStorage();
        } else {
            expiredStakeStorage = new ExpiredStakeStorage();
        }
    }

    /**
     * Increases balance of msg.sender;
     * @param _amount Amount of balance being staked.
     * @param _seconds Seconds of lockup time. 0 means no lockup.
     *
     * @dev Reverts when resulting locked time is not in range of [MIN_LOCKUP_PERIOD, MAX_LOCKUP_PERIOD]
     * @dev Reverts when account has already staked funds.
     * @dev Reverts when amount staked results in less than 1 MP per epoch.
     */
    function stake(uint256 _amount, uint256 _seconds) external onlyTrustedCodehash noPendingMigration {
        finalizeEpoch(newEpoch());
        if (accounts[msg.sender].balance > 0) {
            revert StakeManager__AlreadyStaked();
        }
        if (_seconds != 0 && (_seconds < MIN_LOCKUP_PERIOD || _seconds > MAX_LOCKUP_PERIOD)) {
            revert StakeManager__InvalidLockTime();
        }

        //mp estimation
        uint256 mpPerEpoch = _calculateAccuredMP(_amount, EPOCH_SIZE);
        if (mpPerEpoch < 1) {
            revert StakeManager__StakeIsTooLow();
        }
        uint256 currentEpochExpiredMP = mpPerEpoch - _calculateAccuredMP(_amount, epochEnd() - block.timestamp);
        uint256 maxMpToMint = _calculateMaxAccuredMP(_amount) + currentEpochExpiredMP;
        uint256 epochAmountToReachMpLimit = (maxMpToMint) / mpPerEpoch;
        uint256 mpLimitEpoch = currentEpoch + epochAmountToReachMpLimit;
        uint256 lastEpochAmountToMint = ((mpPerEpoch * (epochAmountToReachMpLimit + 1)) - maxMpToMint);
        uint256 bonusMP = _calculateBonusMP(_amount, _seconds);

        // account initialization
        accounts[msg.sender] = Account({
            rewardAddress: StakeVault(msg.sender).owner(),
            balance: _amount,
            bonusMP: bonusMP,
            totalMP: bonusMP,
            lastMint: block.timestamp,
            lockUntil: block.timestamp + _seconds,
            epoch: currentEpoch,
            mpLimitEpoch: mpLimitEpoch
        });

        //update global storage
        totalMP += bonusMP;
        totalStaked += _amount;
        currentEpochTotalExpiredMP += currentEpochExpiredMP;
        totalMPPerEpoch += mpPerEpoch;
        expiredStakeStorage.incrementExpiredMP(mpLimitEpoch, lastEpochAmountToMint);
        expiredStakeStorage.incrementExpiredMP(mpLimitEpoch + 1, mpPerEpoch - lastEpochAmountToMint);
    }

    /**
     * leaves the staking pool and withdraws all funds;
     */
    function unstake(uint256 _amount)
        external
        onlyTrustedCodehash
        onlyAccountInitialized(msg.sender)
        noPendingMigration
    {
        finalizeEpoch(newEpoch());
        Account storage account = accounts[msg.sender];
        if (_amount > account.balance) {
            revert StakeManager__InsufficientFunds();
        }
        if (account.lockUntil > block.timestamp) {
            revert StakeManager__FundsLocked();
        }
        _processAccount(account, currentEpoch);

        uint256 reducedMP = Math.mulDiv(_amount, account.totalMP, account.balance);
        uint256 reducedInitialMP = Math.mulDiv(_amount, account.bonusMP, account.balance);

        uint256 mpPerEpoch = _calculateAccuredMP(account.balance, EPOCH_SIZE);
        expiredStakeStorage.decrementExpiredMP(account.mpLimitEpoch, mpPerEpoch);
        if (account.mpLimitEpoch < currentEpoch) {
            totalMPPerEpoch -= mpPerEpoch;
        }

        //update storage
        account.balance -= _amount;
        account.bonusMP -= reducedInitialMP;
        account.totalMP -= reducedMP;
        totalStaked -= _amount;
        totalMP -= reducedMP;
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
        finalizeEpoch(newEpoch());
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
        uint256 bonusMP = _calculateAccuredMP(account.balance, _secondsIncrease);

        //update account storage
        account.lockUntil = lockUntil;
        account.bonusMP += bonusMP;
        account.totalMP += bonusMP;
        //update global storage
        totalMP += bonusMP;
    }

    /**
     * @notice Release rewards for current epoch and increase epoch to latest epoch.
     */
    function executeEpoch() external noPendingMigration {
        finalizeEpoch(newEpoch());
    }

    /**
     * @notice Release rewards for current epoch and increase epoch up to _limitEpoch
     * @param _limitEpoch Until what epoch it should be executed
     */
    function executeEpoch(uint256 _limitEpoch) external noPendingMigration {
        if (newEpoch() < _limitEpoch) {
            revert StakeManager__InvalidLimitEpoch();
        }
        finalizeEpoch(_limitEpoch);
    }

    /**
     * @notice Execute rewards for account until last possible epoch reached
     * @param _vault Referred account
     */
    function executeAccount(address _vault) external onlyAccountInitialized(_vault) {
        if (address(migration) == address(0)) {
            finalizeEpoch(newEpoch());
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
            finalizeEpoch(_limitEpoch);
        }
        _processAccount(accounts[_vault], _limitEpoch);
    }

    /**
     * @notice starts migration to new StakeManager
     * @param _migration new StakeManager
     */
    function startMigration(StakeManager _migration) external onlyOwner noPendingMigration {
        finalizeEpoch(newEpoch());
        if (_migration == this || address(_migration) == address(0)) {
            revert StakeManager__InvalidMigration();
        }
        migration = _migration;
        rewardToken.transfer(address(migration), epochReward());
        expiredStakeStorage.transferOwnership(address(_migration));
        migration.migrationInitialize(
            currentEpoch, totalMP, totalStaked, startTime, totalMPPerEpoch, potentialMP, currentEpochTotalExpiredMP
        );
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
        uint256 _totalMPPerEpoch,
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
        if (_startTime != startTime) {
            revert StakeManager__InvalidMigration();
        }
        currentEpoch = _currentEpoch;
        totalMP = _totalMP;
        totalStaked = _totalStaked;
        totalMPPerEpoch = _totalMPPerEpoch;
        potentialMP = _potentialMP;
        currentEpochTotalExpiredMP = _currentEpochExpiredMP;
    }

    /**
     * @notice Transfer current epoch funds for migrated manager
     */
    function transferNonPending() external onlyPendingMigration {
        rewardToken.transfer(address(migration), epochReward());
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
        returns (StakeManager newManager)
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
    function acceptUpdate() external returns (IStakeManager _migrated) {
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
            _mintMP(account, startTime + (EPOCH_SIZE * (userEpoch + 1)), iEpoch);
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
            rewardToken.transfer(account.rewardAddress, userReward);
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
        uint256 mpToMint = _getMaxMPToMint(
            _calculateAccuredMP(account.balance, processTime - account.lastMint),
            account.balance,
            account.bonusMP,
            account.totalMP
        );

        //update storage
        account.lastMint = processTime;
        account.totalMP += mpToMint;
        totalMP += mpToMint;

        //mp estimation
        epoch.potentialMP -= mpToMint;
        potentialMP -= mpToMint;
    }

    /**
     * @notice Calculates maximum multiplier point increase for given balance
     * @param _mpToMint tested value
     * @param _balance balance of account
     * @param _totalMP total multiplier point of the account
     * @param _bonusMP bonus multiplier point of the account
     * @return _maxMpToMint maximum multiplier points to mint
     */
    function _getMaxMPToMint(
        uint256 _mpToMint,
        uint256 _balance,
        uint256 _bonusMP,
        uint256 _totalMP
    )
        private
        pure
        returns (uint256 _maxMpToMint)
    {
        // Maximum multiplier point for given balance
        _maxMpToMint = _calculateMaxAccuredMP(_balance) + _bonusMP;
        if (_mpToMint + _totalMP > _maxMpToMint) {
            //reached cap when increasing MP
            return _maxMpToMint - _totalMP; //how much left to reach cap
        } else {
            //not reached capw hen increasing MP
            return _mpToMint; //just return tested value
        }
    }

    /**
     * @notice Returns account balance
     * @param _vault Account address
     * @return _balance account balance
     */
    function getStakedBalance(address _vault) external view returns (uint256 _balance) {
        return accounts[_vault].balance;
    }

    /*
     * @notice Calculates multiplier points to mint for given balance and time
     * @param _balance balance of account
     * @param _deltaTime time difference
     * @return multiplier points to mint
     */
    function calculateMP(uint256 _balance, uint256 _deltaTime) public pure returns (uint256) {
        return _calculateAccuredMP(_balance, _deltaTime);
    }

    /**
     * @notice Returns total of multiplier points and balance,
     * and the pending MPs that would be minted if all accounts were processed
     * @return _totalSupply current total supply
     */
    function totalSupply() public view returns (uint256 _totalSupply) {
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
    function epochReward() public view returns (uint256 _epochReward) {
        return rewardToken.balanceOf(address(this)) - pendingReward;
    }

    /**
     * @notice Returns end time of current epoch
     * @return _epochEnd end time of current epoch
     */
    function epochEnd() public view returns (uint256 _epochEnd) {
        return startTime + (EPOCH_SIZE * (currentEpoch + 1));
    }

    /**
     * @notice Returns the last epoch that can be processed on current time
     * @return _newEpoch the number of the epoch after all epochs that can be processed
     */
    function newEpoch() public view returns (uint256 _newEpoch) {
        _newEpoch = (block.timestamp - startTime) / EPOCH_SIZE;
    }
}
