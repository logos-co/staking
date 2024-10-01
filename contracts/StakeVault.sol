// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { StakeManager } from "./StakeManager.sol";

/**
 * @title StakeVault
 * @author Ricardo Guilherme Schmidt <ricardo3@status.im>
 * @notice A contract to secure user stakes and manage staking with StakeManager.
 * @dev This contract is owned by the user and allows staking, unstaking, and withdrawing tokens.
 */
contract StakeVault is Ownable {
    error StakeVault__NoEnoughAvailableBalance();
    error StakeVault__InvalidDestinationAddress();
    error StakeVault__MigrationNotAvailable();
    error StakeVault__StakingFailed();
    error StakeVault__UnstakingFailed();

    StakeManager private stakeManager;
    ERC20 public immutable STAKED_TOKEN;
    uint256 public amountStaked = 0;

    /**
     * @dev Emitted when tokens are staked.
     * @param from The address from which tokens are transferred.
     * @param to The address receiving the staked tokens (this contract).
     * @param amount The amount of tokens staked.
     * @param time The time period for which tokens are staked.
     */
    event Staked(address indexed from, address indexed to, uint256 amount, uint256 time);

    modifier validDestination(address _destination) {
        if (_destination == address(0)) {
            revert StakeVault__InvalidDestinationAddress();
        }
        _;
    }

    /**
     * @notice Initializes the contract with the owner, staked token, and stake manager.
     * @param _owner The address of the owner.
     * @param _stakedToken The ERC20 token to be staked.
     * @param _stakeManager The address of the StakeManager contract.
     */
    constructor(address _owner, ERC20 _stakedToken, StakeManager _stakeManager) {
        _transferOwnership(_owner);
        STAKED_TOKEN = _stakedToken;
        stakeManager = _stakeManager;
    }

    /**
     * @notice Stake tokens for a specified time.
     * @param _amount The amount of tokens to stake.
     * @param _time The time period to stake for.
     */
    function stake(uint256 _amount, uint256 _time) external onlyOwner {
        _stake(_amount, _time, msg.sender);
    }

    /**
     * @notice Stake tokens from a specified address for a specified time.
     * @param _amount The amount of tokens to stake.
     * @param _time The time period to stake for.
     * @param _from The address from which tokens will be transferred.
     */
    function stake(uint256 _amount, uint256 _time, address _from) external onlyOwner {
        _stake(_amount, _time, _from);
    }

    /**
     * @notice Extends the lock time of the stake.
     * @param _time The additional time to lock the stake.
     */
    function lock(uint256 _time) external onlyOwner {
        stakeManager.lock(_time);
    }

    /**
     * @notice Unstake a specified amount of tokens and send to the owner.
     * @param _amount The amount of tokens to unstake.
     */
    function unstake(uint256 _amount) external onlyOwner {
        _unstake(_amount, msg.sender);
    }

    /**
     * @notice Unstake a specified amount of tokens and send to a destination address.
     * @param _amount The amount of tokens to unstake.
     * @param _destination The address to receive the unstaked tokens.
     */
    function unstake(uint256 _amount, address _destination) external onlyOwner validDestination(_destination) {
        _unstake(_amount, _destination);
    }

    /**
     * @notice Withdraw tokens from the contract.
     * @param _token The ERC20 token to withdraw.
     * @param _amount The amount of tokens to withdraw.
     */
    function withdraw(ERC20 _token, uint256 _amount) external onlyOwner {
        _withdraw(_token, _amount, msg.sender);
    }

    /**
     * @notice Withdraw tokens from the contract to a destination address.
     * @param _token The ERC20 token to withdraw.
     * @param _amount The amount of tokens to withdraw.
     * @param _destination The address to receive the tokens.
     */
    function withdraw(
        ERC20 _token,
        uint256 _amount,
        address _destination
    )
        external
        onlyOwner
        validDestination(_destination)
    {
        _withdraw(_token, _amount, _destination);
    }

    /**
     * @notice Withdraw Ether from the contract to the owner address.
     * @param _amount The amount of Ether to withdraw.
     */
    function withdraw(uint256 _amount) external onlyOwner {
        _withdraw(_amount, payable(msg.sender));
    }

    /**
     * @notice Withdraw Ether from the contract to a destination address.
     * @param _amount The amount of Ether to withdraw.
     * @param _destination The address to receive the Ether.
     */
    function withdraw(
        uint256 _amount,
        address payable _destination
    )
        external
        onlyOwner
        validDestination(_destination)
    {
        _withdraw(_amount, _destination);
    }

    /**
     * @notice Reject migration, leave staking contract and withdraw all tokens to the owner.
     */
    function leave() external onlyOwner {
        _leave(msg.sender);
    }

    /**
     * @notice Reject migration, leave staking contract and withdraw all tokens to a destination address.
     * @param _destination The address to receive the tokens.
     */
    function leave(address _destination) external onlyOwner validDestination(_destination) {
        _leave(_destination);
    }

    /**
     * @notice Opt-in migration to a new StakeManager contract.
     * @dev Updates the stakeManager to the migrated contract.
     */
    function acceptMigration() external onlyOwner {
        StakeManager migrated = stakeManager.migrateTo(true);
        if (address(migrated) == address(0)) revert StakeVault__MigrationNotAvailable();
        stakeManager = migrated;
    }

    /**
     * @notice Returns the staked token.
     * @return The ERC20 staked token.
     */
    function stakedToken() external view returns (ERC20) {
        return STAKED_TOKEN;
    }

    /**
     * @notice Returns the available amount of a token that can be withdrawn.
     * @param _token The ERC20 token to check.
     * @return The amount of token available for withdrawal.
     */
    function availableWithdraw(ERC20 _token) external view returns (uint256) {
        if (_token == STAKED_TOKEN) {
            return STAKED_TOKEN.balanceOf(address(this)) - amountStaked;
        }
        return _token.balanceOf(address(this));
    }

    function _stake(uint256 _amount, uint256 _time, address _source) internal {
        amountStaked += _amount;
        bool success = STAKED_TOKEN.transferFrom(_source, address(this), _amount);
        if (!success) {
            revert StakeVault__StakingFailed();
        }

        stakeManager.stake(_amount, _time);

        emit Staked(_source, address(this), _amount, _time);
    }

    function _unstake(uint256 _amount, address _destination) internal {
        stakeManager.unstake(_amount);
        bool success = STAKED_TOKEN.transfer(_destination, _amount);
        amountStaked -= _amount;
        if (!success) {
            revert StakeVault__UnstakingFailed();
        }
    }

    function _leave(address _destination) internal {
        stakeManager.migrateTo(false);
        STAKED_TOKEN.transferFrom(address(this), _destination, STAKED_TOKEN.balanceOf(address(this)));
        amountStaked = 0;
    }

    function _withdraw(ERC20 _token, uint256 _amount, address _destination) internal {
        if (_token == STAKED_TOKEN && STAKED_TOKEN.balanceOf(address(this)) - amountStaked < _amount) {
            revert StakeVault__NoEnoughAvailableBalance();
        }
        _token.transfer(_destination, _amount);
    }

    function _withdraw(uint256 _amount, address payable _destination) internal {
        _destination.transfer(_amount);
    }
}
