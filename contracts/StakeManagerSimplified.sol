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
    }

    mapping (address => Account) account;


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

    function calcInitialMultiplierPoints(uint256 _amount, uint256 _time) pure public returns(uint256) {
        return _amount * (_time + 1);
    }

    function calcAccuredMultiplierPoints(uint256 _balance, uint256 _currentMp, uint256 _deltaTime) pure public returns(uint256) {
        uint256 accured = _balance * (MP_APY * _deltaTime);
        uint256 newMp = accured + _currentMp;
        return newMp > MAX_MP ? MAX_MP - newMp : accurred;
    }


    function getRewardsEmissions() public view returns(uint256){
        uint256 totalStaked = this.totalSupply;
        uint256 share = this.multiplierSupply +totalSupply;
    }



}