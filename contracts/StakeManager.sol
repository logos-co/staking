// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

import { StakeVault } from "./StakeVault.sol";

contract StakeRewardEstimate is Ownable {
    mapping(uint256 epochId => uint256 balance) public expiredMPPerEpoch;

    function getExpiredMP(uint256 epochId) public view returns (uint256) {
        return expiredMPPerEpoch[epochId];
    }

    function incrementExpiredMP(uint256 epochId, uint256 amount) public onlyOwner {
        expiredMPPerEpoch[epochId] += amount;
    }

    function decrementExpiredMP(uint256 epochId, uint256 amount) public onlyOwner {
        expiredMPPerEpoch[epochId] -= amount;
    }

    function deleteExpiredMP(uint256 epochId) public onlyOwner {
        delete expiredMPPerEpoch[epochId];
    }
}

contract StakeManager is Ownable {
    error StakeManager__SenderIsNotVault();
    error StakeManager__FundsLocked();
    error StakeManager__InvalidLockTime();
    error StakeManager__NoPendingMigration();
    error StakeManager__PendingMigration();
    error StakeManager__SenderIsNotPreviousStakeManager();
    error StakeManager__InvalidLimitEpoch();
    error StakeManager__AccountNotInitialized();
    error StakeManager__InvalidMigration();
    error StakeManager__AlreadyProcessedEpochs();
    error StakeManager__InsufficientFunds();
    error StakeManager__AlreadyStaked();
    error StakeManager__StakeIsTooLow();

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
        uint256 startTime;
        uint256 epochReward;
        uint256 totalSupply;
        uint256 estimatedMP;
    }

    uint256 public constant EPOCH_SIZE = 1 weeks;
    uint256 public constant YEAR = 365 days;
    uint256 public constant MIN_LOCKUP_PERIOD = 2 weeks;
    uint256 public constant MAX_LOCKUP_PERIOD = 4 * YEAR; // 4 years
    uint256 public constant MP_APY = 1;
    uint256 public constant MAX_BOOST = 4;

    mapping(address index => Account value) public accounts;
    mapping(uint256 index => Epoch value) public epochs;
    mapping(bytes32 codehash => bool approved) public isVault;

    uint256 public currentEpoch;
    uint256 public pendingReward;
    uint256 public immutable startTime;

    uint256 public pendingMPToBeMinted;
    uint256 public totalSupplyMP;
    uint256 public totalSupplyBalance;
    uint256 public totalMPPerEpoch;

    StakeRewardEstimate public stakeRewardEstimate;

    uint256 public currentEpochTotalExpiredMP;

    StakeManager public migration;
    StakeManager public immutable previousManager;
    ERC20 public immutable stakedToken;

    /**
     * @notice Only callable by vaults
     */
    modifier onlyVault() {
        if (!isVault[msg.sender.codehash]) {
            revert StakeManager__SenderIsNotVault();
        }
        _;
    }

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
            Epoch memory thisEpoch;
            uint256 expiredMP = stakeRewardEstimate.getExpiredMP(tempCurrentEpoch);
            if (expiredMP > 0) {
                totalMPPerEpoch -= expiredMP;
                stakeRewardEstimate.deleteExpiredMP(tempCurrentEpoch);
            }
            thisEpoch.estimatedMP = totalMPPerEpoch - currentEpochTotalExpiredMP;
            delete currentEpochTotalExpiredMP;
            pendingMPToBeMinted += thisEpoch.estimatedMP;

            //finalize current epoch
            if (tempCurrentEpoch == currentEpoch) {
                thisEpoch.epochReward = epochReward();
                pendingReward += thisEpoch.epochReward;
            }
            thisEpoch.totalSupply = totalSupply();
            epochs[tempCurrentEpoch] = thisEpoch;
            //create new epoch
            tempCurrentEpoch++;
        }
        currentEpoch = tempCurrentEpoch;
    }

    constructor(address _stakedToken, address _previousManager) {
        startTime = (_previousManager == address(0)) ? block.timestamp : StakeManager(_previousManager).startTime();
        previousManager = StakeManager(_previousManager);
        stakedToken = ERC20(_stakedToken);
        if (address(previousManager) != address(0)) {
            stakeRewardEstimate = previousManager.stakeRewardEstimate();
        } else {
            stakeRewardEstimate = new StakeRewardEstimate();
        }
    }

    /**
     * Increases balance of msg.sender;
     * @param _amount Amount of balance being staked.
     * @param _secondsToLock Seconds of lockup time. 0 means no lockup.
     *
     * @dev Reverts when resulting locked time is not in range of [MIN_LOCKUP_PERIOD, MAX_LOCKUP_PERIOD]
     * @dev Reverts when account has already staked funds.
     * @dev Reverts when amount staked results in less than 1 MP per epoch.
     */
    function stake(uint256 _amount, uint256 _secondsToLock) external onlyVault noPendingMigration {
        finalizeEpoch(newEpoch());
        Account storage account = accounts[msg.sender];
        if (account.balance > 0 || account.lockUntil != 0) {
            revert StakeManager__AlreadyStaked();
        }
        if (_secondsToLock != 0 && (_secondsToLock < MIN_LOCKUP_PERIOD || _secondsToLock > MAX_LOCKUP_PERIOD)) {
            revert StakeManager__InvalidLockTime();
        }

        //mp estimation
        uint256 mpPerEpoch = _getMPToMint(_amount, EPOCH_SIZE);
        if (mpPerEpoch < 1) {
            revert StakeManager__StakeIsTooLow();
        }
        uint256 currentEpochExpiredMP = mpPerEpoch - _getMPToMint(_amount, epochEnd() - block.timestamp);
        uint256 maxMpToMint = _getMPToMint(_amount, MAX_BOOST * YEAR) + currentEpochExpiredMP;
        uint256 epochAmountToReachMpLimit = (maxMpToMint) / mpPerEpoch;
        uint256 mpLimitEpoch = currentEpoch + epochAmountToReachMpLimit;
        uint256 lastEpochAmountToMint = ((mpPerEpoch * (epochAmountToReachMpLimit + 1)) - maxMpToMint);

        // account initialization
        account.lockUntil = block.timestamp + _secondsToLock;
        account.epoch = currentEpoch; //starts in current epoch
        account.rewardAddress = StakeVault(msg.sender).owner();
        _mintBonusMP(account, _secondsToLock, _amount); //TODO: remove this function competely
        account.balance = _amount;
        account.mpLimitEpoch = mpLimitEpoch;

        //update global storage
        totalSupplyBalance += _amount;
        currentEpochTotalExpiredMP += currentEpochExpiredMP;
        totalMPPerEpoch += mpPerEpoch;
        stakeRewardEstimate.incrementExpiredMP(mpLimitEpoch, lastEpochAmountToMint);
        stakeRewardEstimate.incrementExpiredMP(mpLimitEpoch + 1, mpPerEpoch - lastEpochAmountToMint);
    }

    /**
     * leaves the staking pool and withdraws all funds;
     */
    function unstake(uint256 _amount) external onlyVault onlyAccountInitialized(msg.sender) noPendingMigration {
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

        uint256 mpPerEpoch = _getMPToMint(account.balance, EPOCH_SIZE);
        stakeRewardEstimate.decrementExpiredMP(account.mpLimitEpoch, mpPerEpoch);
        if (account.mpLimitEpoch < currentEpoch) {
            totalMPPerEpoch -= mpPerEpoch;
        }

        //update storage
        account.balance -= _amount;
        account.bonusMP -= reducedInitialMP;
        account.totalMP -= reducedMP;
        totalSupplyBalance -= _amount;
        totalSupplyMP -= reducedMP;
    }

    /**
     * @notice Locks entire balance for more amount of time.
     * @param _secondsToIncreaseLock Seconds to increase in locked time. If stake is unlocked, increases from
     * block.timestamp.
     *
     * @dev Reverts when resulting locked time is not in range of [MIN_LOCKUP_PERIOD, MAX_LOCKUP_PERIOD]
     */
    function lock(uint256 _secondsToIncreaseLock)
        external
        onlyVault
        onlyAccountInitialized(msg.sender)
        noPendingMigration
    {
        finalizeEpoch(newEpoch());
        Account storage account = accounts[msg.sender];
        _processAccount(account, currentEpoch);
        uint256 lockUntil = account.lockUntil;
        uint256 deltaTime;
        if (lockUntil < block.timestamp) {
            lockUntil = block.timestamp + _secondsToIncreaseLock;
            deltaTime = _secondsToIncreaseLock;
        } else {
            lockUntil += _secondsToIncreaseLock;
            deltaTime = lockUntil - block.timestamp;
        }
        if (deltaTime < MIN_LOCKUP_PERIOD || deltaTime > MAX_LOCKUP_PERIOD) {
            revert StakeManager__InvalidLockTime();
        }
        _mintBonusMP(account, _secondsToIncreaseLock, 0);
        //update account storage
        account.lockUntil = lockUntil;
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
     * @notice Enables a contract class to interact with staking functions
     * @param _codehash bytecode hash of contract
     */
    function setVault(bytes32 _codehash) external onlyOwner {
        isVault[_codehash] = true;
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
        stakedToken.transfer(address(migration), epochReward());
        stakeRewardEstimate.transferOwnership(address(_migration));
        migration.migrationInitialize(
            currentEpoch,
            totalSupplyMP,
            totalSupplyBalance,
            startTime,
            totalMPPerEpoch,
            pendingMPToBeMinted,
            currentEpochTotalExpiredMP
        );
    }

    /**
     * @dev Callable automatically from old StakeManager.startMigration(address)
     * @notice Initilizes migration process
     * @param _currentEpoch epoch of old manager
     * @param _totalSupplyMP MP supply on old manager
     * @param _totalSupplyBalance stake supply on old manager
     * @param _startTime start time of old manager
     */
    function migrationInitialize(
        uint256 _currentEpoch,
        uint256 _totalSupplyMP,
        uint256 _totalSupplyBalance,
        uint256 _startTime,
        uint256 _totalMPPerEpoch,
        uint256 _pendingMPToBeMinted,
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
        totalSupplyMP = _totalSupplyMP;
        totalSupplyBalance = _totalSupplyBalance;
        totalMPPerEpoch = _totalMPPerEpoch;
        pendingMPToBeMinted = _pendingMPToBeMinted;
        currentEpochTotalExpiredMP = _currentEpochExpiredMP;
    }

    /**
     * @notice Transfer current epoch funds for migrated manager
     */
    function transferNonPending() external onlyPendingMigration {
        stakedToken.transfer(address(migration), epochReward());
    }

    /**
     * @notice Migrate account to new manager.
     * @param _acceptMigration true if wants to migrate, false if wants to leave
     */
    function migrateTo(bool _acceptMigration)
        external
        onlyVault
        onlyAccountInitialized(msg.sender)
        onlyPendingMigration
        returns (StakeManager newManager)
    {
        _processAccount(accounts[msg.sender], currentEpoch);
        Account memory account = accounts[msg.sender];
        totalSupplyMP -= account.totalMP;
        totalSupplyBalance -= account.balance;
        delete accounts[msg.sender];
        migration.migrateFrom(msg.sender, _acceptMigration, account);
        return migration;
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
            totalSupplyMP -= _account.totalMP;
            totalSupplyBalance -= _account.balance;
        }
    }

    /**
     * @dev Only callable from old manager.
     * @notice Increase total MP from old manager
     * @param _amount amount MP increased on account after migration initialized
     */
    function increaseTotalMP(uint256 _amount) external onlyPreviousManager {
        totalSupplyMP += _amount;
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
            stakedToken.transfer(account.rewardAddress, userReward);
        }
        if (address(migration) != address(0)) {
            mpDifference = account.totalMP - mpDifference;
            migration.increaseTotalMP(mpDifference);
        }
    }

    /**
     * @notice Mint bonus multiplier points for given staking amount and time
     * @dev if amount is greater 0, it increases difference of amount for current remaining lock time
     * @dev if increased lock time, increases difference of total new balance for increased lock time
     * @param account Account to mint multiplier points
     * @param increasedLockTime increased lock time
     * @param amount amount to stake
     */
    function _mintBonusMP(Account storage account, uint256 increasedLockTime, uint256 amount) private {
        uint256 mpToMint;
        if (amount > 0) {
            mpToMint += amount; //initial multiplier points
        }
        if (increasedLockTime > 0) {
            //bonus for increased lock time
            mpToMint += _getMPToMint(account.balance + amount, increasedLockTime);
        }
        //update storage
        totalSupplyMP += mpToMint;
        account.bonusMP += mpToMint;
        account.totalMP += mpToMint;
        account.lastMint = block.timestamp;
    }

    /**
     * @notice Mint multiplier points for given account and epoch
     * @param account Account earning multiplier points
     * @param processTime amount of time of multiplier points
     * @param epoch Epoch to increment total supply
     */
    function _mintMP(Account storage account, uint256 processTime, Epoch storage epoch) private {
        uint256 mpToMint = _getMaxMPToMint(
            _getMPToMint(account.balance, processTime - account.lastMint),
            account.balance,
            account.bonusMP,
            account.totalMP
        );

        //update storage
        account.lastMint = processTime;
        account.totalMP += mpToMint;
        totalSupplyMP += mpToMint;

        //mp estimation
        epoch.estimatedMP -= mpToMint;
        pendingMPToBeMinted -= mpToMint;
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
        _maxMpToMint = _getMPToMint(_balance, MAX_BOOST * YEAR) + _bonusMP;
        if (_mpToMint + _totalMP > _maxMpToMint) {
            //reached cap when increasing MP
            return _maxMpToMint - _totalMP; //how much left to reach cap
        } else {
            //not reached capw hen increasing MP
            return _mpToMint; //just return tested value
        }
    }

    /**
     * @notice Calculates multiplier points to mint for given balance and time
     * @param _balance balance of account
     * @param _deltaTime time difference
     * @return multiplier points to mint
     */
    function _getMPToMint(uint256 _balance, uint256 _deltaTime) private pure returns (uint256) {
        return Math.mulDiv(_balance, _deltaTime, YEAR) * MP_APY;
    }

    /*
     * @notice Calculates multiplier points to mint for given balance and time
     * @param _balance balance of account
     * @param _deltaTime time difference
     * @return multiplier points to mint
     */
    function calculateMPToMint(uint256 _balance, uint256 _deltaTime) public pure returns (uint256) {
        return _getMPToMint(_balance, _deltaTime);
    }

    /**
     * @notice Returns total of multiplier points and balance,
     * and the pending MPs that would be minted if all accounts were processed
     * @return _totalSupply current total supply
     */
    function totalSupply() public view returns (uint256 _totalSupply) {
        return totalSupplyMP + totalSupplyBalance + pendingMPToBeMinted;
    }

    /**
     * @notice Returns total of multiplier points and balance
     * @return _totalSupply current total supply
     */
    function totalSupplyMinted() public view returns (uint256 _totalSupply) {
        return totalSupplyMP + totalSupplyBalance;
    }

    /**
     * @notice Returns funds available for current epoch
     * @return _epochReward current epoch reward
     */
    function epochReward() public view returns (uint256 _epochReward) {
        return stakedToken.balanceOf(address(this)) - pendingReward;
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
