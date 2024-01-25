using ERC20A as staked;

methods {
  function staked.balanceOf(address) external returns (uint256) envfree;
  function stakeSupply() external returns (uint256) envfree;
  function multiplierSupply() external returns (uint256) envfree;
  function oldManager() external returns (address) envfree;
  function _.migrate(address, StakeManager.Account) external => NONDET;
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
  return  f.selector == sig:leave().selector ||
          f.selector == sig:migrate(address,StakeManager.Account).selector ||
          f.selector == sig:migrate().selector;
}

/*  assume that migration is zero, causing the verification to take into account only
 cases where it is zero. specifically no externall call to the migration contract */
function simplification(env e) {
  require e.msg.sender != 0;
  require currentContract.oldManager() == 0;
  require currentContract.migration == 0;
}

ghost mathint sumOfBalances { /* sigma account[u].balance forall u */
	init_state axiom sumOfBalances == 0;
}

ghost mathint sumOfMultipliers /* sigma account[u].multiplier forall u */
{
	init_state axiom sumOfMultipliers == 0;
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
