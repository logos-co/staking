// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "./StakeManager.sol";

contract StakeVault {
    address owner;
    StakeManager stakeManager;

    ERC20 stakedToken;
    uint256 balance;
    uint256 locked;
    uint256 unlockTime;
    uint256 lockedPeriod;
    uint256 multiplierPoints;

    function join(uint256 amount) external {
        _join(amount);
    }

    function lock(uint256 amount, uint256 time) external {
        _lock(amount,time);  
    }

    function joinAndLock(uint256 amount, uint256 time) external {
        _join(amount);
        _lock(amount,time);

    }

    function leave(uint256 amount) external {

    }

    function getMaxMultiplierPoints() public view returns(uint256) {
        return balance * (stakeManager.MAX_BOOST() + lockup + 1);
    }

    function _join(uint256 amount) internal {
        stakedToken.transferFrom(msg.sender, address(this), amount);
    }

    function _lock(uint256 amount, uint256 time) internal {
        require(time > 0, "Invalid lock time");
        lockedPeriod = time;
        unlockTime = now() + time;
        locked = amount;
        multiplierPoints += amount * (time + 1);
    }

    function mintMultiplierPoints() internal {
        uint256 new_mp = multiplierPoints + (balance * stakeManager.MP_APY());
        uint256 max_mp = getMaxMultiplierPoints();
        multiplierPoints = new_mp > max_mp ? max_mp : new_mp;
    }

    function distriuteRewards() internal {
            uitn256 stakeApy = stakeManager.STAKE_APY()
        
            if(stakeApy > 0){
                return stake_apy * (balance + multiplierPoints)
            } else {
                uint256 cs = balance + multiplierPoints
                uint256 rewards = stakeManager.getRewardEmissions();
                if(cs > 0){
                    return = rewards * (balance + multiplierPoints) / cs
                }
            }
                
    }

}