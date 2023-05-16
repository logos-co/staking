// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract StakeVault {
    address owner;
    address stakeManager;

    ERC20 stakedToken;
    uint256 balance;
    uint256 locked;
    uint256 multiplier;


    function join(uint256 amount) external {
        stakedToken.transferFrom(msg.sender, address(this), amount);
    }

    function lock(uint256 amount, uint256 time) external {
        
    }

    function joinAndLock(uint256 amount, uint256 time) external {

    }

    function leave(uint256 amount) external {

    }




}