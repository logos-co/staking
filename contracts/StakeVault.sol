// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "./StakeManager.sol";

/**
 * @title StakeVault
 * @author Ricardo Guilherme Schmidt <ricardo3@status.im>
 * @notice Secures user stake
 */
contract StakeVault {
    address owner;
    StakeManager stakeManager;

    ERC20 stakedToken;


    constructor(address _owner) public {
        owner = _owner;
    }

    function join(uint256 _amount, uint256 _time) external {
        stakedToken.transferFrom(msg.sender, address(this), amount);
        stakeManager.increaseBalance(amount, 0);
    }

    function leave(uint256 _amount) external {
        stakeManager.decreaseBalance(amount);
        stakedToken.transferFrom(address(this), msg.sender, amount);
    }

}