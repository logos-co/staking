import "./definition/DefinitionMultiplierPointsMath.spec";

methods {
    function MultiplierPointMath._accrueMP(uint256 _balance, uint256 _deltaTime) internal returns (uint256) => accrueMPSummary(_balance, _deltaTime) ;
    function MultiplierPointMath._bonusMP(uint256 _balance, uint256 _lockedSeconds) internal returns (uint256) => bonusMPSummary(_balance, _lockedSeconds);
    function MultiplierPointMath._initialMP(uint256 _balance) internal returns (uint256)  => initialMPSummary(_balance);
    function MultiplierPointMath._reduceMP(uint256 _balance, uint256 _mp, uint256 _reducedAmount) internal returns (uint256) => reduceMPSummary(_balance, _mp, _reducedAmount);
    function MultiplierPointMath._maxAccrueMP(uint256 _balance) internal returns (uint256) => maxAccrueMPSummary(_balance);
    function MultiplierPointMath._maxTotalMP(uint256 _balance, uint256 _lockTime) internal returns (uint256) => maxTotalMPSummary(_balance, _lockTime) ;
    function MultiplierPointMath._maxAbsoluteMP(uint256 _balance) internal returns (uint256)  => maxAbsoluteMPSummary(_balance);
    function MultiplierPointMath._lockTimeAvailable(uint256 _balance, uint256 _mpMax) internal returns (uint256) => lockTimeAvailableSummary(_balance, _mpMax);
    function MultiplierPointMath._timeToAccrueMP(uint256 _balance, uint256 _mp) internal returns (uint256)  => timeToAccrueMPSummary(_balance, _mp);
    function MultiplierPointMath._retrieveBonusMP(uint256 _balance, uint256 _maxMP) internal returns (uint256) => retrieveBonusMPSummary(_balance, _maxMP);
    function MultiplierPointMath._retrieveAccruedMP(uint256 _balance, uint256 _totalMP, uint256 _maxMP) internal returns (uint256) => retrieveAccruedMPSummary(_balance, _totalMP, _maxMP);
}

function accrueMPSummary(uint256 _balance, uint256 _deltaTime) returns uint256  {
    return require_uint256(accrueMP(_balance, _deltaTime));
}

function bonusMPSummary(uint256 _balance, uint256 _lockedSeconds) returns uint256  {
    return require_uint256(bonusMP(_balance, _lockedSeconds));
}

function initialMPSummary(uint256 _balance) returns uint256 {
    return _balance;
}

function reduceMPSummary(
    uint256 _balance,
    uint256 _mp,
    uint256 _reducedAmount
) returns uint256 {
    return require_uint256(reduceMP(_balance,_mp,_reducedAmount));
}

function maxAccrueMPSummary(uint256 _balance) returns uint256 {
    return require_uint256(maxAccrueMP(_balance));
}

function maxTotalMPSummary(uint256 _balance, uint256 _lockTime) returns uint256 {
    return require_uint256(maxTotalMP(_balance, _lockTime));
}

function maxAbsoluteMPSummary(uint256 _balance) returns uint256 {
    return require_uint256(maxAbsoluteMP(_balance));
}

function lockTimeAvailableSummary(
    uint256 _balance,
    uint256 _mpMax
) returns uint256 {
    return require_uint256(lockTimeAvailable(_balance, _mpMax));
}

function timeToAccrueMPSummary(uint256 _balance, uint256 _mp) returns uint256 { 
    return require_uint256(timeToAccrueMP(_balance, _mp)); 
}
function retrieveBonusMPSummary(uint256 _balance, uint256 _maxMP) returns uint256 { 
    return require_uint256(retrieveBonusMP(_balance, _maxMP)); 
}
function retrieveAccruedMPSummary(uint256 _balance, uint256 _totalMP, uint256 _maxMP) returns uint256 { 
    return require_uint256(retrieveAccruedMP(_balance, _totalMP, _maxMP)); 
}