//SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

type MultiplierPoint is uint256;

using { add as +, sub as -, mul as *, div as /, lt as <, gt as > } for MultiplierPoint global;

MultiplierPoint constant ZERO = MultiplierPoint.wrap(0);

function add(MultiplierPoint a, MultiplierPoint b) pure returns (MultiplierPoint) {
    return MultiplierPoint.wrap(MultiplierPoint.unwrap(a) + MultiplierPoint.unwrap(b));
}

function sub(MultiplierPoint a, MultiplierPoint b) pure returns (MultiplierPoint) {
    return MultiplierPoint.wrap(MultiplierPoint.unwrap(a) - MultiplierPoint.unwrap(b));
}

function div(MultiplierPoint a, MultiplierPoint b) pure returns (MultiplierPoint) {
    return MultiplierPoint.wrap(MultiplierPoint.unwrap(a) / MultiplierPoint.unwrap(b));
}

function mul(MultiplierPoint a, MultiplierPoint b) pure returns (MultiplierPoint) {
    return MultiplierPoint.wrap(MultiplierPoint.unwrap(a) * MultiplierPoint.unwrap(b));
}

function lt(MultiplierPoint a, MultiplierPoint b) pure returns (bool) {
    return MultiplierPoint.unwrap(a) < MultiplierPoint.unwrap(b);
}

function gt(MultiplierPoint a, MultiplierPoint b) pure returns (bool) {
    return MultiplierPoint.unwrap(a) > MultiplierPoint.unwrap(b);
}
