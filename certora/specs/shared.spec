using StakeManager as _stakeManager;

methods {
  function StakeManager.accounts(address) external returns(address, uint256, uint256, uint256, uint256, uint256, uint256, uint256) envfree;
  function Math.mulDiv(uint256 a, uint256 b, uint256 c) internal returns uint256 => mulDivSummary(a, b, c);
}

function mulDivSummary(uint256 a, uint256 b, uint256 c) returns uint256 {
  require c != 0;
  return require_uint256(a*b/c);
}

definition requiresPreviousManager(method f) returns bool = (
  f.selector == sig:_stakeManager.migrationInitialize(uint256,uint256,uint256,uint256,uint256,uint256,uint256).selector ||
  f.selector == sig:_stakeManager.migrateFrom(address,bool,StakeManager.Account).selector ||
  f.selector == sig:_stakeManager.increaseTotalMP(uint256).selector
  );

definition requiresNextManager(method f) returns bool = (
  f.selector == sig:_stakeManager.acceptUpdate().selector ||
  f.selector == sig:_stakeManager.leave().selector ||
  f.selector == sig:_stakeManager.transferNonPending().selector
  );

function getAccountBalance(address addr) returns uint256 {
  uint256 balance;
  _, balance, _, _, _, _, _, _ = _stakeManager.accounts(addr);

  return balance;
}

function getAccountMaxMultiplierPoints(address addr) returns uint256 {
  uint256 maxMP;
  _, _, maxMP, _, _, _, _, _ = _stakeManager.accounts(addr);

  return maxMP;
}

function getAccountCurrentMultiplierPoints(address addr) returns uint256 {
  uint256 totalMP;
  _, _, _, totalMP, _, _, _, _  = _stakeManager.accounts(addr);

  return totalMP;
}

function getAccountLockUntil(address addr) returns uint256 {
  uint256 lockUntil;
  _, _, _, _, _, lockUntil, _, _  = _stakeManager.accounts(addr);

  return lockUntil;
}

function getAccountEpoch(address addr) returns uint256 {
  uint256 epoch;
  _, _, _, _, _, _, epoch, _ = _stakeManager.accounts(addr);
  return epoch;
}

invariant MaxMPIsNeverSmallerThanBalance(address addr)
  to_mathint(getAccountMaxMultiplierPoints(addr)) >= to_mathint(getAccountBalance(addr))
  filtered {
    f -> f.selector != sig:_stakeManager.migrateFrom(address,bool,StakeManager.Account).selector
  }

invariant CurrentMPIsNeverSmallerThanBalance(address addr)
  to_mathint(getAccountCurrentMultiplierPoints(addr)) >= to_mathint(getAccountBalance(addr))
  filtered {
    f -> f.selector != sig:_stakeManager.migrateFrom(address,bool,StakeManager.Account).selector
  }

