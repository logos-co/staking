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
    mapping (address => Account) account;


    constructor() {
        epoch[0].startTime = now();

    }

    function increaseBalance(uint256 _amount, uint256 _time) external {
        accounts[msg.sender].balance += _amount;
        uint256 mp = calcInitialMultiplierPoints(_amount, _time);
        accounts[msg.sender].multiplier += mp;
        multiplierSupply += mp;
        accounts[msg.sender].update = now();
        accounts[msg.sender].lockTime = now() + _time;
        mint(msg.sender, _amount);
    }

    function decreaseBalance(uint256 _amount) external {
        accounts[msg.sender].balance -= _amount;
        accounts[msg.sender].multiplier -= calcInitialMultiplierPoints(_amount, 1);
        burn(msg.sender, _amount);
    }


    function balanceLock(uint256 _time) external {
        require(now() + _time > accounts[msg.sender].lockTime, "Cannot decrease lock time");
        accounts[msg.sender].lockTime =  now() + _time;
    }

    /**
     * @dev Function called to increase the Multiplier Points of a Vault
     * @param _vault 
     */
    function mintMultiplierPoints(address _vault) external {
        uint256 dT = now() - accounts[msg.sender].update; 
        accounts[msg.sender].update = now();
        uint256 mp = calcAccuredMultiplierPoints(accounts[_vault].balance, accounts[_vault].multiplier, dT);
        multiplierSupply += mp;
        accounts[_vault].multiplier += mp;
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
        uint256 userReward;
        require(_limitEpoch <= currentEpoch, "Epoch not reached");
        uint256 userEpoch = account[_vault].epoch
        require(_limitEpoch > userEpoch, "Epoch already claimed");

        uint256 totalShare = this.totalSupply + this.multiplierSupply;
        uint256 userShare = accounts[_vault].balance + accounts[_vault].multiplier;
        uint256 userRatio = userShare / totalShare; //TODO: might lose precision, multiply by 100 and divide back later?

        for (; userEpoch < _limitEpoch; userEpoch++) {
            userReward += userRatio * epoch[epoch].totalReward;
        }
        account[_vault].epoch = userEpoch;
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