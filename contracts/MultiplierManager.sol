 function getMaxMultiplierPoints() public view returns(uint256) {
        return balance * (stakeManager.MAX_BOOST() + lockup + 1);
    }

    
    function mintMultiplierPoints() internal {
        uint256 new_mp = multiplierPoints + (balance * stakeManager.MP_APY());
        uint256 max_mp = getMaxMultiplierPoints();
        multiplierPoints = new_mp > max_mp ? max_mp : new_mp;
    }

    function distriuteRewards() internal {
            uitn256 stakeApy = stakeManager.STAKE_APY();
        
            if(stakeApy > 0){
                return stake_apy * (balance + multiplierPoints);
            } else {
                uint256 cs = balance + multiplierPoints;
                uint256 rewards = stakeManager.getRewardEmissions();
                if(cs > 0){
                    return rewards * (balance + multiplierPoints) / cs;
                }
            }
                
    }
