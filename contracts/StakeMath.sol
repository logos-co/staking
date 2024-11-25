// SPDX-License-Identifier: MIT-1.0
pragma solidity ^0.8.27;

import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { MultiplierPointMath } from "./MultiplierPointMath.sol";

abstract contract StakeMath is MultiplierPointMath {
    error StakeManager__FundsLocked();
    error StakeManager__InvalidLockTime();
    error StakeManager__StakeIsTooLow();
    error StakeManager__InsufficientFunds();
    error StakeManager__AccrueTimeNotReached();

    /// @notice Minimal lockup time
    uint256 public constant MIN_LOCKUP_PERIOD = 1 weeks;
    /// @notice Maximum lockup period
    uint256 public constant MAX_LOCKUP_PERIOD = MAX_MULTIPLIER * YEAR;

    /**
     * @notice Calculates the bonus multiplier points earned when a balance Δa is increased an optionally locked for a
     * specified duration
     * @param _balance Account current balance
     * @param _currentMaxMP Account current max multiplier points
     * @param _currentLockEndTime Account current lock end timestamp
     * @param _processTime Process current timestamp
     * @param _increasedAmount Increased amount of balance
     * @param _increasedLockSeconds Increased amount of seconds to lock
     * @return _deltaMpTotal Increased amount of total multiplier points
     * @return _newMaxMP Account new max multiplier points
     * @return _newLockEnd Account new lock end timestamp
     */
    function _calculateStake(
        uint256 _balance,
        uint256 _currentMaxMP,
        uint256 _currentLockEndTime,
        uint256 _processTime,
        uint256 _increasedAmount,
        uint256 _increasedLockSeconds
    )
        internal
        pure
        returns (uint256 _deltaMpTotal, uint256 _newMaxMP, uint256 _newLockEnd)
    {
        uint256 newBalance = _balance + _increasedAmount;
        if (newBalance < MIN_BALANCE) {
            revert StakeManager__StakeIsTooLow();
        }
        _newLockEnd = Math.max(_currentLockEndTime, _processTime) + _increasedLockSeconds;
        uint256 dt_lock = _newLockEnd - _processTime;
        if (dt_lock != 0 && (dt_lock < MIN_LOCKUP_PERIOD || dt_lock > MAX_LOCKUP_PERIOD)) {
            revert StakeManager__InvalidLockTime();
        }

        uint256 deltaMpBonus;
        if (dt_lock > 0) {
            deltaMpBonus = _bonusMP(_increasedAmount, dt_lock);
        }

        if (_balance > 0 && _increasedLockSeconds > 0) {
            deltaMpBonus += _bonusMP(_balance, _increasedLockSeconds);
        }

        _deltaMpTotal = _initialMP(_increasedAmount) + deltaMpBonus;
        _newMaxMP = _currentMaxMP + _deltaMpTotal + _accruedMP(_increasedAmount, MAX_MULTIPLIER * YEAR);

        require(_newMaxMP <= MP_MPY_ABSOLUTE * (_balance + _increasedAmount), "StakeMath: max multiplier exceeded");
    }

    /**
     * @notice Calculates the bonus multiplier points earned when a balance Δa is locked for a specified duration
     * @param _balance Account current balance
     * @param _currentMaxMP Account current max multiplier points
     * @param _currentLockEndTime Account current lock end timestamp
     * @param _processTime Process current timestamp
     * @param _increasedLockSeconds Increased amount of seconds to lock
     * @return _deltaMpTotal Increased amount of total multiplier points
     * @return _newMaxMP Account new max multiplier points
     * @return _newLockEnd Account new lock end timestamp
     */
    function calculateLock(
        uint256 _balance,
        uint256 _currentMaxMP,
        uint256 _currentLockEndTime,
        uint256 _processTime,
        uint256 _increasedLockSeconds
    )
        internal
        pure
        returns (uint256 _deltaMpTotal, uint256 _newMaxMP, uint256 _newLockEnd)
    {
        require(_balance > 0);
        require(_increasedLockSeconds > 0);

        _newLockEnd = Math.max(_currentLockEndTime, _processTime) + _increasedLockSeconds;
        uint256 dt_lock = _newLockEnd - _processTime;
        if (dt_lock != 0 && (dt_lock < MIN_LOCKUP_PERIOD || dt_lock > MAX_LOCKUP_PERIOD)) {
            revert StakeManager__InvalidLockTime();
        }

        _deltaMpTotal += _bonusMP(_balance, _increasedLockSeconds);
        _newMaxMP = _currentMaxMP + _deltaMpTotal;

        require(_newMaxMP <= MP_MPY_ABSOLUTE * (_balance), "StakeMath: max multiplier exceeded");
    }

    /**
     *
     * @param _balance Account current balance
     * @param _currentLockEndTime Account current lock end timestamp
     * @param _processTime Process current timestamp
     * @param _currentTotalMP Account current total multiplier points
     * @param _currentMaxMP Account current max multiplier points
     * @param _reducedAmount Reduced amount of balance
     * @return _deltaMpTotal Increased amount of total multiplier points
     * @return _deltaMpMax Increased amount of max multiplier points
     */
    function _calculateUnstake(
        uint256 _balance,
        uint256 _currentLockEndTime,
        uint256 _processTime,
        uint256 _currentTotalMP,
        uint256 _currentMaxMP,
        uint256 _reducedAmount
    )
        internal
        pure
        returns (uint256 _deltaMpTotal, uint256 _deltaMpMax)
    {
        if (_reducedAmount > _balance) {
            revert StakeManager__InsufficientFunds();
        }
        if (_currentLockEndTime > _processTime) {
            revert StakeManager__FundsLocked();
        }
        uint256 newBalance = _balance - _reducedAmount;
        if (newBalance < MIN_BALANCE) {
            revert StakeManager__StakeIsTooLow();
        }
        _deltaMpTotal = _reducedMP(_currentTotalMP, _balance, _reducedAmount);
        _deltaMpMax = _reducedMP(_currentMaxMP, _balance, _reducedAmount);
    }

    /**
     * @notice Calculates the accrued multiplier points for a given balance and seconds passed since last accrual
     * @param _balance Account current balance
     * @param _currentTotalMP Account current total multiplier points
     * @param _currentMaxMP Account current max multiplier points
     * @param _lastAccrualTime Account current last accrual timestamp
     * @param _processTime Process current timestamp
     * @return _deltaMpTotal Increased amount of total multiplier points
     */
    function _calculateAccrual(
        uint256 _balance,
        uint256 _currentTotalMP,
        uint256 _currentMaxMP,
        uint256 _lastAccrualTime,
        uint256 _processTime
    )
        internal
        pure
        returns (uint256 _deltaMpTotal)
    {
        uint256 dt = _processTime - _lastAccrualTime;
        if (dt < ACCURE_RATE) {
            revert StakeManager__AccrueTimeNotReached();
        }
        if (_currentTotalMP < _currentMaxMP) {
            _deltaMpTotal = Math.min(_accruedMP(_balance, dt), _currentMaxMP - _currentTotalMP);
        }
    }

    /**
     * @dev Caution: This value is estimated and can be incorrect due precision loss.
     * @notice Estimates the time an account set as locked time.
     * @param _mpMax Maximum multiplier points calculated from the current balance.
     * @param _balance Current balance used to calculate the maximum multiplier points.
     */
    function _estimateLockTime(uint256 _mpMax, uint256 _balance) internal pure returns (uint256 _lockTime) {
        return Math.mulDiv((_mpMax - _balance) * 100, YEAR, _balance * MP_APY, Math.Rounding.Up) - MAX_LOCKUP_PERIOD;
    }
}
