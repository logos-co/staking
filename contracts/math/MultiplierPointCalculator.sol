// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

import { MultiplierPoint } from "./MultiplierPoint.sol";

library MultiplierPointCalculator {
    uint256 constant MAX_BOOST = 4;
    uint256 constant YEAR = 365 days;
    uint256 constant MP_APY = 1;

    function gtThanZero(MultiplierPoint a) public pure returns (bool) {
        return MultiplierPoint.unwrap(a) > 0;
    }
    /**
     * @notice Calculates maximum multiplier point increase for given balance
     * @param _mpToMint tested value
     * @param _balance balance of account
     * @param _totalMP total multiplier point of the account
     * @param _bonusMP bonus multiplier point of the account
     * @return _maxMpToMint maximum multiplier points to mint
     */

    function getMaxMPToMint(
        MultiplierPoint _mpToMint,
        uint256 _balance,
        MultiplierPoint _bonusMP,
        MultiplierPoint _totalMP
    )
        public
        pure
        returns (MultiplierPoint _maxMpToMint)
    {
        // Maximum multiplier point for given balance
        _maxMpToMint = getMPToMint(_balance, MAX_BOOST * YEAR) + _bonusMP;
        if (_mpToMint + _totalMP > _maxMpToMint) {
            //reached cap when increasing MP
            return _maxMpToMint - _totalMP; //how much left to reach cap
        } else {
            //not reached capw hen increasing MP
            return _mpToMint; //just return tested value
        }
    }

    /**
     * @notice Calculates multiplier points to mint for given balance and time
     * @param _balance balance of account
     * @param _deltaTime time difference
     * @return multiplier points to mint
     */
    function getMPToMint(uint256 _balance, uint256 _deltaTime) public pure returns (MultiplierPoint) {
        return MultiplierPoint.wrap(Math.mulDiv(_balance, _deltaTime, YEAR) * MP_APY);
    }

    function getMPReduced(
        uint256 _currentBalance,
        uint256 _decreasedBalance,
        MultiplierPoint _totalMP
    )
        public
        pure
        returns (MultiplierPoint)
    {
        return MultiplierPoint.wrap(Math.mulDiv(_decreasedBalance, MultiplierPoint.unwrap(_totalMP), _currentBalance));
    }

    function getMaxMP(uint256 _amount) public pure returns (MultiplierPoint) {
        return getMPToMint(_amount, MAX_BOOST * YEAR);
    }
}
