using ERC20A as staked;
using StakeManagerNew as newStakeManager;

methods {
  function staked.balanceOf(address) external returns (uint256) envfree;
  function stakeSupply() external returns (uint256) envfree;
  function multiplierSupply() external returns (uint256) envfree;
  function oldManager() external returns (address) envfree;
  function accounts(address) external returns(uint256, uint256, uint256, uint256, uint256, address) envfree;

  function _.migrationInitialize(uint256,uint256,uint256,uint256) external => DISPATCHER(true);
  function StakeManagerNew.stakeSupply() external returns (uint256) envfree;
  //function _.stakeSupply() external => DISPATCHER(true);
}


function getAccountMultiplierPoints(address addr) returns uint256 {
  uint256 multiplierPoints;
  _, _, multiplierPoints, _, _, _ = accounts(addr);

  return multiplierPoints;
}

function getAccountBalance(address addr) returns uint256 {
  uint256 balance;
  _, balance, _, _, _, _ = accounts(addr);

  return balance;
}

definition blockedWhenMigrating(method f) returns bool = (
      f.selector == sig:stake(uint256, uint256).selector ||
      f.selector == sig:unstake(uint256).selector ||
      f.selector == sig:lock(uint256).selector ||
      f.selector == sig:executeEpoch().selector ||
      f.selector == sig:startMigration(address).selector
      );

definition blockedWhenNotMigrating(method f) returns bool = (
      f.selector == sig:migrateTo(bool).selector ||
      f.selector == sig:transferNonPending().selector
      );

rule rejectWhenMigrating(method f) filtered {
  f -> blockedWhenMigrating(f)
} {
  calldataarg args;
  env e;

  require currentContract.migration != 0;

  f@withrevert(e, args);

  assert lastReverted;
}

rule allowWhenMigrating(method f) filtered {
  f -> !blockedWhenMigrating(f)
} {
  calldataarg args;
  env e;

  require currentContract.migration != 0;

  f@withrevert(e, args);

  satisfy !lastReverted;
}


rule rejectWhenNotMigrating(method f) filtered {
  f -> blockedWhenNotMigrating(f)
} {
  calldataarg args;
  env e;

  require currentContract.migration == 0;

  f@withrevert(e, args);

  assert lastReverted;
}

rule allowWhenNotMigrating(method f) filtered {
  f -> !blockedWhenNotMigrating(f)
} {
  calldataarg args;
  env e;

  require currentContract.migration == 0;

  f@withrevert(e, args);

  satisfy !lastReverted;
}

rule startMigrationCorrect {
  env e;
  address newContract = newStakeManager;

  startMigration(e, newContract);

  assert currentContract.migration == newContract;
  assert newStakeManager.stakeSupply() == currentContract.stakeSupply();
}

rule migrationLockedIn {
  method f;
  env e;
  calldataarg args;

  require currentContract.migration != 0;

  f(e, args);

  assert currentContract.migration != 0;
}

rule epochStaysSameOnMigration {
  method f;
  env e;
  calldataarg args;

  uint256 epochBefore = currentContract.currentEpoch;
  require currentContract.migration != 0;

  f(e, args);

  assert currentContract.currentEpoch == epochBefore;
}
