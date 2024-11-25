import "./DefinitionMultiplierPointsMath.spec";

definition epoch(mathint _timestamp, mathint startTime) returns mathint = (_timestamp - startTime) / T_RATE();
definition epochStart(mathint _epochNum, mathint startTime) returns mathint = startTime + (T_RATE() * _epochNum);


