using ERC20A as staked;
methods {
  function staked.balanceOf(address) external returns (uint256) envfree;
  function totalSupplyBalance() external returns (uint256) envfree;
  function accounts(address) external returns(address, uint256, uint256, uint256, uint256, uint256, uint256, uint256) envfree;

  function _processAccount(StakeManager.Account storage account, uint256 _limitEpoch) internal with(env e) => markAccountProccessed(e.msg.sender, _limitEpoch);
  function _.migrationInitialize(uint256,uint256,uint256,uint256) external => NONDET;
  function pendingMPToBeMinted() external returns (uint256) envfree;
}

// keeps track of the last epoch an account was processed
ghost mapping (address => mathint) accountProcessed;
// balance changed in an epoch that was processed
ghost mapping (address => mathint) balanceChangedInEpoch;

function markAccountProccessed(address account, uint256 _limitEpoch) {
    accountProcessed[account] = to_mathint(_limitEpoch);
}

function getAccountLockUntil(address addr) returns uint256 {
  uint256 lockUntil;
  _, _, _, _, _, lockUntil, _, _ = accounts(addr);

  return lockUntil;
}

hook Sstore accounts[KEY address addr].balance uint256 newValue (uint256 oldValue) {
    balanceChangedInEpoch[addr] = accountProcessed[addr];
}

definition requiresPreviousManager(method f) returns bool = (
  f.selector == sig:migrationInitialize(uint256,uint256,uint256,uint256).selector ||
  f.selector == sig:migrateFrom(address,bool,StakeManager.Account).selector ||
  f.selector == sig:increaseTotalMP(uint256).selector
  );

definition requiresNextManager(method f) returns bool = (
  f.selector == sig:migrateTo(bool).selector ||
  f.selector == sig:transferNonPending().selector
  );

/*
  If a balance of an account has changed, the account should have been processed up to the `currentEpoch`.
  This is filtering out most of migration related functions, as those will be vacuous.

  Verified on two mutations:
  https://prover.certora.com/output/40726/68668bbb7b6e49828da8521c3425a20b/?anonymousKey=015fce76d5d66ef40de8342b75fda4cff1dfdd57
  https://prover.certora.com/output/40726/055d52bc67154e3fbea330fd7d68d36d/?anonymousKey=73030555b4cefe429d4eed6718b9a7e5be3a22c8
*/
rule checkAccountProcessedBeforeStoring(method f) filtered {
  f -> !requiresPreviousManager(f) && !requiresNextManager(f)
} {
  address account;

  mathint lastChanged = balanceChangedInEpoch[account];
  env e;
  calldataarg args;

  require currentContract.migration == 0;

  // If the account's `lockUntil` == 0, then the account will be initialized
  // with the current epoch and no processing is required.
  require getAccountLockUntil(account) > 0;

  f(e,args);

  assert  balanceChangedInEpoch[account] != lastChanged  =>
          balanceChangedInEpoch[account] == to_mathint(currentContract.currentEpoch);

}

rule pendingMPToMintShouldNotBeBiggerTotalSupplyMP(method f) filtered {
  f -> !requiresPreviousManager(f) && !requiresNextManager(f)
} {

  calldataarg args;
  env e;
  address account;
  address account2;
  mathint amount;

  uint256 pendingMPBefore = currentContract.pendingMPToBeMinted();
  currentContract.stake(e, amount, 0);
  uint256 pendingMPAfter = currentContract.pendingMPToBeMinted();

  require e.block.timestamp > currentContract.currentEpoch()
  currentContract.executeAccount(account1)
  assert pendingMPAfter > pendingMPBefore;
}


/*
Below is a rule that finds all methods that change an account's balance.
This is just for debugging purposes and not meant to be a production rule.
Hence it is commented out.
*/
/*
rule whoChangeERC20Balance(  method f ) filtered { f -> f.contract != staked }
{
  address user;
  uint256 before = staked.balanceOf(user);
  calldataarg args;
  env e;
  f(e,args);
  assert before == staked.balanceOf(user);
} */
