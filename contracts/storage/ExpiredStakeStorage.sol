// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { MultiplierPoint, ZERO } from "../math/MultiplierPoint.sol";

contract ExpiredStakeStorage is Ownable {
    mapping(uint256 epochId => MultiplierPoint balance) public expiredMPPerEpoch;

    function getExpiredMP(uint256 epochId) public view returns (MultiplierPoint) {
        return expiredMPPerEpoch[epochId];
    }

    function incrementExpiredMP(uint256 epochId, MultiplierPoint amount) public onlyOwner {
        expiredMPPerEpoch[epochId] = expiredMPPerEpoch[epochId] + amount;
    }

    function decrementExpiredMP(uint256 epochId, MultiplierPoint amount) public onlyOwner {
        expiredMPPerEpoch[epochId] = expiredMPPerEpoch[epochId] - amount;
    }

    function deleteExpiredMP(uint256 epochId) public onlyOwner {
        expiredMPPerEpoch[epochId] = ZERO;
    }
}
