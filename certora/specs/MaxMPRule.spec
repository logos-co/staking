import "./shared.spec";

methods {
  function accounts(address) external returns(address, uint256, uint256, uint256, uint256, uint256, uint256, uint256) envfree;
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

