using ERC20A as staked;
using StakeManager as stakeManger; 
methods {
  function ERC20A.balanceOf(address) external returns (uint256) envfree; 
}

/*  assume that migration is zero, causing to ignore cases where it is not zero */
function simplification() {
  require stakeManger.migration == 0;  
}

rule reachability(method f){
  calldataarg args;
  env e;
  simplification();
  f(e,args);
  satisfy true;
}



rule whoChangeERC20Balance(  method f ) 
{
  simplification(); 
  address user;
  uint256 before = staked.balanceOf(user); 
  calldataarg args;
  env e;
  f(e,args);
  assert before == staked.balanceOf(user); 
} 