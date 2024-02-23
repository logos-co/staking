// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { StakeVault } from "./StakeVault.sol";

contract StakeManager is Ownable {
    error StakeManager__SenderIsNotVault();
    error StakeManager__FundsLocked();
    error StakeManager__InvalidLockTime();
    error StakeManager__NoPendingMigration();
    error StakeManager__PendingMigration();
    error StakeManager__SenderIsNotPreviousStakeManager();
    error StakeManager__InvalidLimitEpoch();
    error StakeManager__InvalidLockupPeriod();
    error StakeManager__AccountNotInitialized();
    error StakeManager__InvalidMigration();

    struct Account {
        address rewardAddress;
        uint256 balance;
        uint256 initialMP;
        uint256 currentMP;
        uint256 lastMint;
        uint256 lockUntil;
        uint256 epoch;
    }

    struct Epoch {
        uint256 startTime;
        uint256 epochReward;
        uint256 totalSupply;
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
    uint256 public totalSupplyMP;
    uint256 public totalSupplyBalance;
    StakeManager public migration;
    StakeManager public immutable oldManager;
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

    modifier onlyInitialized(address account) {
        if (accounts[account].lockUntil == 0) {
            revert StakeManager__AccountNotInitialized();
        }
        _;
    }

    /**
     * @notice Only callable when migration is not initialized.
     */
    modifier noMigration() {
        if (address(migration) != address(0)) {
            revert StakeManager__PendingMigration();
        }
        _;
    }

    /**
     * @notice Only callable when migration is initialized.
     */
    modifier onlyMigration() {
        if (address(migration) == address(0)) {
            revert StakeManager__NoPendingMigration();
        }
        _;
    }

    /**
     * @notice Only callable from old manager.
     */
    modifier onlyOldManager() {
        if (msg.sender != address(oldManager)) {
            revert StakeManager__SenderIsNotPreviousStakeManager();
        }
        _;
    }

    /**
     * @notice Process epoch if it has ended
     */
    modifier processEpoch() {
        if (block.timestamp >= epochEnd() && address(migration) == address(0)) {
            //finalize current epoch
            epochs[currentEpoch].epochReward = epochReward();
            epochs[currentEpoch].totalSupply = totalSupply();
            pendingReward += epochs[currentEpoch].epochReward;
            //create new epoch
            currentEpoch++;
            epochs[currentEpoch].startTime = block.timestamp;
        }
        _;
    }

    constructor(address _stakedToken, address _oldManager) {
        epochs[0].startTime = block.timestamp;
        oldManager = StakeManager(_oldManager);
        stakedToken = ERC20(_stakedToken);
    }

    /**
     * Increases balance of msg.sender;
     * @param _amount Amount of balance to be decreased.
     * @param _time Seconds from block.timestamp to lock balance.
     *
     * @dev Reverts when `_time` is not in range of [MIN_LOCKUP_PERIOD, MAX_LOCKUP_PERIOD]
     */
    function stake(uint256 _amount, uint256 _time) external onlyVault noMigration processEpoch {
        if (_time > 0 && (_time < MIN_LOCKUP_PERIOD || _time > MAX_LOCKUP_PERIOD)) {
            revert StakeManager__InvalidLockupPeriod();
        }
        Account storage account = accounts[msg.sender];
        if (account.lockUntil == 0) {
            // account not initialized
            account.lockUntil = block.timestamp;
            account.epoch = currentEpoch + 1; //starts next epoch
            account.rewardAddress = StakeVault(msg.sender).owner();
        } else {
            _processAccount(account, currentEpoch);
        }
        _mintIntialMP(account, _time, _amount);
        //update storage
        totalSupplyBalance += _amount;
        account.balance += _amount;
        account.lockUntil += _time;
    }

    /**
     * leaves the staking pool and withdraws all funds;
     */
    function unstake(uint256 _amount) external onlyVault onlyInitialized(msg.sender) noMigration processEpoch {
        Account storage account = accounts[msg.sender];
        if (_amount > account.balance) {
            revert("StakeManager: Amount exceeds balance");
        }
        if (account.lockUntil > block.timestamp) {
            revert StakeManager__FundsLocked();
        }
        _processAccount(account, currentEpoch);

        uint256 reducedMP = ((_amount * account.currentMP) / account.balance); //TODO: fix precision loss
        uint256 reducedInitialMP = ((_amount * account.initialMP) / account.balance); //TODO: fix precision loss

        //update storage
        account.balance -= _amount;
        account.initialMP -= reducedInitialMP;
        account.currentMP -= reducedMP;
        totalSupplyBalance -= _amount;
        totalSupplyMP -= reducedMP;
    }

    /**
     * @notice Locks entire balance for more amount of time.
     * @param _time amount of time to lock from now.
     *
     * @dev Reverts when `_time` is bigger than `MAX_LOCKUP_PERIOD`
     * @dev Reverts when `_time + block.timestamp` is smaller than current lock time.
     */
    function lock(uint256 _time) external onlyVault onlyInitialized(msg.sender) noMigration processEpoch {
        if (_time > MAX_LOCKUP_PERIOD) {
            revert StakeManager__InvalidLockupPeriod();
        }
        Account storage account = accounts[msg.sender];
        _processAccount(account, currentEpoch);
        if (account.lockUntil + _time < block.timestamp) {
            revert StakeManager__InvalidLockTime();
        }
        _mintIntialMP(account, _time, 0);
        //update account storage
        account.lockUntil += _time;
    }

    /**
     * @notice Release rewards for current epoch and increase epoch.
     * @dev only executes the prerequisite modifier processEpoch
     */
    function executeEpoch() external noMigration processEpoch {
        return; //see modifier processEpoch
    }

    /**
     * @notice Execute rewards for account until limit has reached
     * @param _vault Referred account
     * @param _limitEpoch Until what epoch it should be executed
     */
    function executeAccount(address _vault, uint256 _limitEpoch) external onlyInitialized(_vault) processEpoch {
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
    function startMigration(StakeManager _migration) external onlyOwner noMigration processEpoch {
        if (_migration == this || address(_migration) == address(0)) {
            revert StakeManager__InvalidMigration();
        }
        migration = _migration;
        stakedToken.transfer(address(migration), epochReward());
        migration.migrationInitialize(currentEpoch, totalSupplyMP, totalSupplyBalance, epochs[currentEpoch].startTime);
    }

    /**
     * @dev Callable automatically from old StakeManager.startMigration(address)
     * @notice Initilizes migration process
     * @param _currentEpoch epoch of old manager
     * @param _totalSupplyMP MP supply on old manager
     * @param _totalSupplyBalance stake supply on old manager
     * @param _epochStartTime epoch start time of old manager
     */
    function migrationInitialize(
        uint256 _currentEpoch,
        uint256 _totalSupplyMP,
        uint256 _totalSupplyBalance,
        uint256 _epochStartTime
    )
        external
        onlyOldManager
    {
        currentEpoch = _currentEpoch;
        totalSupplyMP = _totalSupplyMP;
        totalSupplyBalance = _totalSupplyBalance;
        epochs[currentEpoch].startTime = _epochStartTime;
    }

    /**
     * @notice Transfer current epoch funds for migrated manager
     */
    function transferNonPending() external onlyMigration {
        stakedToken.transfer(address(migration), epochReward());
    }

    /**
     * @notice Migrate account to new manager.
     * @param _acceptMigration true if wants to migrate, false if wants to leave
     */
    function migrateTo(bool _acceptMigration)
        external
        onlyVault
        onlyInitialized(msg.sender)
        onlyMigration
        processEpoch
        returns (StakeManager newManager)
    {
        _processAccount(accounts[msg.sender], currentEpoch);
        Account memory account = accounts[msg.sender];
        totalSupplyMP -= account.currentMP;
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
    function migrateFrom(address _vault, bool _acceptMigration, Account memory _account) external onlyOldManager {
        if (_acceptMigration) {
            accounts[_vault] = _account;
        } else {
            totalSupplyMP -= _account.currentMP;
            totalSupplyBalance -= _account.balance;
        }
    }

    /**
     * @dev Only callable from old manager.
     * @notice Increase total MP from old manager
     * @param _increasedMP amount MP increased on account after migration initialized
     */
    function increaseMPFromMigration(uint256 _increasedMP) external onlyOldManager {
        totalSupplyMP += _increasedMP;
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
        uint256 mpDifference = account.currentMP;
        for (Epoch storage iEpoch = epochs[userEpoch]; userEpoch < _limitEpoch; userEpoch++) {
            //mint multiplier points to that epoch
            _mintMP(account, iEpoch.startTime + EPOCH_SIZE, iEpoch);
            uint256 userSupply = account.balance + account.currentMP;
            uint256 userShare = userSupply / iEpoch.totalSupply; //TODO: fix precision loss;
            uint256 userEpochReward = userShare * iEpoch.epochReward;
            userReward += userEpochReward;
            iEpoch.epochReward -= userEpochReward;
            iEpoch.totalSupply -= userSupply;
        }
        account.epoch = userEpoch;
        if (userReward > 0) {
            pendingReward -= userReward;
            stakedToken.transfer(account.rewardAddress, userReward);
        }
        mpDifference = account.currentMP - mpDifference;
        if (address(migration) != address(0)) {
            migration.increaseMPFromMigration(mpDifference);
        } else if (userEpoch == currentEpoch) {
            _mintMP(account, block.timestamp, epochs[currentEpoch]);
        }
    }

    /**
     * @notice Mint initial multiplier points for given balance and time
     * @dev if increased balance, increases difference of increased balance for current remaining lock time
     * @dev if increased lock time, increases difference of total new balance for increased lock time
     * @param account Account to mint multiplier points
     * @param increasedLockTime increased lock time
     * @param increasedBalance increased balance
     */
    function _mintIntialMP(Account storage account, uint256 increasedLockTime, uint256 increasedBalance) private {
        uint256 increasedMP;
        if (increasedBalance > 0) {
            increasedMP += increasedBalance; //initial multiplier points
            if (block.timestamp < account.lockUntil) {
                //increasing balance on locked account?
                //bonus for remaining previously locked time of new balance.
                increasedMP += _getIncreasedMP(increasedBalance, account.lockUntil - block.timestamp);
            }
        }
        if (increasedLockTime > 0) {
            //bonus for increased lock time
            increasedMP += _getIncreasedMP(account.balance + increasedBalance, increasedLockTime);
        }

        //does not check for MAX_BOOST

        //update storage
        totalSupplyMP += increasedMP;
        account.initialMP += increasedMP;
        account.currentMP += increasedMP;
        account.lastMint = block.timestamp;
    }

    /**
     * @notice Mint multiplier points for given account and epoch
     * @param account Account earning multiplier points
     * @param processTime amount of time of multiplier points
     * @param epoch Epoch to increment total supply
     */
    function _mintMP(Account storage account, uint256 processTime, Epoch storage epoch) private {
        uint256 increasedMP = _capMaxMPIncrease( //check for MAX_BOOST
            _getIncreasedMP(account.balance, processTime - account.lastMint),
            account.balance,
            account.initialMP,
            account.currentMP
        );

        //update storage
        account.lastMint = processTime;
        account.currentMP += increasedMP;
        totalSupplyMP += increasedMP;
        epoch.totalSupply += increasedMP;
    }

    /**
     * @notice Calculates maximum multiplier point increase for given balance
     * @param _increasedMP tested value
     * @param _balance balance of account
     * @param _currentMP current multiplier point of the account
     * @param _initialMP initial multiplier point of the account
     * @return _maxToIncrease maximum multiplier point increase
     */
    function _capMaxMPIncrease(
        uint256 _increasedMP,
        uint256 _balance,
        uint256 _initialMP,
        uint256 _currentMP
    )
        private
        pure
        returns (uint256 _maxToIncrease)
    {
        // Maximum multiplier point for given balance
        _maxToIncrease = _getIncreasedMP(_balance, MAX_BOOST * YEAR) + _initialMP;
        if (_increasedMP + _currentMP > _maxToIncrease) {
            //reached cap when increasing MP
            return _maxToIncrease - _currentMP; //how much left to reach cap
        } else {
            //not reached capw hen increasing MP
            return _increasedMP; //just return tested value
        }
    }

    /**
     * @notice Calculates increased multiplier points for given balance and time
     * @param _balance balance of account
     * @param _deltaTime time difference
     * @return _increasedMP increased multiplier points
     */
    function _getIncreasedMP(uint256 _balance, uint256 _deltaTime) private pure returns (uint256 _increasedMP) {
        return _balance * ((_deltaTime / YEAR) * MP_APY); //TODO: fix precision loss
    }

    /**
     * @notice Returns total of multiplier points and balance
     * @return _totalSupply current total supply
     */
    function totalSupply() public view returns (uint256 _totalSupply) {
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
        return epochs[currentEpoch].startTime + EPOCH_SIZE;
    }
}
