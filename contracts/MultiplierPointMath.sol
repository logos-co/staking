// SPDX-License-Identifier: MIT-1.0
pragma solidity ^0.8.26;

import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

abstract contract MultiplierPointMath {
    /// @notice One (mean) tropical year, in seconds.
    uint256 public constant YEAR = 365 days + 5 hours + 48 minutes + 45 seconds;
    /// @notice Multiplier points annual percentage yield.
    uint256 public constant MP_APY = 100;
    /// @notice Accrued multiplier points maximum multiplier.
    uint256 public constant MAX_MULTIPLIER = 4;
    /// @notice The accrue rate period of time over which multiplier points are calculated.
    uint256 public constant ACCURE_RATE = 1 weeks;
    /// @notice Minimal value to generate 1 multiplier point in the accrue rate period (rounded up).
    uint256 public constant MIN_BALANCE = (((YEAR * 100) - 1) / (MP_APY * ACCURE_RATE)) + 1;
    /// @notice Multiplier points absolute maximum multiplier
    uint256 public constant MAX_MULTIPLIER_ABSOLUTE = 1 + (2 * (MAX_MULTIPLIER * MP_APY) / 100);
    /// @notice Maximum lockup period
    uint256 public constant MAX_LOCKUP_PERIOD = MAX_MULTIPLIER * YEAR;

    /**
     * @notice Calculates the accrued multiplier points (MPs) over a time period Δt, based on the account balance
     * @param _balance Represents the current account balance
     * @param _deltaTime The time difference or the duration over which the multiplier points are accrued, expressed in
     * seconds
     * @return _accuredMP points accured for given `_amount` and  `_seconds`
     * 51584438
     * 10000000
     */
    function _calculateAccuredMP(uint256 _balance, uint256 _deltaTime) public pure returns (uint256 _accuredMP) {
        return Math.mulDiv(_balance, _deltaTime * MP_APY, YEAR * 100);
    }

    /**
     * @notice Calculates the bonus multiplier points (MPs) earned when a balance Δa is locked for a specified duration
     * t_lock.
     * It is equivalent to the accrued multiplier points function but specifically applied in the context of a locked
     * balance.
     * @param _amount quantity of tokens
     * @param _lockedSeconds time in seconds locked
     * @return _bonusMP bonus multiplier points for given `_amount` and `_lockedSeconds`
     */
    function _calculateBonusMP(uint256 _amount, uint256 _lockedSeconds) public pure returns (uint256 _bonusMP) {
        return _calculateAccuredMP(_amount, _lockedSeconds);
    }

    /**
     * @notice Calculates the initial multiplier points (MPs) based on the balance change Δa. The result is equal to
     * the amount of balance added.
     * @param _amount Represents the change in balance.
     */
    function _calculateInitialMP(uint256 _amount) public pure returns (uint256 _initialMP) {
        return _amount;
    }

    /**
     * @notice Calculates the reduction in multiplier points (MPs) when a portion of the balance Δa `_reducedAmount` is
     * removed from the total balance a_bal `_currentBalance`.
     * The reduction is proportional to the ratio of the removed balance to the total balance, applied to the current
     * multiplier points $mp$.
     * @param _mp Represents the current multiplier points
     * @param _currentBalance The total account balance before the removal of Δa `_reducedBalance`
     * @param _reducedAmount reduced balance
     * @return _reducedMP Multiplier points to reduce from `_mp`
     */
    function _calculateReducedMP(
        uint256 _mp,
        uint256 _currentBalance,
        uint256 _reducedAmount
    )
        public
        pure
        returns (uint256 _reducedMP)
    {
        return Math.mulDiv(_mp, _currentBalance, _reducedAmount);
    }

    /**
     * @notice Calculates maximum stake a given `_amount` can be generated with `MAX_MULTIPLIER`
     * @param _balance quantity of tokens
     * @return _maxMPAccured maximum quantity of muliplier points that can be generated for given `_amount`
     */
    function _calculateMaxAccuredMP(uint256 _balance) public pure returns (uint256 _maxMPAccured) {
        return Math.mulDiv(_balance, MAX_MULTIPLIER * MP_APY, 100);
    }

    /**
     * @notice The maximum total multiplier points that can be generated for a determined amount of balance and lock
     * duration.
     * @param _balance Represents the current account balance
     * @param _lockTime The time duration for which the balance is locked
     * @return _maxMP Maximum multiplier points that can be generated for given `_balance` and `_lockTime`
     */
    function _calculateMaxMP(uint256 _balance, uint256 _lockTime) public pure returns (uint256 _maxMP) {
        return _balance + Math.mulDiv(_balance * MP_APY, (MAX_MULTIPLIER * YEAR) + _lockTime, YEAR * 100);
    }

    /**
     * @dev Caution: This value is estimated and can be incorrect due precision loss.
     * @notice Estimates the time an account set as locked time.
     * @param _mpMax Maximum multiplier points calculated from the current balance.
     * @param _currentBalance Current balance used to calculate the maximum multiplier points.
     */
    function _estimateLockTime(uint256 _mpMax, uint256 _currentBalance) public pure returns (uint256 _lockTime) {
        return Math.mulDiv((_mpMax - _currentBalance) * 100, YEAR, _currentBalance * MP_APY, Math.Rounding.Ceil)
            - MAX_LOCKUP_PERIOD;
    }

    /**
     * @dev Caution: This value is estimated and can be incorrect due precision loss.
     * @notice Calculates the remaining lock time available for a given `_mpMax` and `_currentBalance`
     * @param _mpMax Maximum multiplier points calculated from the current balance.
     * @param _currentBalance Current balance used to calculate the maximum multiplier points.
     */
    function _remainingLockTimeAvailable(
        uint256 _mpMax,
        uint256 _currentBalance
    )
        public
        pure
        returns (uint256 _lockTime)
    {
        return Math.mulDiv((_currentBalance * MAX_MULTIPLIER_ABSOLUTE) - _mpMax, YEAR, _currentBalance);
    }

    /**
     * @notice Calculates the lock time for a given bonus multiplier points and current balance.
     * @param _bonusMP bonus multiplier points intended to be generated
     * @param _currentBalance current balance
     */
    function _calculateLockTime(uint256 _bonusMP, uint256 _currentBalance) public pure returns (uint256 _lockTime) {
        return Math.mulDiv(_bonusMP * 100, YEAR, _currentBalance * MP_APY);
    }
}
