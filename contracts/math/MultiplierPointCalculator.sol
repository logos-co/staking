// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

type MultiplierPoints is uint256;

using { add as + } for MultiplierPoints global;
using { sub as - } for MultiplierPoints global;
using { lt as < } for MultiplierPoints global;
using { gt as > } for MultiplierPoints global;

function add(MultiplierPoints a, MultiplierPoints b) pure returns (MultiplierPoints) {
    return MultiplierPoints.wrap(MultiplierPoints.unwrap(a) + MultiplierPoints.unwrap(b));
}

function sub(MultiplierPoints a, MultiplierPoints b) pure returns (MultiplierPoints) {
    return MultiplierPoints.wrap(MultiplierPoints.unwrap(a) - MultiplierPoints.unwrap(b));
}

function lt(MultiplierPoints a, MultiplierPoints b) pure returns (bool) {
    return MultiplierPoints.unwrap(a) < MultiplierPoints.unwrap(b);
}

function gt(MultiplierPoints a, MultiplierPoints b) pure returns (bool) {
    return MultiplierPoints.unwrap(a) > MultiplierPoints.unwrap(b);
}

library MultiplierPointsCalculator {
    uint256 constant MAX_BOOST = 4;
    uint256 constant YEAR = 365 days;
    uint256 constant MP_APY = 1;

    /**
     * @notice Calculates maximum multiplier point increase for given balance
     * @param _mpToMint tested value
     * @param _balance balance of account
     * @param _totalMP total multiplier point of the account
     * @param _bonusMP bonus multiplier point of the account
     * @return _maxMpToMint maximum multiplier points to mint
     */
    function getMaxMPToMint(
        MultiplierPoints _mpToMint,
        uint256 _balance,
        MultiplierPoints _bonusMP,
        MultiplierPoints _totalMP
    )
        private
        pure
        returns (MultiplierPoints _maxMpToMint)
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
    function getMPToMint(uint256 _balance, uint256 _deltaTime) private pure returns (MultiplierPoints) {
        return MultiplierPoints.wrap(Math.mulDiv(_balance, _deltaTime, YEAR) * MP_APY);
    }
}
