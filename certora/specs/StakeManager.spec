using ERC20A as staked;
methods {
  function staked.balanceOf(address) external returns (uint256) envfree; 
  function stakeSupply() external returns (uint256) envfree; 
}

function isMigrationfunction(method f) returns bool {
  return  f.selector == sig:leave().selector ||
          f.selector == sig:migrate(address,StakeManager.Account).selector ||
          f.selector == sig:migrate().selector;
}

/*  assume that migration is zero, causing the verification to take into account only
 cases where it is zero. specifically no externall call to the migration contract */
function simplification() {
  require currentContract.migration == 0;  
}

ghost mathint sumOfBalances ; /* sigma account[u].balance forall u */
{
	init_state axiom sumOfBalances == 0;
} 

hook Sstore accounts[KEY address addr].balance uint256 newValue (uint256 oldValue) STORAGE {
    sumOfBalances = sumOfBalances - oldValue + newValue;
}

/*
//no need for this 
hook Sload uint256 balance _balances[KEY address addr] STORAGE {
    require sumOfBalances >= to_mathint(balance);
}
*/

invariant sumOfBalancesIsStakeSupply()
      sumOfBalances == to_mathint(stakeSupply());


rule reachability(method f) 
{
  calldataarg args;
  env e;
  f(e,args);
  satisfy true;
}

/** 
@title when there is no migration - some functions must revert. 
Other function should have non reverting cases 
**/
rule revertsWhenNoMigration(method f) {
  calldataarg args;
  env e;
  require currentContract.migration == 0;
  f@withrevert(e,args);
  bool reverted = lastReverted;
  if (!isMigrationfunction(f))
    satisfy !reverted;
  assert isMigrationfunction(f) => reverted;
}

rule whoChangeERC20Balance(  method f ) filtered { f -> f.contract != staked }
{
  address user;
  uint256 before = staked.balanceOf(user); 
  calldataarg args;
  env e;
  f(e,args);
  assert before == staked.balanceOf(user); 
}