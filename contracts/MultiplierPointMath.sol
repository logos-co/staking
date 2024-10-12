// SPDX-License-Identifier: MIT-1.0
pragma solidity ^0.8.18;

import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

abstract contract MultiplierPointMath {
    uint256 public constant YEAR = 365 days;
    uint256 public constant MP_APY = 1;
    uint256 public constant MAX_MULTIPLIER = 4;

    /**
     * @notice Calculates multiplier points accurred for given `_amount` and  `_seconds` time passed
     * @param _amount quantity of tokens
     * @param _seconds time in seconds
     * @return _accuredMP points accured for given `_amount` and  `_seconds`
     */
    function _calculateAccuredMP(uint256 _amount, uint256 _seconds) internal pure returns (uint256 _accuredMP) {
        return Math.mulDiv(_amount, _seconds, YEAR) * MP_APY;
    }

    /**
     * @notice Calculates bonus multiplier points for given `_amount` and `_lockedSeconds`
     * @param _amount quantity of tokens
     * @param _lockedSeconds time in seconds locked
     * @return _bonusMP bonus multiplier points for given `_amount` and `_lockedSeconds`
     */
    function _calculateBonusMP(uint256 _amount, uint256 _lockedSeconds) internal pure returns (uint256 _bonusMP) {
        _bonusMP = _amount;
        if (_lockedSeconds > 0) {
            _bonusMP += _calculateAccuredMP(_amount, _lockedSeconds);
        }
    }

    /**
     * @notice Calculates minimum stake to genarate 1 multiplier points for given `_seconds`
     * @param _seconds time in seconds
     * @return _minimumStake minimum quantity of tokens
     */
    function _calculateMinimumStake(uint256 _seconds) internal pure returns (uint256 _minimumStake) {
        return YEAR / (_seconds * MP_APY);
    }

    /**
     * @notice Calculates maximum stake a given `_amount` can be generated with `MAX_MULTIPLIER`
     * @param _amount quantity of tokens
     * @return _maxMPAccured maximum quantity of muliplier points that can be generated for given `_amount`
     */
    function _calculateMaxAccuredMP(uint256 _amount) internal pure returns (uint256 _maxMPAccured) {
        return _calculateAccuredMP(_amount, MAX_MULTIPLIER * YEAR);
    }
}
