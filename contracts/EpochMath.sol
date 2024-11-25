// SPDX-License-Identifier: MIT-1.0
pragma solidity ^0.8.27;

import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { MultiplierPointMath } from "./MultiplierPointMath.sol";
import { ExpiredStakeStorage } from "./storage/ExpiredStakeStorage.sol";

/**
 * @title EpochMath
 * @notice Abstract contract for managing epochs, rewards, and multiplier points (MP) within the system.
 * @author Ricardo Guilherme Schmidt
 */
abstract contract EpochMath is MultiplierPointMath {
    function totalSupply() public view virtual returns (uint256);
    function epochReward() public view virtual returns (uint256);

    uint256 public immutable START_TIME;

    struct Epoch {
        uint256 epochReward;
        uint256 totalSupply;
        uint256 potentialMP;
    }

    mapping(uint256 index => Epoch value) public epochs;
    uint256 public pendingReward;
    uint256 public currentEpoch;
    uint256 public potentialMP;
    uint256 public totalMPRate;
    ExpiredStakeStorage public EXPIRED_STAKE_STORAGE;

    uint256 public currentEpochTotalExpiredMP;

    constructor(uint256 _startTime) {
        EXPIRED_STAKE_STORAGE = _createStorage();
        START_TIME = _startTime;
    }

    /**
     * @notice Creates a new instance of ExpiredStakeStorage.
     * @return addr A new instance of the ExpiredStakeStorage contract.
     */
    function _createStorage() internal virtual returns (ExpiredStakeStorage addr) {
        return new ExpiredStakeStorage();
    }

    /**
     * @notice Release rewards for current epoch and increase epoch up to _limitEpoch
     * @param _limitEpoch Until what epoch it should be executed
     */
    function _finalizeEpoch(uint256 _limitEpoch) internal {
        uint256 tempCurrentEpoch = currentEpoch;
        while (tempCurrentEpoch < _limitEpoch) {
            Epoch storage thisEpoch = epochs[tempCurrentEpoch];
            uint256 expiredMP = EXPIRED_STAKE_STORAGE.getExpiredMP(tempCurrentEpoch);
            if (expiredMP > 0) {
                totalMPRate -= expiredMP;
                EXPIRED_STAKE_STORAGE.deleteExpiredMP(tempCurrentEpoch);
            }
            uint256 epochPotentialMP = totalMPRate;
            if (tempCurrentEpoch == currentEpoch) {
                epochPotentialMP -= currentEpochTotalExpiredMP;
                currentEpochTotalExpiredMP = 0;
                thisEpoch.epochReward = epochReward();
                pendingReward += thisEpoch.epochReward;
            }

            potentialMP += epochPotentialMP;
            thisEpoch.potentialMP = epochPotentialMP;
            thisEpoch.totalSupply = totalSupply();
            tempCurrentEpoch++;
        }
        currentEpoch = tempCurrentEpoch;
    }

    /**
     * @notice Calculates the new start time of restake based on MP predictions and processing time.
     * @param _balance The account's token balance.
     * @param _totalMP The current total multiplier points.
     * @param _maxMP The maximum multiplier points allowed.
     * @param _processTime The processing timestamp.
     * @return newStartTime The adjusted start time.
     */
    function _calculateNewStartTime(
        uint256 _balance,
        uint256 _totalMP,
        uint256 _maxMP,
        uint256 _processTime
    )
        internal
        pure
        returns (uint256 newStartTime)
    {
        return _processTime - _timeToAccrueMP(_balance, _retrieveAccruedMP(_balance, _totalMP, _maxMP));
    }

    /**
     * @notice Reduces predicted multiplier points (MP) for an account after unstake or restake.
     * @param _startTime The start time of the account's stake.
     * @param _balance The account's token balance.
     */
    function _reducePredictiedMP(uint256 _startTime, uint256 _balance) internal {
        uint256 accountEpoch = getEpoch(_startTime);
        uint256 epochExpiredTime =
            accountEpoch == currentEpoch ? getEpochStartTime(currentEpoch + 1) - _startTime : ACCURE_RATE;
        (uint256 mpRate, uint256 mpFractional, uint256 epochTarget1, uint256 mpRemainder) =
            _calculateMPPrediction(_balance, accountEpoch, epochExpiredTime);

        currentEpochTotalExpiredMP -= mpFractional;
        if (mpRemainder > 0) {
            if (epochTarget1 < currentEpoch) {
                EXPIRED_STAKE_STORAGE.decrementExpiredMP(epochTarget1, mpRemainder);
                totalMPRate -= mpRemainder;
            }

            if (epochTarget1 + 1 < currentEpoch) {
                EXPIRED_STAKE_STORAGE.decrementExpiredMP(epochTarget1 + 1, mpRate - mpRemainder);
                totalMPRate -= mpRate - mpRemainder;
            }
        } else {
            if (epochTarget1 < currentEpoch) {
                EXPIRED_STAKE_STORAGE.decrementExpiredMP(epochTarget1, mpRate);
                totalMPRate -= mpRate;
            }
        }
    }

    /**
     * @notice Increases predicted multiplier points (MP) for an account based on new stakes.
     * @param _startTime The start time of the stake.
     * @param _balance The token balance for the stake.
     * @param _maxMP The maximum multiplier points allowed.
     * @param _totalMP The current total multiplier points.
     */
    function _increasePredictedMP(uint256 _startTime, uint256 _balance, uint256 _maxMP, uint256 _totalMP) internal {
        uint256 accountEpoch = getEpoch(_startTime);
        uint256 epochExpiredTime =
            accountEpoch == currentEpoch ? getEpochStartTime(currentEpoch + 1) - _startTime : ACCURE_RATE;
        (uint256 mpRate, uint256 mpFractional, uint256 epochTarget1, uint256 mpRemainder) =
            _calculateMPPrediction(_balance, accountEpoch, epochExpiredTime);

        currentEpochTotalExpiredMP += mpFractional;
        if (mpRemainder > 0) {
            if (currentEpoch < epochTarget1) {
                EXPIRED_STAKE_STORAGE.incrementExpiredMP(epochTarget1, mpRemainder);
            }
            if (currentEpoch < epochTarget1 + 1) {
                EXPIRED_STAKE_STORAGE.incrementExpiredMP(epochTarget1 + 1, mpRate - mpRemainder);
            }
        } else {
            EXPIRED_STAKE_STORAGE.incrementExpiredMP(epochTarget1, mpRate);
        }
        totalMPRate += Math.min(mpRate, _maxMP - _totalMP);
    }

    /**
     * @notice Predicts the multiplier points (MP) for an account based on epoch time difference and balance.
     * @param _balance The account's token balance.
     * @param _accountEpoch The epoch of the account's stake.
     * @param _deltaTime The time difference from current epoch
     * @return mpRate The MP rate accrued over a full epoch.
     * @return mpFractional The fractional MP for the time difference.
     * @return epochTarget1 The target epoch for full MP accrual.
     * @return mpRemainder The remaining MP for the next epoch.
     */
    function _calculateMPPrediction(
        uint256 _balance,
        uint256 _accountEpoch,
        uint256 _deltaTime
    )
        internal
        pure
        returns (uint256 mpRate, uint256 mpFractional, uint256 epochTarget1, uint256 mpRemainder)
    {
        mpRate = _accrueMP(_balance, ACCURE_RATE);
        mpFractional = mpRate - _accrueMP(_balance, _deltaTime);

        uint256 mpTarget = _maxAccrueMP(_balance) + mpFractional;
        uint256 deltaEpochTarget1 = mpTarget / mpRate;

        epochTarget1 = _accountEpoch + deltaEpochTarget1;
        if (mpTarget % mpRate > 0) {
            mpRemainder = (mpRate * (deltaEpochTarget1 + 1)) - mpTarget;
        }
    }

    /**
     * @notice Returns the epoch of a specific timestamp
     * @param _timestamp the timestamp to calculate the epoch
     * @return _epochNum the number of the epoch
     */
    function getEpoch(uint256 _timestamp) public view returns (uint256 _epochNum) {
        _epochNum = (_timestamp - START_TIME) / ACCURE_RATE;
    }

    /**
     * @notice Returns the start time of an epoch
     * @param _epochNum epoch number
     * @return _epochEnd start time of epoch
     */
    function getEpochStartTime(uint256 _epochNum) public view returns (uint256 _epochEnd) {
        return START_TIME + (ACCURE_RATE * (_epochNum));
    }

    /**
     * @notice Returns the last epoch that can be processed on current time
     * @return _newEpoch the number of the epoch after all epochs that can be processed
     */
    function newEpoch() public view returns (uint256 _newEpoch) {
        _newEpoch = (block.timestamp - START_TIME) / ACCURE_RATE;
    }
}
