using ERC20A as staked;
using StakeManager as stakeManager;
methods {
  function ERC20A.balanceOf(address) external returns (uint256) envfree;
}

/*  assume that migration is zero, causing to ignore cases where it is not zero */
function simplification() {
  require stakeManager.migration == 0;
}

rule reachability(method f){
  calldataarg args;
  env e;
  f(e,args);
  satisfy true;
}

/*
  The rule below is commented out as it's merely used to easily have the
  prover find all functions that change balances.

rule whoChangeERC20Balance(method f)
{
  simplification();
  address user;
  uint256 before = staked.balanceOf(user);
  calldataarg args;
  env e;
  f(e,args);
  assert before == staked.balanceOf(user);
}
*/
