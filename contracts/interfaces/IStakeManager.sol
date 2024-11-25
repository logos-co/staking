// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ITrustedCodehashAccess } from "./ITrustedCodehashAccess.sol";
import { IStakeConstants } from "./IStakeConstants.sol";

interface IStakeManager is IStakeConstants, ITrustedCodehashAccess {
    function STAKING_TOKEN() external view returns (IERC20);
    function REWARD_TOKEN() external view returns (IERC20);

    function stake(uint256 _amount, uint256 _seconds) external;
    function lock(uint256 _seconds) external;
    function unstake(uint256 _amount) external;

    function totalStaked() external view returns (uint256);
    function totalMP() external view returns (uint256);
    //function totalMaxMP() external view returns (uint256);
    function getStakedBalance(address _vault) external view returns (uint256 _balance);

    struct Account {
        address rewardAddress;
        uint256 balance;
        uint256 maxMP;
        uint256 totalMP;
        uint256 lastMint;
        uint256 lockUntil;
        uint256 epoch;
        uint256 startTime;
    }
}
