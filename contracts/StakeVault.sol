// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "./StakeManager.sol";

contract StakeVault {
    address owner;
    StakeManager stakeManager;

    ERC20 stakedToken;
    uint256 balance;
    uint256 locked;
    uint256 multiplierPoints;

    //uint256 constant FACTOR = 1; 
    uint256 constant MP_APY = 1; 
    uint256 constant MAX_MP = 1; 

    function join(uint256 amount) external {
        stakedToken.transferFrom(msg.sender, address(this), amount);
    }

    function lock(uint256 amount, uint256 time) external {
        
    }

    function joinAndLock(uint256 amount, uint256 time) external {

    }

    function leave(uint256 amount) external {

    }


    function mintMultiplierPoints() internal {
        uint256 new_mp = multiplierPoints + (balance * stakeManager.MP_APY());
        uint256 max_mp = stakeManager.MAX_MP();
        multiplierPoints = new_mp > max_mp ? max_mp : new_mp;
    }




}