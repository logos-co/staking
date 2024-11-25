import "./definition/DefinitionEpoch.spec";

methods {
    function EpochMath._calculateMPPrediction(uint256 _balance, uint256 _accountEpoch, uint256 _deltaTime) internal returns (uint256, uint256, uint256, uint256) => calculateMPPredictionSummary(_balance, _accountEpoch, _deltaTime);
    function EpochMath._calculateNewStartTime(uint256 _balance, uint256 _totalMP,uint256 _maxMP, uint256 _processTime) internal returns (uint256) => calculateNewStartTime( _balance, _totalMP, _maxMP, _processTime);
}

function calculateMPPredictionSummary(uint256 _balance, uint256 _accountEpoch, uint256 _deltaTime) returns (uint256, uint256, uint256, uint256) {
        require _balance >= A_MIN();
        uint256 mpRate = require_uint256(accrueMP(_balance, T_RATE()));
        uint256 mpFractional = require_uint256(mpRate - accrueMP(_balance, _deltaTime));

        mathint mpTarget = maxAccrueMP(_balance) + mpFractional;
        mathint deltaEpochTarget1 = mpTarget / mpRate;

        uint256 epochTarget1 = require_uint256(_accountEpoch + deltaEpochTarget1);
        uint256 mpRemainder;
        if (mpTarget % mpRate > 0) {
            mpRemainder = require_uint256((mpRate * (deltaEpochTarget1 + 1)) - mpTarget);
        } else {
            mpRemainder = 0;
        }
        return (mpRate, mpFractional, epochTarget1, mpRemainder);
}


function calculateNewStartTime(uint256 _balance, uint256 _totalMP,uint256 _maxMP, uint256 _processTime) returns uint256 {
    return require_uint256(_processTime - timeToAccrueMP(_balance, retrieveAccruedMP(_balance, _totalMP, _maxMP)));
}
