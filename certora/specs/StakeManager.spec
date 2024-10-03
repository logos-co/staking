import "./shared.spec";

using ERC20A as staked;

methods {
  function staked.balanceOf(address) external returns (uint256) envfree;
  function totalSupplyBalance() external returns (uint256) envfree;
  function totalSupplyMP() external returns (uint256) envfree;
  function previousManager() external returns (address) envfree;
  function _.migrateFrom(address, bool, StakeManager.Account) external => NONDET;
  function _.increaseTotalMP(uint256) external => NONDET;
  function _.migrationInitialize(uint256,uint256,uint256,uint256,uint256,uint256,uint256) external => NONDET;
  function accounts(address) external returns(address, uint256, uint256, uint256, uint256, uint256, uint256, uint256) envfree;
  function Math.mulDiv(uint256 a, uint256 b, uint256 c) internal returns uint256 => mulDivSummary(a,b,c);
  function _._ external => DISPATCH [] default NONDET;
}

function mulDivSummary(uint256 a, uint256 b, uint256 c) returns uint256 {
  require c != 0;
  return require_uint256(a*b/c);
}

function isMigrationfunction(method f) returns bool {
  return
          f.selector == sig:migrateTo(bool).selector ||
          f.selector == sig:transferNonPending().selector;
}

/*  assume that migration is zero, causing the verification to take into account only
 cases where it is zero. specifically no externall call to the migration contract */
function simplification(env e) {
  require currentContract.migration == 0;
  require currentContract.previousManager() == 0;
  require e.msg.sender != 0;
}

ghost mathint sumOfEpochRewards
{
  init_state axiom sumOfEpochRewards == 0;
}

ghost mathint sumOfMultipliers /* sigma account[u].multiplier forall u */
{
	init_state axiom sumOfMultipliers == 0;
}

ghost mathint sumOfBalances /* sigma account[u].balance forall u */ {
	init_state axiom sumOfBalances == 0;
}

hook Sstore epochs[KEY uint256 epochId].epochReward uint256 newValue (uint256 oldValue) {
  sumOfEpochRewards = sumOfEpochRewards - oldValue + newValue;
}

hook Sstore accounts[KEY address addr].balance uint256 newValue (uint256 oldValue) {
    sumOfBalances = sumOfBalances - oldValue + newValue;
}

hook Sstore accounts[KEY address addr].totalMP uint256 newValue (uint256 oldValue) {
    sumOfMultipliers = sumOfMultipliers - oldValue + newValue;
}

hook Sload uint256 newValue accounts[KEY address addr].totalMP {
    require sumOfMultipliers >= to_mathint(newValue);
}

invariant sumOfBalancesIsTotalSupplyBalance()
  sumOfBalances == to_mathint(totalSupplyBalance())
  filtered {
    m -> !requiresPreviousManager(m) && !requiresNextManager(m)
  }

invariant sumOfMultipliersIsMultiplierSupply()
  sumOfMultipliers == to_mathint(totalSupplyMP())
  filtered {
    m -> !requiresPreviousManager(m) && !requiresNextManager(m)
  }
  { preserved with (env e){
    requireInvariant accountMPIsZeroIfBalanceIsZero(e.msg.sender);
    requireInvariant accountBonusMPIsZeroIfBalanceIsZero(e.msg.sender);
    }
  }

invariant sumOfEpochRewardsIsPendingRewards()
  sumOfEpochRewards == to_mathint(currentContract.pendingReward)
  { preserved {
    requireInvariant highEpochsAreNull(currentContract.currentEpoch);
  }
}

invariant highEpochsAreNull(uint256 epochNumber)
  epochNumber >= currentContract.currentEpoch => currentContract.epochs[epochNumber].epochReward == 0
  filtered {
    m -> !requiresPreviousManager(m) && !requiresNextManager(m)
  }

invariant accountBonusMPIsZeroIfBalanceIsZero(address addr)
  to_mathint(getAccountBalance(addr)) == 0 => to_mathint(getAccountBonusMultiplierPoints(addr)) == 0
  filtered {
    f -> f.selector != sig:migrateFrom(address,bool,StakeManager.Account).selector
  }

invariant accountMPIsZeroIfBalanceIsZero(address addr)
  to_mathint(getAccountBalance(addr)) == 0 => to_mathint(getAccountCurrentMultiplierPoints(addr)) == 0
  filtered {
    f -> f.selector != sig:migrateFrom(address,bool,StakeManager.Account).selector
  }

