using ERC20A as staked;
methods {
  function staked.balanceOf(address) external returns (uint256) envfree; 
  function stakeSupply() external returns (uint256) envfree;

  function processAccount(StakeManager.Account storage account, uint256 _limitEpoch) internal with(env e) => markAccountProccessed(e.msg.sender, _limitEpoch ); 
}


/*  assume that migration is zero, causing the verification to take into account only
 cases where it is zero. specifically no externall call to the migration contract */
function simplification() {
  require currentContract.migration == 0;  
}

ghost mapping (address => mathint) accountProccsed;
// balance changed in an epoch thart was processed
ghost mapping (address => mathint) balanceChangedInEpoch;

function markAccountProccessed(address account, uint256 _limitEpoch) {
    accountProccsed[account] = to_mathint(_limitEpoch); 
}

hook Sstore accounts[KEY address addr].balance uint256 newValue (uint256 oldValue) STORAGE {
    balanceChangedInEpoch[addr] = accountProccsed[addr];
}


/*
if a balance of an acocunthas changed,
his account should have beeen process up to the currentEpoch

verified on two mutations:
https://prover.certora.com/output/40726/68668bbb7b6e49828da8521c3425a20b/?anonymousKey=015fce76d5d66ef40de8342b75fda4cff1dfdd57
https://prover.certora.com/output/40726/055d52bc67154e3fbea330fd7d68d36d/?anonymousKey=73030555b4cefe429d4eed6718b9a7e5be3a22c8

*/
rule checkAccountProccsedBeforeStoring(method f) {
  address account;

  mathint lastChanged = balanceChangedInEpoch[account]; 
  env e;
  calldataarg args;
  f(e,args);
  
  assert  balanceChangedInEpoch[account] != lastChanged  =>   
          balanceChangedInEpoch[account] == to_mathint(currentContract.currentEpoch);
  
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