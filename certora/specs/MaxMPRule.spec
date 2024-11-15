import "./shared.spec";

methods {
  function startTime() external returns (uint256) envfree;
  function currentEpoch() external returns (uint256) envfree;
}

function simplifyEpochProcessing(env e){
  require e.block.timestamp == _stakeManager.startTime();
  require _stakeManager.currentEpoch() == 0;
}

/* TODO: very usage of CONSTANT with Math.mulDiv or simplify mulDiv somehow, and replace simplifyEpochProcessing with reduceEpochProcessing

function reduceEpochProcessing(env e, uint256 maxEpochs) {
  require e.block.timestamp >= _stakeManager.startTime();
  uint256 currentEpoch = _stakeManager.currentEpoch();
  uint256 newEpoch = _stakeManager.newEpoch(e);
  require currentEpoch <= newEpoch;
  require currentEpoch - newEpoch <= maxEpochs;
}

function reduceAccountProcessing(env e, address addr, uint256 maxEpochs) {
  uint256 currentEpoch = _stakeManager.currentEpoch();
  uint256 accountEpoch = getAccountEpoch(addr);
  require accountEpoch <= currentEpoch;
  require accountEpoch >= currentEpoch - maxEpochs;
}
*/

invariant MPcantBeGreaterThanMaxMP(address addr)
  to_mathint(getAccountCurrentMultiplierPoints(addr)) <= to_mathint(getAccountMaxMultiplierPoints(addr))
  filtered {
    f -> f.selector != sig:migrateFrom(address,bool,StakeManager.Account).selector
  }
  { preserved with (env e) {
      simplifyEpochProcessing(e);
      /*reduceEpochProcessing(e, 3);
      reduceAccountProcessing(e, addr, 3);*/
      requireInvariant MaxMPIsNeverSmallerThanBalance(addr);
      requireInvariant CurrentMPIsNeverSmallerThanBalance(addr);
    }
  }

