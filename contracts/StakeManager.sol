// SPDX-License-Identifier: MIT

pragma solidity 0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract StakeManager is Ownable {

    struct Account {
        uint256 lockUntil;
        uint256 balance;
        uint256 multiplier;
        uint256 lastAccured;
        uint256 epoch;
    }

    struct Epoch {
        uint256 startTime;
        uint256 totalReward;    
    }

    uint256 public constant EPOCH_SIZE = 1 weeks;
    uint256 public constant MP_APY = 1; 
    uint256 public constant STAKE_APY = 1; 
    uint256 public constant MAX_BOOST = 1; 
    uint256 public constant MAX_MP = 1; 

    mapping (address => Account) accounts;
    mapping (uint256 => Epoch) epoch;
    mapping (bytes32 => bool) isVault;

    
    uint256 currentEpoch;
    uint256 pendingReward;
    uint256 public multiplierSupply;
    uint256 public totalSupply;
    StakeManager public migration;
    StakeManager public immutable oldManager;
    ERC20 public immutable stakedToken;
    modifier onlyVault {
        require(isVault[msg.sender.codehash], "Not a vault");
        _;
    }

    constructor(ERC20 _stakedToken, StakeManager _oldManager) Ownable()  {
        epoch[0].startTime = block.timestamp;
        oldManager = _oldManager;
        stakedToken = _stakedToken;
    }

    /**
     * Increases balance of msg.sender;
     * @param _amount Amount of balance to be decreased.
     * @param _time Seconds from block.timestamp to lock balance.
     */
    function join(uint256 _amount, uint256 _time) external {
        Account storage account = accounts[msg.sender];
        uint256 increasedMultiplier = _amount * (_time + 1);
        account.balance += _amount;
        account.multiplier += increasedMultiplier;
        account.lastAccured = block.timestamp;
        account.lockUntil = block.timestamp + _time;

        multiplierSupply += increasedMultiplier;
        totalSupply += _amount;
    }

    /**
     * Decreases balance of msg.sender;
     * @param _amount Amount of balance to be decreased
     */
    function leave(uint256 _amount) external {
        Account storage account = accounts[msg.sender];
        uint256 reducedMultiplier = (_amount * account.multiplier) / account.balance;
        account.multiplier -= reducedMultiplier;
        account.balance -= _amount;

        multiplierSupply -= reducedMultiplier;
        totalSupply -= _amount;
    }

    /**
     * @notice Locks entire balance for more amount of time.
     * @param _time amount of time to lock from now.
     */
    function lock(uint256 _time) external {
        Account storage account = accounts[msg.sender];
        require(block.timestamp + _time > account.lockUntil, "Cannot decrease lock time");

        //if balance still locked, multipliers must be minted from difference of time.
        uint256 dT = account.lockUntil > block.timestamp ? block.timestamp + _time - account.lockUntil : _time; 
        account.lockUntil =  block.timestamp + _time;
        uint256 increasedMultiplier = account.balance * dT;

        account.multiplier += increasedMultiplier;
        multiplierSupply += increasedMultiplier;
    }

    /**
     * @notice Increase the multiplier points of an account
     * @param _vault Referring account 
     */
    function mintMultiplierPoints(address _vault) external {
        Account storage account = accounts[msg.sender];
        uint256 lastCall = block.timestamp - account.lastAccured; 
        uint256 increasedMultiplier = checkMaxMultiplier(
            account.balance * (MP_APY * lastCall),  
            account.multiplier);
        account.lastAccured = block.timestamp;
        account.multiplier += increasedMultiplier;
        multiplierSupply += increasedMultiplier;
    }

    /**
     * @notice Release rewards for current epoch and increase epoch.
     */
    function executeEpochReward() external {
        if(block.timestamp > epoch[currentEpoch].startTime + EPOCH_SIZE){
            uint256 epochReward = stakedToken.balanceOf(address(this)) - pendingReward;
            epoch[currentEpoch].totalReward = epochReward;
            pendingReward += epochReward;
            currentEpoch++;
            epoch[currentEpoch].startTime = block.timestamp;
        }

    }

    /**
     * @notice Execute rewards for account until limit has reached
     * @param _vault Referred account
     * @param _limitEpoch Until what epoch it should be executed
     */
    function executeUserReward(address _vault, uint256 _limitEpoch) external {
        Account storage account = accounts[msg.sender];
        uint256 userReward;
        uint256 userEpoch = account.epoch;
        require(_limitEpoch <= currentEpoch, "Epoch not reached");
        require(_limitEpoch > userEpoch, "Epoch already claimed");
        uint256 totalShare = totalSupply + multiplierSupply;
        uint256 userShare = account.balance + account.multiplier;
        uint256 userRatio = userShare / totalShare; //TODO: might lose precision, multiply by 100 and divide back later?
        for (; userEpoch < _limitEpoch; userEpoch++) {
            userReward += userRatio * epoch[userEpoch].totalReward;
        }
        account.epoch = userEpoch;
        pendingReward -= userReward;
        stakedToken.transfer(_vault, userReward);
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
        accounts[_vault] = _account
;    }

    function checkMaxMultiplier(uint256 _increasedMultiplier, uint256 _currentMp) private view returns(uint256 _maxToIncrease) {
        uint256 newMp = _increasedMultiplier + _currentMp;
        return newMp > MAX_MP ? MAX_MP - newMp : _increasedMultiplier;
    }

}