// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import { Ownable2Step } from "@openzeppelin/contracts/access/Ownable2Step.sol";
import { StakeManager } from "./StakeManager.sol";
import { StakeVault } from "./StakeVault.sol";

/**
 * @title VaultFactory
 * @author 0x-r4bbit
 *
 * This contract is reponsible for creating staking vaults for users.
 * A user of the staking protocol is able to create multiple vaults to facilitate
 * different strategies. For example, a user may want to create a vault for
 * a long-term lock period, while also creating a vault that has no lock period
 * at all.
 *
 * @notice This contract is used by users to create staking vaults.
 * @dev This contract will be deployed by Status, making Status the owner of the contract.
 * @dev A contract address for a `StakeManager` has to be provided to create this contract.
 * @dev Reverts with {VaultFactory__InvalidStakeManagerAddress} if the provided
 * `StakeManager` address is zero.
 * @dev The `StakeManager` contract address can be changed by the owner.
 */
contract VaultFactory is Ownable2Step {
    error VaultFactory__InvalidStakeManagerAddress();

    event VaultCreated(address indexed vault, address indexed owner);
    event StakeManagerAddressChanged(address indexed newStakeManagerAddress);

    /// @dev Address of the `StakeManager` contract instance.
    StakeManager public stakeManager;

    /// @param _stakeManager Address of the `StakeManager` contract instance.
    constructor(address _stakeManager) {
        if (_stakeManager == address(0)) {
            revert VaultFactory__InvalidStakeManagerAddress();
        }
        stakeManager = StakeManager(_stakeManager);
    }

    /// @notice Sets the `StakeManager` contract address.
    /// @dev Only the owner can call this function.
    /// @dev Reverts if the provided `StakeManager` address is zero.
    /// @dev Emits a {StakeManagerAddressChanged} event.
    /// @param _stakeManager Address of the `StakeManager` contract instance.
    function setStakeManager(address _stakeManager) external onlyOwner {
        if (_stakeManager == address(0) || _stakeManager == address(stakeManager)) {
            revert VaultFactory__InvalidStakeManagerAddress();
        }
        stakeManager = StakeManager(_stakeManager);
        emit StakeManagerAddressChanged(_stakeManager);
    }

    /// @notice Creates an instance of a `StakeVault` contract.
    /// @dev Anyone can call this function.
    /// @dev Emits a {VaultCreated} event.
    function createVault() external returns (StakeVault) {
        StakeVault vault = new StakeVault(msg.sender, stakeManager.stakedToken(), stakeManager);
        emit VaultCreated(address(vault), msg.sender);
        return vault;
    }

    function createVault(address _owner, address _stakeManager, address _vaultManager) external returns (StakeVault) {
        StakeVault vault = new StakeVault(_owner, stakeManager.stakedToken(), stakeManager);
        emit VaultCreated(address(vault), _owner);
        return vault;
    }
}
