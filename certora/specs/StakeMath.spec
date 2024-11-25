import "./definition/DefinitionMath.spec";
import "./definition/DefinitionEpoch.spec";
import "./definition/DefinitionMultiplierPointsMath.spec";
import "./math/OpenZeppelinMath.spec";
import "./EpochMath.spec";
import "./IStakeManager.spec";

rule check_stake(
    uint256 _increasedAmount,
    uint256 _increasedLockSeconds
)
{
    env e;
    uint256 processTime = e.block.timestamp; 
    address addr = e.msg.sender;
    uint256 globalEpoch = currentEpoch();
    uint256 globalStartTime = START_TIME();
  
    requireValidSystem(processTime, globalStartTime, globalEpoch, 2);
    requireValidAccount(processTime, globalStartTime, globalEpoch, addr, 2);
    
    address initial_rewardAddress; 
    uint256 initial_balance;
    uint256 initial_maxMP;
    uint256 initial_totalMP;
    uint256 initial_lastMint;
    uint256 initial_lockUntil;
    uint256 initial_accountEpoch; 
    uint256 initial_accountStartTime;

    initial_rewardAddress, initial_balance, initial_maxMP, initial_totalMP, initial_lastMint, initial_lockUntil, initial_accountEpoch, initial_accountStartTime = accounts(addr);

    
    mathint calc_balance = initial_balance + _increasedAmount; 
    mathint calc_lockUntil = max(initial_lockUntil, processTime) + _increasedLockSeconds;
    mathint dt_lock = calc_lockUntil - processTime; 
    mathint calc_accountEpoch = newEpoch(e); 
    
    require calc_balance >= A_MIN();
    require dt_lock == 0 || dt_lock >= T_MIN();
    require dt_lock <= T_MAX();

    

    mathint delta_bonusMP_initial_balance = bonusMP(initial_balance, _increasedLockSeconds); 
    mathint delta_bonusMP_increasedAmount = bonusMP(_increasedAmount, dt_lock); 

    mathint delta_bonusMP = delta_bonusMP_initial_balance + delta_bonusMP_increasedAmount;
    mathint delta_accountEpoch = calc_accountEpoch - initial_accountEpoch;
    
    mathint calc_lastMint;
    if(initial_lastMint == 0){
        calc_lastMint = processTime;
    } else if (delta_accountEpoch == 0) {
        calc_lastMint = initial_lastMint;
    } else {
        calc_lastMint = epochStart(calc_accountEpoch, globalStartTime);
    }

    mathint delta_totalMP = initialMP(_increasedAmount) + delta_bonusMP; 
    mathint currentEpochAccrued = initial_accountEpoch < calc_accountEpoch ? accrueMP(initial_balance, epochStart(initial_accountEpoch+1, globalStartTime) - initial_lastMint) : 0; 
    mathint calc_accruedMP = initial_accountEpoch < calc_accountEpoch ? min(currentEpochAccrued + (accrueMP(initial_balance, T_RATE()) * (delta_accountEpoch-1)), initial_maxMP - initial_totalMP) : 0; 
    mathint calc_maxMP = initial_maxMP + delta_totalMP + accrueMP(_increasedAmount, MAX_MULTIPLIER() * YEAR());
    mathint calc_totalMP = initial_totalMP + delta_totalMP + calc_accruedMP;

    mathint calc_accountStartTime ;
    if(initial_accountStartTime == 0) {
        calc_accountStartTime = processTime;
    } else if (_increasedAmount > 0) {
        calc_accountStartTime = processTime - timeToAccrueMP(calc_balance, retrieveAccruedMP(calc_balance, calc_totalMP, calc_maxMP));
    } else {
        calc_accountStartTime = initial_accountStartTime;
    }

    stake(e, _increasedAmount, _increasedLockSeconds); 

    address final_rewardAddress; 
    uint256 final_balance;
    uint256 final_maxMP;
    uint256 final_totalMP;
    uint256 final_lastMint;
    uint256 final_lockUntil;
    uint256 final_accountEpoch;
    uint256 final_accountStartTime;
    final_rewardAddress, final_balance, final_maxMP, final_totalMP, final_lastMint, final_lockUntil, final_accountEpoch, final_accountStartTime = accounts(addr);

    //assert(final_rewardAddress == calc_rewardAddress); 
    assert(to_mathint(final_balance) == calc_balance); 
    assert(to_mathint(final_maxMP) == calc_maxMP); 
    assert(to_mathint(final_totalMP) == calc_totalMP); 
    assert(to_mathint(final_lastMint) == calc_lastMint);
    assert(to_mathint(final_lockUntil) == calc_lockUntil); 
    assert(to_mathint(final_accountEpoch) == calc_accountEpoch);
    assert(to_mathint(final_accountStartTime) == calc_accountStartTime);
}