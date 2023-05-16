// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

contract Staking {

    uint256 stake;
    uint256 max_boost;
    uint256 lockup;

    constructor() {

    }

    /// @notice Calculates the maximum multiplier points an account can have
    function max_mp() public view returns(uint256){
        return stake * (max_boost + lockup + 1);
    }

    /// @notice Create multiplier points for an account
    function mint_mp() public {
        /**
            factor = params['NUM_PERIODS_IN_YEAR']
            mp_apy = (params["MP_APY"]/100.)/factor

            # prev_state already accounts for partial state updates,
            # in case other policies were applied before this one.
            staked_tokens = prev_state['staked_tokens']
            mps = prev_state['staked_mps']
            max_staked_mps = prev_state['max_staked_mps']
            active = prev_state['active']

            delta_mps = active * np.minimum(
                staked_tokens * mp_apy, max_staked_mps - mps
            )
         */
    }

    /// @notice Create initial multiplier points for locked stake
    function inital_mp() public {
        /**
          return np.where(lockup>0, stake * (lockup + 1), 0.)
         */
    }

    /// @notice Distribute rewards
    function distribute_rewards() public {
        /**
            factor = params['NUM_PERIODS_IN_YEAR']
            stake_apy = (params['CUMULATIVE_STAKE_APY']/100.)/factor

            # prev_state already accounts for partial state updates,
            # in case other policies were applied before this one.
            staked = prev_state['staked_tokens']
            mps = prev_state['staked_mps']
            rewards = prev_state['rewards_emissions']
            active = prev_state['active']

            if stake_apy > 0.:
                delta_rewards_tokens = stake_apy * active * (staked + mps)

            else:
                cs = ((staked + mps) * active).sum()

                if cs > 0.:
                    delta_rewards_tokens = rewards * active * (staked + mps) / cs

                else:
                    delta_rewards_tokens = np.zeros_like(prev_state['staked_tokens'])
         */

    }

}