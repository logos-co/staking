// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { StakeManager } from "./StakeManager.sol";

/**
 * @title StakeVault
 * @author Ricardo Guilherme Schmidt <ricardo3@status.im>
 * @notice Secures user stake
 */
contract StakeVault is Ownable {
    error StakeVault__MigrationNotAvailable();

    error StakeVault__InDepositCooldown();

    error StakeVault__InWithdrawCooldown();

    error StakeVault__DepositFailed();

    error StakeVault__WithdrawFailed();

    error StakeVault__InsufficientFunds();

    error StakeVault__InvalidLockTime();

    event Deposited(uint256 amount);

    event Withdrawn(uint256 amount);

    event Staked(uint256 _amount, uint256 time);

    StakeManager private stakeManager;

    ERC20 public immutable STAKED_TOKEN;

    uint256 public balance;

    uint256 public depositCooldownUntil;

    uint256 public withdrawCooldownUntil;

    modifier whenNotInDepositCooldown() {
        if (block.timestamp <= depositCooldownUntil) {
            revert StakeVault__InDepositCooldown();
        }
        _;
    }

    modifier whenNotInWithdrawCooldown() {
        if (block.timestamp <= withdrawCooldownUntil) {
            revert StakeVault__InWithdrawCooldown();
        }
        _;
    }

    modifier onlySufficientBalance(uint256 _amount) {
        uint256 availableFunds = _unstakedBalance();
        if (_amount > availableFunds) {
            revert StakeVault__InsufficientFunds();
        }
        _;
    }

    constructor(address _owner, ERC20 _stakedToken, StakeManager _stakeManager) {
        _transferOwnership(_owner);
        STAKED_TOKEN = _stakedToken;
        stakeManager = _stakeManager;
    }

    function deposit(uint256 _amount) external onlyOwner whenNotInDepositCooldown {
        depositCooldownUntil = block.timestamp + stakeManager.DEPOSIT_COOLDOWN_PERIOD();
        _deposit(msg.sender, _amount);
    }

    function withdraw(uint256 _amount) public onlyOwner whenNotInWithdrawCooldown onlySufficientBalance(_amount) {
        balance -= _amount;
        bool success = STAKED_TOKEN.transfer(msg.sender, _amount);
        if (!success) {
            revert StakeVault__WithdrawFailed();
        }
        emit Withdrawn(_amount);
    }

    function stake(
        uint256 _amount,
        uint256 _time
    )
        public
        onlyOwner
        whenNotInDepositCooldown
        onlySufficientBalance(_amount)
    {
        _stake(_amount, _time);
    }

    function depositAndStake(uint256 _amount, uint256 _time) external onlyOwner whenNotInDepositCooldown {
        uint256 stakedBalance = _stakedBalance();
        if (stakedBalance == 0 && _time == 0) {
            // we expect `depositAndStake` to be called either with a lock time,
            // or when there's already funds staked (because it's possible to top up stake without locking)
            revert StakeVault__InvalidLockTime();
        }
        _deposit(msg.sender, _amount);
        _stake(_amount, _time);
    }

    function lock(uint256 _time) external onlyOwner {
        stakeManager.lock(_time);
    }

    function unstake(uint256 _amount) external onlyOwner whenNotInWithdrawCooldown {
        withdrawCooldownUntil = block.timestamp + stakeManager.WITHDRAW_COOLDOWN_PERIOD();
        stakeManager.unstake(_amount);
    }

    function unstakeAndWithdraw(uint256 _amount) external onlyOwner {
        stakeManager.unstake(_amount);
        withdraw(_amount);
    }

    function leave() external onlyOwner {
        stakeManager.migrateTo(false);
        STAKED_TOKEN.transferFrom(address(this), msg.sender, STAKED_TOKEN.balanceOf(address(this)));
    }

    /**
     * @notice Opt-in migration to a new StakeManager contract.
     */
    function acceptMigration() external onlyOwner {
        StakeManager migrated = stakeManager.migrateTo(true);
        if (address(migrated) == address(0)) revert StakeVault__MigrationNotAvailable();
        stakeManager = migrated;
    }

    function stakedToken() external view returns (ERC20) {
        return STAKED_TOKEN;
    }

    function _deposit(address _from, uint256 _amount) internal {
        balance += _amount;
        bool success = STAKED_TOKEN.transferFrom(_from, address(this), _amount);
        if (!success) {
            revert StakeVault__DepositFailed();
        }
        emit Deposited(_amount);
    }

    function _stake(uint256 _amount, uint256 _time) internal {
        stakeManager.stake(_amount, _time);
        emit Staked(_amount, _time);
    }

    function _unstakedBalance() internal view returns (uint256) {
        (, uint256 stakedBalance,,,,,) = stakeManager.accounts(address(this));
        return balance - stakedBalance;
    }

    function _stakedBalance() internal view returns (uint256) {
        (, uint256 stakedBalance,,,,,) = stakeManager.accounts(address(this));
        return stakedBalance;
    }
}
