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

ghost mapping (address => uint256) accountProccsed;

function markAccountProccessed(address account, uint256 _limitEpoch) {
    accountProccsed[account] = _limitEpoch;
}

rule whenAccountProccsed(method f) {
  address account;
  uint256 before = accountProccsed[account];
  env e;
  calldataarg args;
  f(e,args);
  assert before == accountProccsed[account];
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