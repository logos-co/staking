// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract StakeManager is ERC20 {

    ERC20 stakedToken;

    uint256 public constant MP_APY = 1; 
    uint256 public constant STAKE_APY = 1; 
    uint256 public constant MAX_BOOST = 1; 
    uint256 public constant MAX_MP = 1; 
    mapping (address => Account) accounts;

    struct Account {
        uint256 lockTime;
        uint256 balance;
        uint256 multiplier;
        uint256 multiplierUpdate;
        uint256 epoch;
    }

    struct Epoch {
        uint256 startTime;
        uint256 totalReward;    
    }

    uint256 currentEpoch;
    uint256 pendingReward;
    
    uint256 public constant EPOCH_SIZE = 1 week;

    mapping (uint256 => Epoch) epoch;
    mapping (address => Account) accounts;


    constructor() {
        epoch[0].startTime = now();

    }

    function increaseBalance(uint256 _amount, uint256 _time) external {
        Account storage account = accounts[msg.sender];
        account.balance += _amount;
        uint256 mp = calcInitialMultiplierPoints(_amount, _time);
        account.multiplier += mp;
        multiplierSupply += mp;
        account.update = now();
        account.lockTime = now() + _time;
        mint(msg.sender, _amount);
    }

    function decreaseBalance(uint256 _amount) external {
        Account storage account = accounts[msg.sender];
        account.balance -= _amount;
        account.multiplier -= calcInitialMultiplierPoints(_amount, 1);
        burn(msg.sender, _amount);
    }


    function balanceLock(uint256 _time) external {
        Account storage account = accounts[msg.sender];
        require(now() + _time > account.lockTime, "Cannot decrease lock time");
        account.lockTime =  now() + _time;
    }

    /**
     * @dev Function called to increase the Multiplier Points of a Vault
     * @param _vault 
     */
    function mintMultiplierPoints(address _vault) external {
        Account storage account = accounts[msg.sender];
        uint256 dT = now() - account.update; 
        account.update = now();
        uint256 mp = calcAccuredMultiplierPoints(account.balance, account.multiplier, dT);
        multiplierSupply += mp;
        account.multiplier += mp;
    }

    function executeEpochReward() external {
        if(now() > epoch[currentEpoch].startTime + EPOCH_SIZE){
            uint256 epochReward = stakedToken.balanceOf(this) - pendingReward;
            epoch[currentEpoch].totalReward = epochReward;
            pendingReward += epochReward;
            currentEpoch++;
            epoch[currentEpoch].startTime = now();
        }

    }

    function executeUserReward(address _vault, uint256 _limitEpoch) external {
        Account storage account = accounts[msg.sender];
        uint256 userReward;
        uint256 userEpoch = account.epoch
        require(_limitEpoch <= currentEpoch, "Epoch not reached");
        require(_limitEpoch > userEpoch, "Epoch already claimed");
        uint256 totalShare = this.totalSupply + this.multiplierSupply;
        uint256 userShare = account.balance + account.multiplier;
        uint256 userRatio = userShare / totalShare; //TODO: might lose precision, multiply by 100 and divide back later?
        for (; userEpoch < _limitEpoch; userEpoch++) {
            userReward += userRatio * epoch[userEpoch].totalReward;
        }
        account.epoch = userEpoch;
        pendingReward -= userReward;
        stakedToken.transfer(_vault, userReward);
    }

    function calcInitialMultiplierPoints(uint256 _amount, uint256 _time) pure public returns(uint256) {
        return _amount * (_time + 1);
    }

    function calcAccuredMultiplierPoints(uint256 _balance, uint256 _currentMp, uint256 _deltaTime) pure public returns(uint256) {
        uint256 accured = _balance * (MP_APY * _deltaTime);
        uint256 newMp = accured + _currentMp;
        return newMp > MAX_MP ? MAX_MP - newMp : accurred;
    }

}