import "./math/OpenZeppelinMath.spec";
import "./EpochMath.spec";
import "./IStakeManager.spec";
import "./MultiplierPointsMathSummarized.spec";


invariant MaxMPIsNeverSmallerThanBalance(address addr)
  to_mathint(getAccountMaxMPs(addr)) >= to_mathint(getAccountBalance(addr))
  { preserved with (env e) {
    requireValidState(e, 2);
  }
}

invariant CurrentMPIsNeverSmallerThanBalance(address addr)
  to_mathint(getAccountTotalMPs(addr)) >= to_mathint(getAccountBalance(addr))
  { preserved with (env e) {
      requireValidState(e, 2);
    }
  }

invariant MPcantBeGreaterThanMaxMP(address addr)
  to_mathint(getAccountTotalMPs(addr)) <= to_mathint(getAccountMaxMPs(addr))
  { preserved with (env e) {
      requireValidState(e, 2);
      requireInvariant MaxMPIsNeverSmallerThanBalance(addr);
      requireInvariant CurrentMPIsNeverSmallerThanBalance(addr);
    }
  }

