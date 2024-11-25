definition abs(mathint x) returns mathint = 
    x >= 0 ? x : 0 - x;

definition min(mathint x, mathint y) returns mathint = 
    x > y ? y : x;

definition max(mathint x, mathint y) returns mathint = 
    x > y ? x : y;

definition average(mathint a, mathint b) returns mathint =
    (a + b) / 2;

definition mulDiv(mathint x, mathint y, mathint denominator) returns mathint =
    (x * y) / denominator;

definition ceilMulDiv(mathint x, mathint y, mathint denominator) returns mathint =
    mulDiv(x, y, denominator) + ((x * y) % denominator > 0 ? 1 : 0);