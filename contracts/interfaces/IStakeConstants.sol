// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { ITrustedCodehashAccess } from "./ITrustedCodehashAccess.sol";

interface IStakeConstants {
    function MIN_LOCKUP_PERIOD() external view returns (uint256);
    function MAX_LOCKUP_PERIOD() external view returns (uint256);
    function MP_APY() external view returns (uint256);
    function MAX_MULTIPLIER() external view returns (uint256);
}
