using ERC20A as staked;
using StakeManager as stakeManager;

methods {
  function ERC20A.balanceOf(address) external returns (uint256) envfree;
  function ERC20A.allowance(address, address) external returns(uint256) envfree;
  function ERC20A.totalSupply() external returns(uint256) envfree;
  function StakeManager.accounts(address) external returns(address, uint256, uint256, uint256, uint256, uint256, uint256, uint256) envfree;
  function _.migrateFrom(address, bool, StakeManager.Account) external => DISPATCHER(true);
  function _.increaseTotalMP(uint256) external => DISPATCHER(true);
  function _.owner() external => DISPATCHER(true);
  function Math.mulDiv(uint256 a, uint256 b, uint256 c) internal returns uint256 => mulDivSummary(a,b,c);
}

function mulDivSummary(uint256 a, uint256 b, uint256 c) returns uint256 {
  require c != 0;
  return require_uint256(a*b/c);
}

function getAccountBalance(address addr) returns uint256 {
  uint256 balance;
  _, balance, _, _, _, _, _, _ = stakeManager.accounts(addr);

  return balance;
}

definition isMigrationFunction(method f) returns bool = (
  f.selector == sig:stakeManager.migrationInitialize(uint256,uint256,uint256,uint256,uint256,uint256,uint256).selector ||
  f.selector == sig:stakeManager.migrateFrom(address,bool,StakeManager.Account).selector ||
  f.selector == sig:stakeManager.increaseTotalMP(uint256).selector ||
  f.selector == sig:stakeManager.startMigration(address).selector
  );

// check that the ERC20.balanceOf(vault) is >= to StakeManager.accounts[a].balance
invariant accountBalanceVsERC20Balance()
  staked.balanceOf(currentContract) >= getAccountBalance(currentContract)
  filtered {
    m -> m.selector != sig:leave().selector && !isMigrationFunction(m)
  }
  { preserved with (env e) {
      // the sender can't be the vault otherwise it can transfer tokens
      require e.msg.sender != currentContract;
      // nobody has allowance to spend the tokens of the vault
      require staked.allowance(currentContract, e.msg.sender) == 0;
      // if it's a generic transfer to the vault, it can't overflow
      require staked.balanceOf(currentContract) + staked.balanceOf(e.msg.sender) <= to_mathint(staked.totalSupply());
      // if it's a transfer from the StakeManager to the vault as reward address, it can't overflow
      require staked.balanceOf(currentContract) + staked.balanceOf(stakeManager) <= to_mathint(staked.totalSupply());
    }

    // the next blocked is run instead of the general one if the current function is staked.transferFrom.
    // if it's a transferFrom, we don't have the from in the first preserved block to check for an overflow
    preserved staked.transferFrom(address from, address to, uint256 amount) with (env e) {
      // if the msg.sender is the vault than it would be able to move tokens.
      // it would be possible only if the Vault contract called the ERC20.transferFrom.
      require e.msg.sender != currentContract;
      // no one has allowance to move tokens owned by the vault
      require staked.allowance(currentContract, e.msg.sender) == 0;
      require staked.balanceOf(from) + staked.balanceOf(to) <= to_mathint(staked.totalSupply());
    }

    preserved stake(uint256 amount, uint256 duration) with (env e) {

      require e.msg.sender != currentContract;

      require staked.balanceOf(currentContract) + staked.balanceOf(e.msg.sender) + staked.balanceOf(stakeManager) <= to_mathint(staked.totalSupply());
    }
  }



/*  assume that migration is zero, causing to ignore cases where it is not zero */
function simplification() {
  require stakeManager.migration == 0;
}

rule reachability(method f) filtered { f -> !isMigrationFunction(f) }
 {
  calldataarg args;
  env e;
  f(e,args);
  satisfy true;
}

/*
  The rule below is commented out as it's merely used to easily have the
  prover find all functions that change balances.

rule whoChangeERC20Balance(method f)
{
  simplification();
  address user;
  uint256 before = staked.balanceOf(user);
  calldataarg args;
  env e;
  f(e,args);
  assert before == staked.balanceOf(user);
}
*/
