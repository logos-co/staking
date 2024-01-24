using ERC20A as staked;

methods {
  function staked.balanceOf(address) external returns (uint256) envfree;
  function stakeSupply() external returns (uint256) envfree;
  function multiplierSupply() external returns (uint256) envfree;
  function oldManager() external returns (address) envfree;
  function _.migrateFrom(address, bool, StakeManager.Account) external => NONDET;
  function _.increaseMPFromMigration(uint256) external => NONDET;
  function _.migrationInitialize(uint256,uint256,uint256,uint256) external => NONDET;

  function accounts(address) external returns(uint256, uint256, uint256, uint256, uint256, address) envfree;
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

function isMigrationfunction(method f) returns bool {
  return
          f.selector == sig:migrateFrom(address,bool,StakeManager.Account).selector ||
          f.selector == sig:migrateTo(bool).selector;
}

/*  assume that migration is zero, causing the verification to take into account only
 cases where it is zero. specifically no externall call to the migration contract */
function simplification(env e) {
  require e.msg.sender != 0;
  require currentContract.oldManager() == 0;
  require currentContract.migration == 0;
}

ghost mathint sumOfEpochRewards
{
  init_state axiom sumOfEpochRewards == 0;
}

ghost mathint sumOfBalances { /* sigma account[u].balance forall u */
	init_state axiom sumOfBalances == 0;
}

ghost mathint sumOfMultipliers /* sigma account[u].multiplier forall u */
{
	init_state axiom sumOfMultipliers == 0;
}

hook Sstore epochs[KEY uint256 epochId].epochReward uint256 newValue (uint256 oldValue) STORAGE {
  sumOfEpochRewards = sumOfEpochRewards - oldValue + newValue;
}

hook Sstore accounts[KEY address addr].balance uint256 newValue (uint256 oldValue) STORAGE {
    sumOfBalances = sumOfBalances - oldValue + newValue;
}

hook Sstore accounts[KEY address addr].multiplier uint256 newValue (uint256 oldValue) STORAGE {
    sumOfMultipliers = sumOfMultipliers - oldValue + newValue;
}

invariant sumOfBalancesIsStakeSupply()
      sumOfBalances == to_mathint(stakeSupply());

invariant sumOfMultipliersIsMultiplierSupply()
      sumOfMultipliers == to_mathint(multiplierSupply())
      { preserved with (env e) {
          simplification(e);
        }
      }

invariant sumOfEpochRewardsIsPendingRewards()
  sumOfEpochRewards == to_mathint(currentContract.pendingReward)
  { preserved {
    requireInvariant highEpochsAreNull(currentContract.currentEpoch);
  }
}

invariant highEpochsAreNull(uint256 epochNumber)
  epochNumber >= currentContract.currentEpoch => currentContract.epochs[epochNumber].epochReward == 0;


rule reachability(method f)
{
  calldataarg args;
  env e;
  f(e,args);
  satisfy true;
}

invariant MPcantBeGreaterThanMaxMP(address addr)
  to_mathint(getAccountMultiplierPoints(addr)) <= getAccountBalance(addr) * 8;

rule stakingMintsMultiplierPoints1To1Ratio {

  env e;
  uint256 amount;
  uint256 lockupTime;
  uint256 multiplierPointsBefore;
  uint256 multiplierPointsAfter;

  multiplierPointsBefore = getAccountMultiplierPoints(e.msg.sender);
  stake(e, amount, lockupTime);
  multiplierPointsAfter = getAccountMultiplierPoints(e.msg.sender);

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

  //require getAccountMultiplierPoints(e.msg.sender) == 0;

  storage initalStorage = lastStorage;

  stake(e, amount, lockupTime1);
  multiplierPointsAfter1 = getAccountMultiplierPoints(e.msg.sender);

  stake(e, amount, lockupTime2) at initalStorage;
  multiplierPointsAfter2 = getAccountMultiplierPoints(e.msg.sender);

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

rule whoChangeERC20Balance(  method f ) filtered { f -> f.contract != staked }
{
  address user;
  uint256 before = staked.balanceOf(user);
  calldataarg args;
  env e;
  f(e,args);
  assert before == staked.balanceOf(user);
}

rule epochOnlyIncreases {
  method f;
  env e;
  calldataarg args;

  uint256 epochBefore = currentContract.currentEpoch;

  f(e, args);

  assert currentContract.currentEpoch >= epochBefore;
}


//TODO codehash / isVault
/*
ghost mapping(address => bytes32) codehash;

hook EXTCODEHASH(address a) bytes32 hash {
    require hash == codehash[a];
}

rule checksCodeHash(method f) filtered {
  f -> requiresVault(f)
} {
  env e;

  bool isWhitelisted = isVault(codehash[e.msg.sender]);
  f(e);

  assert isWhitelisted;
}
*/
