// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { IStakeManager } from "./IStakeManager.sol";

interface IStakeManagerUpdated is IStakeManager {
    function migrationInitialize(
        uint256 _currentEpoch,
        uint256 _totalMP,
        uint256 _totalStaked,
        uint256 _startTime,
        uint256 _totalMPRate,
        uint256 _potentialMP,
        uint256 _currentEpochExpiredMP
    )
        external;
    function migrateFrom(address _vault, bool _acceptMigration, Account memory _account) external;
    function increaseTotalMP(uint256 _amount) external;
}
