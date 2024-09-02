// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

contract StakeRewardEstimate is Ownable {
    mapping(uint256 epochId => uint256 balance) public expiredMPPerEpoch;

    function getExpiredMP(uint256 epochId) public view returns (uint256) {
        return expiredMPPerEpoch[epochId];
    }

    function incrementExpiredMP(uint256 epochId, uint256 amount) public onlyOwner {
        expiredMPPerEpoch[epochId] += amount;
    }

    function decrementExpiredMP(uint256 epochId, uint256 amount) public onlyOwner {
        expiredMPPerEpoch[epochId] -= amount;
    }

    function deleteExpiredMP(uint256 epochId) public onlyOwner {
        delete expiredMPPerEpoch[epochId];
    }

}


