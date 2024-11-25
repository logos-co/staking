import "./IStakeManager.spec";

using ERC20A as staked;
using StakeManagerUpdated as newStakeManager;

methods {
  function staked.balanceOf(address) external returns (uint256) envfree;
  function totalStaked() external returns (uint256) envfree;
  function totalMP() external returns (uint256) envfree;
  function newStakeManager.PREVIOUS_MANAGER() external returns (address) envfree;

  function _.migrationInitialize(uint256,uint256,uint256,uint256,uint256,uint256,uint256) external => DISPATCHER(true);
  function newStakeManager.totalStaked() external returns (uint256) envfree;
}


invariant MaxMPIsNeverSmallerThanBalance(address addr)
  to_mathint(getAccountMaxMPs(addr)) >= to_mathint(getAccountBalance(addr))
  filtered {
    f -> f.selector != sig:StakeManagerUpdated.migrateFrom(address,bool,IStakeManager.Account).selector
  }

invariant CurrentMPIsNeverSmallerThanBalance(address addr)
  to_mathint(getAccountTotalMPs(addr)) >= to_mathint(getAccountBalance(addr))
  filtered {
    f -> f.selector != sig:StakeManagerUpdated.migrateFrom(address,bool,IStakeManager.Account).selector
  }



definition requiresPreviousManager(method f) returns bool = (
  f.selector == sig:StakeManagerUpdated.migrationInitialize(uint256,uint256,uint256,uint256,uint256,uint256,uint256).selector ||
  f.selector == sig:StakeManagerUpdated.migrateFrom(address,bool,IStakeManager.Account).selector ||
  f.selector == sig:StakeManagerUpdated.increaseTotalMP(uint256).selector
);


definition blockedWhenMigrating(method f) returns bool = (
  f.selector == sig:stake(uint256, uint256).selector ||
  f.selector == sig:unstake(uint256).selector ||
  f.selector == sig:lock(uint256).selector ||
  f.selector == sig:executeEpoch().selector ||
  f.selector == sig:executeEpoch(uint256).selector ||
  f.selector == sig:startMigration(address).selector ||
  f.selector == sig:StakeManagerUpdated.migrationInitialize(uint256,uint256,uint256,uint256,uint256,uint256,uint256).selector
);

definition blockedWhenNotMigrating(method f) returns bool = (
      f.selector == sig:acceptUpdate().selector ||
      f.selector == sig:leave().selector ||
      f.selector == sig:transferNonPending().selector
      );

rule rejectWhenMigrating(method f) filtered {
  f -> blockedWhenMigrating(f) && f.contract == currentContract
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
  f -> blockedWhenNotMigrating(f) && f.contract == currentContract
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
  assert newStakeManager.totalStaked() == currentContract.totalStaked();
}

rule migrationLockedIn(method f) filtered {
  f -> !blockedWhenMigrating(f) && f.contract == currentContract
} {
  env e;
  calldataarg args;

  require currentContract.migration != 0;

  f(e, args);

  assert currentContract.migration != 0;
}

rule epochStaysSameOnMigration(method f) filtered {
  f -> !blockedWhenMigrating(f) && f.contract == currentContract
} {
  env e;
  calldataarg args;

  uint256 epochBefore = currentContract.currentEpoch;
  require currentContract.migration != 0;

  f(e, args);

  assert currentContract.currentEpoch == epochBefore;
}
