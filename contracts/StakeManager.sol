// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract StakeManager is ERC20 {

    address stakedToken;
    
    bytes32 vaultCodehash;

    mapping (address => Account) account;


    modifier onlyVault {
        require(msg.sender.codehash() == vaultCodehash, "Unauthorized Codehash");
    }

    function join(uint256 amount) external onlyVault {
        stakedToken.transferFrom(msg.sender, )
    }

    function lock(uint256 amount, uint256 time) external onlyVault {
        
    }

    function joinAndLock(uint256 amount, uint256 time) external onlyVault {

    }

    function leave(uint256 amount) external {

    }




}