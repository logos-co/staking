import "./DefinitionTime.spec";
definition M_MAX() returns mathint = 4;
definition APY() returns mathint = 100;
definition MPY() returns mathint = M_MAX() * APY();
definition MPY_ABS() returns mathint = 100 + (2 * (M_MAX() * APY()));
definition T_RATE() returns mathint = 1 * T_WEEK();
definition A_MIN() returns mathint = (((T_YEAR() * 100) - 1) / (APY() * T_RATE())) + 1;
definition T_MIN() returns mathint = 90 * T_DAY();
definition T_MAX() returns mathint = M_MAX() * T_YEAR();


definition accrueMP(mathint _balance, mathint _deltaTime) returns mathint = (_balance * _deltaTime * APY()) / (T_YEAR() * 100);
definition bonusMP(mathint _balance, mathint _lockedSeconds) returns mathint = accrueMP(_balance, _lockedSeconds);
definition initialMP(mathint _balance) returns mathint = _balance;
definition reduceMP(mathint _balance, mathint _mp, mathint _reducedAmount) returns mathint = (_mp * _balance) / _reducedAmount;

definition maxTotalMP(mathint _balance, mathint _lockTime) returns mathint = _balance + ((_balance * APY()) * ((M_MAX() * T_YEAR()) + _lockTime) / (T_YEAR() * 100));
definition maxAccrueMP(mathint _balance) returns mathint = (_balance * MPY()) / 100;
definition maxAbsoluteMP(mathint _balance) returns mathint = (_balance * MPY_ABS()) / 100;
definition retrieveBonusMP(mathint _balance, mathint _maxMP) returns mathint = _maxMP - (_balance + maxAccrueMP(_balance));
definition retrieveAccruedMP(mathint _balance, mathint _totalMP, mathint _maxMP) returns mathint = _totalMP - maxAccrueMP(_balance) - _maxMP;
definition timeToAccrueMP(mathint _balance, mathint _targetMP) returns mathint = (_targetMP * 100 * T_YEAR()) / (_balance * APY());
definition estimateLockTime(mathint _balance, mathint _maxMP) returns mathint = (((_maxMP-_balance) * 100 * T_YEAR())+1) / ((_balance * APY())-1);
definition lockTimeAvailable(mathint _balance, mathint _maxMP) returns mathint = ((maxAbsoluteMP(_balance) - _maxMP) * T_YEAR()) / _balance;





