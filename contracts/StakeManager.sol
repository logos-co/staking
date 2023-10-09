// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { StakeVault } from "./StakeVault.sol";

contract StakeManager is Ownable {
    error StakeManager__SenderIsNotVault();
    error StakeManager__FundsLocked();

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
    uint256 public constant MP_APY = 1;
    uint256 public constant MAX_BOOST = 4;

    mapping(address => Account) accounts;
    mapping(uint256 => Epoch) epochs;
    mapping(bytes32 => bool) isVault;

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

    constructor(address _stakedToken, address _oldManager) {
        epochs[0].startTime = block.timestamp;
        oldManager = StakeManager(_oldManager);
        stakedToken = ERC20(_stakedToken);
    }

    /**
     * Increases balance of msg.sender;
     * @param _amount Amount of balance to be decreased.
     * @param _time Seconds from block.timestamp to lock balance.
     */
    function stake(uint256 _amount, uint256 _time) external onlyVault {
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
    function unstake(uint256 _amount) external onlyVault {
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
     */
    function lock(uint256 _time) external onlyVault {
        Account storage account = accounts[msg.sender];
        processAccount(account, currentEpoch);
        require(block.timestamp + _time > account.lockUntil, "Cannot decrease lock time");
        mintIntialMultiplier(account, _time, account.balance, 0);
    }

    /**
     * @notice leave without processing account
     */
    function leave() external onlyVault {
        require(address(migration) != address(0), "Leave only during migration");
        Account memory account = accounts[msg.sender];
        delete accounts[msg.sender];
        multiplierSupply -= account.multiplier;
        stakeSupply -= account.balance;
    }

    /**
     * @notice Release rewards for current epoch and increase epoch.
     */
    function executeEpoch() external {
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
     * @notice Migrate account to new manager.
     */

    function migrate() external onlyVault returns (StakeManager newManager) {
        require(address(migration) != address(0), "Migration not available");
        Account storage account = accounts[msg.sender];
        stakedToken.approve(address(migration), account.balance);
        migration.migrate(msg.sender, account);
        delete accounts[msg.sender];
        return migration;
    }

    /**
     * @dev Only callable from old manager.
     * @notice Migrate account from old manager
     * @param _vault Account address
     * @param _account Account data
     */
    function migrate(address _vault, Account memory _account) external {
        require(msg.sender == address(oldManager), "Unauthorized");
        stakedToken.transferFrom(address(oldManager), address(this), _account.balance);
        accounts[_vault] = _account;
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
        if (block.timestamp >= epochEnd()) {
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
        require(address(migration) == address(0), "Contract ended, please migrate");
        require(_limitEpoch <= currentEpoch, "Non-sense call");
        uint256 userReward;
        uint256 userEpoch = account.epoch;
        for (Epoch memory iEpoch = epochs[userEpoch]; userEpoch < _limitEpoch; userEpoch++) {
            //mint multipliers to that epoch
            mintMultiplier(account, iEpoch.startTime + EPOCH_SIZE);
            uint256 userSupply = account.balance + account.multiplier;
            uint256 userShare = userSupply / iEpoch.totalSupply; //TODO: might lose precision, multiply by 100 and
                // divide back later?
            userReward += userShare * iEpoch.epochReward;
        }
        account.epoch = userEpoch;
        if (userReward > 0) {
            pendingReward -= userReward;
            stakedToken.transfer(account.rewardAddress, userReward);
        }
        mintMultiplier(account, block.timestamp);
    }

    function mintMultiplier(Account storage account, uint256 processTime) private {
        uint256 deltaTime = processTime - account.lastMint;
        account.lastMint = processTime;
        uint256 increasedMultiplier = calcMaxMultiplierIncrease(
            account.balance * (MP_APY / YEAR * deltaTime), account.multiplier, account.lockUntil, account.balance
        );
        account.multiplier += increasedMultiplier;
        multiplierSupply += increasedMultiplier;
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
