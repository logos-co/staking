// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ITrustedCodehashAccess } from "./access/ITrustedCodehashAccess.sol";

interface IStakeManager is ITrustedCodehashAccess {
    error StakeManager__FundsLocked();
    error StakeManager__InvalidLockTime();
    error StakeManager__InsufficientFunds();
    error StakeManager__StakeIsTooLow();

    function MIN_LOCKUP_PERIOD() external pure returns (uint256);
    function MAX_LOCKUP_PERIOD() external pure returns (uint256);

    function stake(uint256 _amount, uint256 _seconds) external;
    function unstake(uint256 _amount) external;
    function lock(uint256 _secondsIncrease) external;

    function acceptUpdate() external returns (IStakeManager _migrated);
    function leave() external returns (bool _leaveAccepted);

    function totalStaked() external view returns (uint256 _totalStaked);
    function getStakedBalance(address _vault) external view returns (uint256 _balance);
    function potentialMP() external view returns (uint256 _potentialMP);
    function totalMP() external view returns (uint256 _totalMP);

    function totalSupply() external view returns (uint256 _totalSupply);
    function totalSupplyMinted() external view returns (uint256 _totalSupply);
    function pendingReward() external view returns (uint256 _pendingReward);

    function calculateMP(uint256 _balance, uint256 _deltaTime) external pure returns (uint256);
}
