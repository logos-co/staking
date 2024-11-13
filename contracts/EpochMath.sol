// SPDX-License-Identifier: MIT-1.0
pragma solidity ^0.8.27;

import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { MultiplierPointMath } from "./MultiplierPointMath.sol";

abstract contract EpochMath is MultiplierPointMath {
    function getEpochStartTime(uint256 _epochNum) public view virtual returns (uint256);

    function _calculateMPPrediction(
        uint256 _amount,
        uint256 _currentEpoch,
        uint256 _deltaTime
    )
        internal
        pure
        returns (uint256 mpRate, uint256 mpFractional, uint256 epochTarget1, uint256 epochTarget2, uint256 mpRemainder)
    {
        mpRate = _calculateAccuredMP(_amount, ACCURE_RATE);
        mpFractional = mpRate - _calculateAccuredMP(_amount, _deltaTime);

        uint256 mpTarget = _calculateMaxAccuredMP(_amount) + mpFractional;
        uint256 deltaEpochTarget1 = mpTarget / mpRate;
        uint256 deltaEpochTarget2 = mpTarget % mpRate;

        epochTarget1 = _currentEpoch + deltaEpochTarget1;
        if (deltaEpochTarget2 > 0) {
            epochTarget2 = epochTarget1 + 1;
            mpRemainder = (mpRate * (epochTarget1 + 1)) - mpTarget;
        }
    }
}
