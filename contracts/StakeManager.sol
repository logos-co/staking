// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract StakeManager is ERC20 {

    address stakedToken;
    
    bytes32 vaultCodehash;
    uint256 mp_supply = 0;
    uint256 public constant MP_APY = 1; 
    uint256 public constant STAKE_APY = 1; 
    uint256 public constant MAX_BOOST = 1; 

    mapping (address => Account) account;


    modifier onlyVault {
        require(msg.sender.codehash() == vaultCodehash, "Unauthorized Codehash");
    }

    function join(uint256 amount) external onlyVault {

    }

    function lock(uint256 amount, uint256 time) external onlyVault {
        
    }

    function joinAndLock(uint256 amount, uint256 time) external onlyVault {

    }

    function leave(uint256 amount) external {

    }

    function getRewardsEmissions() public view returns(uint256){

    }
    

    function increase_mp(uint256 amount) {
        
    }



}