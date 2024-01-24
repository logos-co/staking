// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { StakeVault } from "./StakeVault.sol";

contract StakeManager is Ownable {
    error StakeManager__SenderIsNotVault();
    error StakeManager__FundsLocked();
    error StakeManager__DecreasingLockTime();
    error StakeManager__NoPendingMigration();
    error StakeManager__PendingMigration();
    error StakeManager__SenderIsNotPreviousStakeManager();
    error StakeManager__InvalidLimitEpoch();
    error StakeManager__InvalidLockupPeriod();

    struct Account {
        uint256 lockUntil;
        uint256 balance;
        uint256 multiplier;
        uint256 lastMint;
        uint256 epoch;
        address rewardAddress;
    }

    struct Epoch {
        uint256 startTime;
        uint256 epochReward;
        uint256 totalSupply;
    }

    uint256 public constant EPOCH_SIZE = 1 weeks;
    uint256 public constant YEAR = 365 days;
    uint256 public constant MIN_LOCKUP_PERIOD = 12 weeks; // 3 months
    uint256 public constant MAX_LOCKUP_PERIOD = 4 * YEAR; // 4 years
    uint256 public constant MP_APY = 1;
    uint256 public constant MAX_BOOST = 4;

    mapping(address => Account) public accounts;
    mapping(uint256 => Epoch) epochs;
    mapping(bytes32 => bool) public isVault;

    uint256 public currentEpoch;
    uint256 public pendingReward;
    uint256 public multiplierSupply;
    uint256 public stakeSupply;
    StakeManager public migration;
    StakeManager public immutable oldManager;
    ERC20 public immutable stakedToken;

    modifier onlyVault() {
        if (!isVault[msg.sender.codehash]) {
            revert StakeManager__SenderIsNotVault();
        }
        _;
    }

    modifier noMigration() {
        if (address(migration) != address(0)) {
            revert StakeManager__PendingMigration();
        }
        _;
    }

    modifier onlyMigration() {
        if (address(migration) == address(0)) {
            revert StakeManager__NoPendingMigration();
        }
        _;
    }

    modifier onlyOldManager() {
        if (msg.sender != address(oldManager)) {
            revert StakeManager__SenderIsNotPreviousStakeManager();
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
    function stake(uint256 _amount, uint256 _time) external onlyVault noMigration {
        if (_time > 0 && (_time < MIN_LOCKUP_PERIOD || _time > MAX_LOCKUP_PERIOD)) {
            revert StakeManager__InvalidLockupPeriod();
        }
        Account storage account = accounts[msg.sender];
        processAccount(account, currentEpoch);
        account.balance += _amount;
        account.rewardAddress = StakeVault(msg.sender).owner();
        mintIntialMultiplier(account, _time, _amount, 1);
        stakeSupply += _amount;
    }

    /**
     * Decreases balance of msg.sender;
     * @param _amount Amount of balance to be decreased
     */
    function unstake(uint256 _amount) external onlyVault noMigration {
        Account storage account = accounts[msg.sender];
        if (account.lockUntil > block.timestamp) {
            revert StakeManager__FundsLocked();
        }
        processAccount(account, currentEpoch);
        uint256 reducedMultiplier = (_amount * account.multiplier) / account.balance;
        account.multiplier -= reducedMultiplier;
        account.balance -= _amount;
        multiplierSupply -= reducedMultiplier;
        stakeSupply -= _amount;
    }

    /**
     * @notice Locks entire balance for more amount of time.
     * @param _time amount of time to lock from now.
     *
     * @dev Reverts when `_time` is bigger than `MAX_LOCKUP_PERIOD`
     * @dev Reverts when `_time + block.timestamp` is smaller than current lock time.
     */
    function lock(uint256 _time) external onlyVault noMigration {
        if (_time > MAX_LOCKUP_PERIOD) {
            revert StakeManager__InvalidLockupPeriod();
        }
        Account storage account = accounts[msg.sender];
        processAccount(account, currentEpoch);
        if (block.timestamp + _time < account.lockUntil) {
            revert StakeManager__DecreasingLockTime();
        }
        mintIntialMultiplier(account, _time, account.balance, 0);
    }

    /**
     * @notice Release rewards for current epoch and increase epoch.
     */
    function executeEpoch() external noMigration {
        processEpoch();
    }

    /**
     * @notice Execute rewards for account until limit has reached
     * @param _vault Referred account
     * @param _limitEpoch Until what epoch it should be executed
     */
    function executeAccount(address _vault, uint256 _limitEpoch) external {
        processAccount(accounts[_vault], _limitEpoch);
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
    function startMigration(StakeManager _migration) external onlyOwner noMigration {
        processEpoch();
        migration = _migration;
        stakedToken.transfer(address(migration), epochReward());
        migration.migrationInitialize(currentEpoch, multiplierSupply, stakeSupply, epochs[currentEpoch].startTime);
    }

    /**
     * @dev Callable automatically from old StakeManager.startMigration(address)
     * @notice Initilizes migration process
     * @param _currentEpoch epoch of old manager
     * @param _multiplierSupply MP supply on old manager
     * @param _stakeSupply stake supply on old manager
     * @param _epochStartTime epoch start time of old manager
     */
    function migrationInitialize(
        uint256 _currentEpoch,
        uint256 _multiplierSupply,
        uint256 _stakeSupply,
        uint256 _epochStartTime
    )
        external
        onlyOldManager
    {
        currentEpoch = _currentEpoch;
        multiplierSupply = _multiplierSupply;
        stakeSupply = _stakeSupply;
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
    function migrateTo(bool _acceptMigration) external onlyVault onlyMigration returns (StakeManager newManager) {
        processAccount(accounts[msg.sender], currentEpoch);
        Account memory account = accounts[msg.sender];
        multiplierSupply -= account.multiplier;
        stakeSupply -= account.balance;
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
            multiplierSupply -= _account.multiplier;
            stakeSupply -= _account.balance;
        }
    }
    /**
     * @dev Only callable from old manager.
     * @notice Increase total MP from old manager
     * @param _increasedMP amount MP increased on account after migration initialized
     */

    function increaseMPFromMigration(uint256 _increasedMP) external onlyOldManager {
        multiplierSupply += _increasedMP;
    }

    function calcMaxMultiplierIncrease(
        uint256 _increasedMultiplier,
        uint256 _currentMp,
        uint256 _lockUntil,
        uint256 _stake
    )
        private
        view
        returns (uint256 _maxToIncrease)
    {
        uint256 newMp = _increasedMultiplier + _currentMp;
        if (block.timestamp > _lockUntil) {
            //not locked, limit to max_boost
            return newMp > _stake * MAX_BOOST ? _stake * MAX_BOOST - _currentMp : _increasedMultiplier;
        } else {
            // locked, ignore cap
            return _increasedMultiplier;
        }
    }

    function processEpoch() private {
        if (block.timestamp >= epochEnd() && address(migration) == address(0)) {
            //finalize current epoch
            epochs[currentEpoch].epochReward = epochReward();
            epochs[currentEpoch].totalSupply = totalSupply();
            pendingReward += epochs[currentEpoch].epochReward;
            //create new epoch
            currentEpoch++;
            epochs[currentEpoch].startTime = block.timestamp;
        }
    }

    function processAccount(Account storage account, uint256 _limitEpoch) private {
        processEpoch();
        if (_limitEpoch > currentEpoch) {
            revert StakeManager__InvalidLimitEpoch();
        }
        uint256 userReward;
        uint256 userEpoch = account.epoch;
        for (Epoch storage iEpoch = epochs[userEpoch]; userEpoch < _limitEpoch; userEpoch++) {
            //mint multipliers to that epoch
            mintMultiplier(account, iEpoch.startTime + EPOCH_SIZE, iEpoch);
            uint256 userSupply = account.balance + account.multiplier;
            uint256 userShare = (userSupply / iEpoch.totalSupply) * 100;
            uint256 userEpochReward = (userShare * iEpoch.epochReward) / 100;
            userReward += userEpochReward;
            iEpoch.epochReward -= userEpochReward;
            iEpoch.totalSupply -= userSupply;
        }
        account.epoch = userEpoch;
        if (userReward > 0) {
            pendingReward -= userReward;
            stakedToken.transfer(account.rewardAddress, userReward);
        }
        if (userEpoch == currentEpoch && address(migration) == address(0)) {
            mintMultiplier(account, block.timestamp, epochs[currentEpoch]);
        }
    }

    function mintMultiplier(Account storage account, uint256 processTime, Epoch storage epoch) private {
        uint256 deltaTime = processTime - account.lastMint;
        account.lastMint = processTime;
        uint256 increasedMultiplier = calcMaxMultiplierIncrease(
            account.balance * ((MP_APY / YEAR) * deltaTime), account.multiplier, account.lockUntil, account.balance
        );
        account.multiplier += increasedMultiplier;
        multiplierSupply += increasedMultiplier;
        epoch.totalSupply += increasedMultiplier;
        if (address(migration) != address(0)) {
            migration.increaseMPFromMigration(increasedMultiplier);
        }
    }

    function mintIntialMultiplier(
        Account storage account,
        uint256 lockTime,
        uint256 amount,
        uint256 initMint
    )
        private
    {
        //if balance still locked, multipliers must be minted from difference of time.
        uint256 dT = account.lockUntil > block.timestamp ? block.timestamp + lockTime - account.lockUntil : lockTime;
        account.lockUntil = block.timestamp + lockTime;
        uint256 increasedMultiplier = amount * ((dT / YEAR) + initMint);
        account.lastMint = block.timestamp;
        increasedMultiplier = account.multiplier + increasedMultiplier > (account.balance * (MAX_BOOST + (dT / YEAR)))
            ? account.balance * (MAX_BOOST + (dT / YEAR)) - account.multiplier
            : increasedMultiplier; // checks if MPs are within (lock_time_in_years+MAX_BOOST)*stake
        multiplierSupply += increasedMultiplier;
        account.multiplier += increasedMultiplier;
    }

    function totalSupply() public view returns (uint256) {
        return multiplierSupply + stakeSupply;
    }

    function epochReward() public view returns (uint256) {
        return stakedToken.balanceOf(address(this)) - pendingReward;
    }

    function epochEnd() public view returns (uint256) {
        return epochs[currentEpoch].startTime + EPOCH_SIZE;
    }
}