invariant InitialMPIsNeverSmallerThanBalance(address addr)
  to_mathint(getAccountBonusMultiplierPoints(addr)) >= to_mathint(getAccountBalance(addr))
  filtered {
    f -> f.selector != sig:migrateFrom(address,bool,StakeManager.Account).selector
  }

invariant CurrentMPIsNeverSmallerThanInitialMP(address addr)
  to_mathint(getAccountCurrentMultiplierPoints(addr)) >= to_mathint(getAccountBonusMultiplierPoints(addr))
  filtered {
    f -> f.selector != sig:migrateFrom(address,bool,StakeManager.Account).selector
  }

invariant MPcantBeGreaterThanMaxMP(address addr)
  to_mathint(getAccountCurrentMultiplierPoints(addr)) <= (getAccountBalance(addr) * 8) + getAccountBonusMultiplierPoints(addr)
  filtered {
    f -> f.selector != sig:migrateFrom(address,bool,StakeManager.Account).selector
  }
  { preserved {
      requireInvariant InitialMPIsNeverSmallerThanBalance(addr);
      requireInvariant CurrentMPIsNeverSmallerThanInitialMP(addr);
    }
  }

rule reachability(method f)
{
  calldataarg args;
  env e;
  f(e,args);
  satisfy true;
}

rule stakingMintsMultiplierPoints1To1Ratio {

  env e;
  uint256 amount;
  uint256 lockupTime;
  uint256 multiplierPointsBefore;
  uint256 multiplierPointsAfter;

  requireInvariant InitialMPIsNeverSmallerThanBalance(e.msg.sender);
  requireInvariant CurrentMPIsNeverSmallerThanInitialMP(e.msg.sender);
  requireInvariant accountMPIsZeroIfBalanceIsZero(e.msg.sender);

  require getAccountLockUntil(e.msg.sender) <= e.block.timestamp;

  multiplierPointsBefore = getAccountBonusMultiplierPoints(e.msg.sender);
  stake(e, amount, lockupTime);
  multiplierPointsAfter = getAccountBonusMultiplierPoints(e.msg.sender);

  assert lockupTime == 0 => to_mathint(multiplierPointsAfter) == multiplierPointsBefore + amount;
  assert to_mathint(multiplierPointsAfter) >= multiplierPointsBefore + amount;
}

rule stakingGreaterLockupTimeMeansGreaterMPs {

  env e;
  uint256 amount;
  uint256 lockupTime1;
  uint256 lockupTime2;
  uint256 multiplierPointsAfter1;
  uint256 multiplierPointsAfter2;

  storage initalStorage = lastStorage;

  stake(e, amount, lockupTime1);
  multiplierPointsAfter1 = getAccountBonusMultiplierPoints(e.msg.sender);

  stake(e, amount, lockupTime2) at initalStorage;
  multiplierPointsAfter2 = getAccountBonusMultiplierPoints(e.msg.sender);

  assert lockupTime1 >= lockupTime2 => to_mathint(multiplierPointsAfter1) >= to_mathint(multiplierPointsAfter2);
  satisfy to_mathint(multiplierPointsAfter1) > to_mathint(multiplierPointsAfter2);
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

// This rule is commented out as it's just a helper rule to easily see which
// functions change the balance of the `StakeManager` contract.
//
// rule whoChangeERC20Balance(  method f ) filtered { f -> f.contract != staked }
// {
//   address user;
//   uint256 before = staked.balanceOf(user);
//   calldataarg args;
//   env e;
//   f(e,args);
//   assert before == staked.balanceOf(user);
// }

rule epochOnlyIncreases(method f) {
  env e;
  calldataarg args;

  uint256 epochBefore = currentContract.currentEpoch;

  f(e, args);

  assert currentContract.currentEpoch >= epochBefore;
}


//TODO codehash / isTrustedCodehash
/*
ghost mapping(address => bytes32) codehash;

hook EXTCODEHASH(address a) bytes32 hash {
    require hash == codehash[a];
}

rule checksCodeHash(method f) filtered {
  f -> requiresVault(f)
} {
  env e;

  bool isWhitelisted = isTrustedCodehash(codehash[e.msg.sender]);
  f(e);

  assert isWhitelisted;
}
*/
