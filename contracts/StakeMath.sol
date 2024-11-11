// SPDX-License-Identifier: MIT-1.0
pragma solidity ^0.8.27;

import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { MultiplierPointMath } from "./MultiplierPointMath.sol";

abstract contract StakeMath is MultiplierPointMath {
    /// @notice Minimal lockup time
    uint256 public constant MIN_LOCKUP_PERIOD = 1 weeks;
    /// @notice Maximum lockup period
    uint256 public constant MAX_LOCKUP_PERIOD = MAX_MULTIPLIER * YEAR;

    /**
     * @notice Calculates the bonus multiplier points earned when a balance Δa is increased an optionally locked for a
     * specified duration
     * @param _balance Account current balance
     * @param _maxMP Account current max multiplier points
     * @param _lockEndTime Account current lock end timestamp
     * @param _processTime Process current timestamp
     * @param _increasedAmount Increased amount of balance
     * @param _increasedLockSeconds Increased amount of seconds to lock
     * @return _deltaMpTotal Increased amount of total multiplier points
     * @return _newMaxMP Account new max multiplier points
     * @return _newLockEnd Account new lock end timestamp
     */
    function _calculateStake(
        uint256 _balance,
        uint256 _maxMP,
        uint256 _lockEndTime,
        uint256 _processTime,
        uint256 _increasedAmount,
        uint256 _increasedLockSeconds
    )
        internal
        pure
        returns (uint256 _deltaMpTotal, uint256 _newMaxMP, uint256 _newLockEnd)
    {
        uint256 newBalance = _balance + _increasedAmount;
        require(newBalance >= MIN_BALANCE, "StakeMath: balance too low");
        _newLockEnd = Math.max(_lockEndTime, _processTime) + _increasedLockSeconds;
        uint256 dt_lock = _newLockEnd - _processTime;
        require(dt_lock == 0 || dt_lock >= MIN_LOCKUP_PERIOD, "StakeMath: lockup time too low");
        require(dt_lock <= MAX_LOCKUP_PERIOD, "StakeMath: lockup time too high");

        uint256 deltaMpBonus;
        if (dt_lock > 0) {
            deltaMpBonus = _calculateBonusMP(_increasedAmount, dt_lock);
        }

        if (_balance > 0 && _increasedLockSeconds > 0) {
            deltaMpBonus += _calculateBonusMP(_balance, _increasedLockSeconds);
        }

        _deltaMpTotal = _calculateInitialMP(_increasedAmount) + deltaMpBonus;
        _newMaxMP = _maxMP + _deltaMpTotal + _calculateAccuredMP(_balance, MAX_MULTIPLIER * YEAR);

        require(_newMaxMP <= MP_MPY_ABSOLUTE * (_balance + _increasedAmount), "StakeMath: max multiplier exceeded");
    }

    /**
     * @notice Calculates the bonus multiplier points earned when a balance Δa is locked for a specified duration
     * @param _balance Account current balance
     * @param _maxMP Account current max multiplier points
     * @param _lockEndTime Account current lock end timestamp
     * @param _processTime Process current timestamp
     * @param _increasedLockSeconds Increased amount of seconds to lock
     * @return _deltaMpTotal Increased amount of total multiplier points
     * @return _newMaxMP Account new max multiplier points
     * @return _newLockEnd Account new lock end timestamp
     */
    function calculateLock(
        uint256 _balance,
        uint256 _maxMP,
        uint256 _lockEndTime,
        uint256 _processTime,
        uint256 _increasedLockSeconds
    )
        internal
        pure
        returns (uint256 _deltaMpTotal, uint256 _newMaxMP, uint256 _newLockEnd)
    {
        require(_balance > 0);
        require(_increasedLockSeconds > 0);

        _newLockEnd = Math.max(_lockEndTime, _processTime) + _increasedLockSeconds;
        uint256 dt_lock = _newLockEnd - _processTime;
        require(dt_lock == 0 || dt_lock >= MIN_LOCKUP_PERIOD, "StakeMath: lockup time too low");
        require(dt_lock <= MAX_LOCKUP_PERIOD, "StakeMath: lockup time too high");

        _deltaMpTotal += _calculateBonusMP(_balance, _increasedLockSeconds);
        _newMaxMP = _maxMP + _deltaMpTotal;

        require(_newMaxMP <= MP_MPY_ABSOLUTE * (_balance), "StakeMath: max multiplier exceeded");
    }

    /**
     *
     * @param _balance Account current balance
     * @param _lockEndTime Account current lock end timestamp
     * @param _processTime Process current timestamp
     * @param _totalMP Account current total multiplier points
     * @param _maxMP Account current max multiplier points
     * @param _reducedAmount Reduced amount of balance
     * @return _deltaMpTotal Increased amount of total multiplier points
     * @return _deltaMpMax Increased amount of max multiplier points
     */
    function _calculateUnstake(
        uint256 _balance,
        uint256 _lockEndTime,
        uint256 _processTime,
        uint256 _totalMP,
        uint256 _maxMP,
        uint256 _reducedAmount
    )
        internal
        pure
        returns (uint256 _deltaMpTotal, uint256 _deltaMpMax)
    {
        require(_lockEndTime <= _processTime, "StakeMath: lockup not ended");
        require(_balance >= _reducedAmount, "StakeMath: balance too low");
        uint256 newBalance = _balance - _reducedAmount;
        require(newBalance == 0 || newBalance >= MIN_BALANCE, "StakeMath: balance too low");
        _deltaMpTotal = _calculateReducedMP(_totalMP, _balance, _reducedAmount);
        _deltaMpMax = _calculateReducedMP(_maxMP, _balance, _reducedAmount);
    }

    /**
     * @notice Calculates the accrued multiplier points for a given balance and seconds passed since last accrual
     * @param _balance Account current balance
     * @param _totalMP Account current total multiplier points
     * @param _maxMP Account current max multiplier points
     * @param _lastAccrualTime Account current last accrual timestamp
     * @param _processTime Process current timestamp
     * @return _deltaMpTotal Increased amount of total multiplier points
     */
    function _calculateAccrual(
        uint256 _balance,
        uint256 _totalMP,
        uint256 _maxMP,
        uint256 _lastAccrualTime,
        uint256 _processTime
    )
        internal
        pure
        returns (uint256 _deltaMpTotal)
    {
        uint256 dt = _processTime - _lastAccrualTime;
        require(dt >= ACCURE_RATE, "StakeMath: no enough time passed");
        if (_totalMP <= _maxMP) {
            _deltaMpTotal = Math.min(_calculateAccuredMP(_balance, dt), _maxMP - _totalMP);
        }
    }

    /**
     * @dev Caution: This value is estimated and can be incorrect due precision loss.
     * @notice Estimates the time an account set as locked time.
     * @param _mpMax Maximum multiplier points calculated from the current balance.
     * @param _currentBalance Current balance used to calculate the maximum multiplier points.
     */
    function _estimateLockTime(uint256 _mpMax, uint256 _currentBalance) internal pure returns (uint256 _lockTime) {
        return Math.mulDiv((_mpMax - _currentBalance) * 100, YEAR, _currentBalance * MP_APY, Math.Rounding.Up)
            - MAX_LOCKUP_PERIOD;
    }
}
