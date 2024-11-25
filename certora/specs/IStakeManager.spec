import "./definition/DefinitionEpoch.spec";

methods {
    function potentialMP() external returns (uint256) envfree;
    function START_TIME() external returns (uint256) envfree;
    function currentEpoch() external returns (uint256) envfree;
    function accounts(address) external returns(address, uint256, uint256, uint256, uint256, uint256, uint256, uint256) envfree;
    function totalStaked() external returns (uint256) envfree;
    function totalMP() external returns (uint256) envfree;
    function getEpochStartTime(uint256) external returns (uint256) envfree;
    function totalMPRate() external returns (uint256) envfree;
    function getEpoch(uint) external returns (uint256) envfree;
    function MIN_LOCKUP_PERIOD() external returns (uint256) envfree;
    function MAX_LOCKUP_PERIOD() external returns (uint256) envfree;
    function YEAR() external returns (uint256) envfree;
    function MAX_MULTIPLIER() external returns (uint256) envfree;
    function MP_APY() external returns (uint256) envfree;
    function MP_MPY() external returns (uint256) envfree;
    function MP_MPY_ABSOLUTE() external returns (uint256) envfree;
    function ACCURE_RATE() external returns (uint256) envfree;
    function MIN_BALANCE() external returns (uint256) envfree;   
}

definition requiresNextManager(method f) returns bool = (
  f.selector == sig:acceptUpdate().selector ||
  f.selector == sig:leave().selector ||
  f.selector == sig:transferNonPending().selector
  );


function requireValidSystem(uint256 _processTime, uint256 _globalStartTime, uint256 _globalEpoch, uint256 _maxEpochsToProcess) {
    require _globalStartTime > 0;
    require _processTime >= START_TIME();
    mathint newEpoch = epoch(_processTime, _globalStartTime);
    require _globalEpoch <= newEpoch;
    require newEpoch - _globalEpoch <= _maxEpochsToProcess;
}

function simplifyEpochProcessing(uint256 _processTime, uint256 _globalStartTime, uint256 _globalEpoch) {
    require _processTime == _globalStartTime;
    require _globalEpoch == 0;
}

function requireValidAccount(uint256 _processTime, uint256 _globalStartTime, uint256 _globalEpoch, address _addr, uint256 _maxEpochsToProcess) {
    address rewardAddress; 
    uint256 balance;
    uint256 maxMP;
    uint256 totalMP;
    uint256 lastMint;
    uint256 lockUntil;
    uint256 accountEpoch;
    uint256 accountStartTime;
    rewardAddress, balance, maxMP, totalMP, lastMint, lockUntil, accountEpoch, accountStartTime = accounts(_addr);
    
    if(balance > 0){
        require balance >= MIN_BALANCE();
        require lastMint >= _globalStartTime;
        require lastMint <= _processTime;  
        require lastMint < epochStart(accountEpoch+1, _globalStartTime);
        require accountStartTime >= _globalStartTime;
        require accountStartTime <= lastMint;
        require lockUntil >= accountStartTime;
        require accountEpoch <= _globalEpoch;
        require accountEpoch >= _globalEpoch - _maxEpochsToProcess;   
        mathint lockTime = lockUntil - accountStartTime;
        require maxMP > maxTotalMP(balance, lockTime);
        require totalMP <= maxMP;
    } else {
        require accountStartTime == 0;
        require lastMint == 0;
        require rewardAddress == 0;
        require maxMP == 0;
        require totalMP == 0;
        require lockUntil == 0;
        require accountEpoch == 0;
    }
}

function requireValidState(env e, uint256 _maxEpochsToProcess) {
    uint256 processTime = e.block.timestamp; 
    address addr = e.msg.sender;
    uint256 globalEpoch = currentEpoch();
    uint256 globalStartTime = START_TIME();
    requireValidSystem(processTime, globalStartTime, globalEpoch, _maxEpochsToProcess);
    requireValidAccount(processTime, globalStartTime, globalEpoch, addr, _maxEpochsToProcess);
}
/**
struct Account {
        address rewardAddress;
        uint256 balance;
        uint256 maxMP;
        uint256 totalMP;
        uint256 lastMint;
        uint256 lockUntil;
        uint256 accountEpoch;
        uint256 _globalStartTime;
    }
**/


function getAccountBalance(address _addr) returns uint256 {
  uint256 balance;
  _, balance, _, _, _, _, _, _ = accounts(_addr);
  return balance;
}


function getAccountLastMint(address _addr) returns uint256 {
  uint256 lastMint;
  _, _, _, _, lastMint, _, _, _ = accounts(_addr);
  return lastMint;
}

function getAccountMaxMPs(address _addr) returns uint256 {
  uint256 maxMP;
  _, _, maxMP, _, _, _, _, _ = accounts(_addr);
  return maxMP;
}

function getAccountTotalMPs(address _addr) returns uint256 {
  uint256 totalMP;
  _, _, _, totalMP, _, _, _, _  = accounts(_addr);
  return totalMP;
}

function getAccountLockUntil(address _addr) returns uint256 {
  uint256 lockUntil;
  _, _, _, _, _, lockUntil, _, _  = accounts(_addr);
  return lockUntil;
}

function getAccountEpoch(address _addr) returns uint256 {
  uint256 accountEpoch;
  _, _, _, _, _, _, accountEpoch, _ = accounts(_addr);
  return accountEpoch;
}