// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.19;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import { Test, console } from "forge-std/Test.sol";
import { Deploy } from "../script/Deploy.s.sol";
import { DeployMigrationStakeManager } from "../script/DeployMigrationStakeManager.s.sol";
import { DeploymentConfig } from "../script/DeploymentConfig.s.sol";
import { TrustedCodehashAccess, StakeManager, ExpiredStakeStorage } from "../contracts/StakeManager.sol";
import { MultiplierPointMath } from "../contracts/MultiplierPointMath.sol";
import { StakeVault } from "../contracts/StakeVault.sol";
import { VaultFactory } from "../contracts/VaultFactory.sol";

contract DynamicTest is MultiplierPointMath, Test {
    DeploymentConfig internal deploymentConfig;
    StakeManager internal stakeManager;
    VaultFactory internal vaultFactory;

    address internal stakeToken;
    address internal deployer;
    address internal testUser = makeAddr("testUser");
    address internal testUser2 = makeAddr("testUser2");

    function setUp() public virtual {
        Deploy deployment = new Deploy();
        (vaultFactory, stakeManager, deploymentConfig) = deployment.run();
        (deployer, stakeToken) = deploymentConfig.activeNetworkConfig();
    }

    modifier withPrank(address _prankAddress) {
        vm.startPrank(_prankAddress);
        _;
        vm.stopPrank();
    }

    modifier fuzz_stake(uint256 _amount) {
        vm.assume(_amount > _calculateMinimumStake(stakeManager.EPOCH_SIZE()));
        vm.assume(_amount < 1e20);
        _;
    }

    modifier fuzz_lock(uint256 _seconds) {
        vm.assume(_seconds == 0 || _seconds > stakeManager.MIN_LOCKUP_PERIOD());
        vm.assume(_seconds == 0 || _seconds < stakeManager.MAX_LOCKUP_PERIOD());
        _;
    }

    modifier fuzz_unstake(uint256 _staked, uint256 _unstaked) {
        vm.assume(_unstaked > 0);
        vm.assume(_unstaked < _staked);
        _;
    }

    function _setTrustedCodehash(StakeVault _vault, bool _trusted) internal withPrank(deployer) {
        if (stakeManager.isTrustedCodehash(address(_vault).codehash) == _trusted) {
            stakeManager.setTrustedCodehash(address(_vault).codehash, _trusted);
        }
    }

    function _createVault(address _account) internal withPrank(_account) returns (StakeVault vault) {
        vm.prank(_account);
        vault = vaultFactory.createVault();
    }

    function _initializeVault(address _account) internal returns (StakeVault vault) {
        vault = _createVault(_account);
        _setTrustedCodehash(vault, true);
    }

    function _stake(StakeVault _vault, uint256 _amount, uint256 _lockedSeconds) internal withPrank(_vault.owner()) {
        ERC20(stakeToken).approve(address(_vault), _amount);
        _vault.stake(_amount, _lockedSeconds);
    }

    function _unstake(StakeVault _vault, uint256 _amount) internal withPrank(_vault.owner()) {
        _vault.unstake(_amount);
    }

    function _lock(StakeVault _vault, uint256 _lockedSeconds) internal withPrank(_vault.owner()) {
        _vault.unstake(_lockedSeconds);
    }

    enum VaultMethod {
        CREATE,
        STAKE,
        UNSTAKE,
        LOCK
    }
    enum VMMethod {
        VM_WARP
    }

    struct StageActions {
        VMAction[] vmActions;
        VaultAction[] vaultActions;
    }

    struct VaultAction {
        StakeVault vault;
        VaultMethod method;
        uint256[] args;
    }

    struct VMAction {
        VMMethod method;
        uint256[] args;
    }

    struct StageState {
        uint256 timestamp;
        VaultState[] vaultStates;
    }

    struct VaultState {
        StakeVault vault;
        uint256 increasedAccuredMP;
        uint256 predictedBonusMP;
        uint256 predictedAccuredMP;
        uint256 stakeAmount;
    }

    function _processStage(
        StageState memory _input,
        StageActions memory _action
    )
        internal
        pure
        returns (StageState memory output)
    {
        output = _input;
        for (uint256 i = 0; i < _action.vmActions.length; i++) {
            output = _processStage_VMAction_StageResult(output, _action.vmActions[i]);
        }
        for (uint256 i = 0; i < _action.vaultActions.length; i++) {
            output = _processStage_AccountAction_StageResult(output, _action.vaultActions[i]);
        }
    }

    function _processStage_VMAction_StageResult(
        StageState memory _input,
        VMAction memory _action
    )
        internal
        pure
        returns (StageState memory output)
    {
        if (_action.method == VMMethod.VM_WARP) {
            output.timestamp = _input.timestamp + _action.args[0];
            output.vaultStates = new VaultState[](_input.vaultStates.length);
            for (uint256 i = 0; i < _input.vaultStates.length; i++) {
                output.vaultStates[i] = _predict_VMAction_AccountState(_input.vaultStates[i], _action);
            }
        }
    }

    function _processStage_AccountAction_StageResult(
        StageState memory input,
        VaultAction memory action
    )
        internal
        pure
        returns (StageState memory output)
    {
        if (action.method == VaultMethod.CREATE) {
            output.vaultStates = new VaultState[](input.vaultStates.length + 1);
        } else {
            output.vaultStates = new VaultState[](input.vaultStates.length);
        }
        for (uint256 i = 0; i < input.vaultStates.length; i++) {
            output.vaultStates[i] = _predict_AccountAction_AccountState(input.vaultStates[i], action);
        }
    }

    function _predict_VMAction_AccountState(
        VaultState memory input,
        VMAction memory action
    )
        internal
        pure
        returns (VaultState memory output)
    {
        if (action.method == VMMethod.VM_WARP) {
            require(action.args.length == 1, "Incorrect number of arguments");
            output.stakeAmount = input.stakeAmount;
            output.predictedBonusMP = input.predictedBonusMP;
            output.increasedAccuredMP = _calculateAccuredMP(input.stakeAmount, action.args[0]);
            output.predictedAccuredMP = input.predictedAccuredMP + output.increasedAccuredMP;
        }
    }

    function _predict_AccountAction_AccountState(
        VaultState memory input,
        VaultAction memory action
    )
        internal
        pure
        returns (VaultState memory output)
    {
        if (
            action.method != VaultMethod.CREATE && action.vault != input.vault
                || action.method == VaultMethod.CREATE && address(input.vault) != address(0)
        ) {
            return input;
        }
        output.vault = input.vault;
        if (action.method == VaultMethod.CREATE) {
            //output.vault = _createVault(address(uint160(action.args[0])));
            output.stakeAmount = 0;
            output.predictedBonusMP = 0;
            output.increasedAccuredMP = 0;
            output.predictedAccuredMP = 0;
        } else if (action.method == VaultMethod.STAKE) {
            require(action.args.length == 2, "Incorrect number of arguments");
            output.stakeAmount = input.stakeAmount + action.args[0];
            output.predictedBonusMP = _calculateBonusMP(output.stakeAmount, action.args[1]);
            output.increasedAccuredMP = input.increasedAccuredMP;
            output.predictedAccuredMP = input.predictedAccuredMP;
        } else if (action.method == VaultMethod.UNSTAKE) {
            require(action.args.length == 1, "Incorrect number of arguments");
            output.stakeAmount = input.stakeAmount - action.args[0];
            output.predictedBonusMP = (output.stakeAmount * input.predictedBonusMP) / input.stakeAmount;
            output.increasedAccuredMP = input.increasedAccuredMP;
            output.predictedAccuredMP = (output.stakeAmount * input.predictedAccuredMP) / input.stakeAmount;
        } else if (action.method == VaultMethod.LOCK) {
            require(action.args.length == 1, "Incorrect number of arguments");
            output.stakeAmount = input.stakeAmount;
            output.predictedBonusMP = _calculateBonusMP(output.stakeAmount, action.args[0]);
            output.increasedAccuredMP = input.increasedAccuredMP;
            output.predictedAccuredMP = input.predictedAccuredMP + output.increasedAccuredMP;
        }
    }
    /*
    function testFuzz_UnstakeBonusMPAndAccuredMP(
        uint256 amountStaked,
        uint256 secondsLocked,
        uint256 reducedStake,
        uint256 increasedTime
    )
        public
        fuzz_stake(amountStaked)
        fuzz_unstake(amountStaked, reducedStake)
        fuzz_lock(secondsLocked)
    {
    
        //initialize memory placehodlders
        uint totalStages = 4;
        uint[totalStages] memory timestamp;
        AccountState[totalStages] memory globalParams;
        AccountState[totalStages][] memory userParams;
        StageActions[totalStages] memory actions;
        address[totalStages][] memory users;

        //stages variables setup
        uint stage = 0; // first stage =  initialization
        {
            actions[stage] = StageActions({
                timeIncrease: 0,
                userActions: [ UserActions({
                    stakeIncrease: amountStaked,
                    lockupIncrease: secondsLocked,
                    stakeDecrease: 0
                })]
            });
            timestamp[stage] = block.timestamp;
            users[stage] = [alice];
            userParams[stage] = new AccountState[](users[stage].length);
            {
                UserActions memory userActions = actions[stage].userActions[0];
                userParams[stage][0].stakeAmount = userActions.stakeIncrease;
        userParams[stage][0].predictedBonusMP = _calculateBonusMP(userActions.stakeIncrease,
        userActions.lockupIncrease);
                userParams[stage][0].increasedAccuredMP = 0; //no increased accured MP in first stage
                userParams[stage][0].predictedAccuredMP = 0; //no accured MP in first stage
            }
        }

        stage++; // second stage =  progress in time
        {
            actions[stage] = StageActions({
                timeIncrease: increasedTime,
                userActions: [UserActions({
                    stakeIncrease: 0,
                    lockupIncrease: 0,
                    stakeDecrease: 0
                })]
            });
            timestamp[stage] = timestamp[stage-1] + actions[stage].timeIncrease;
            users[stage] = users[stage-1]; //no new users in second stage
            userParams[stage] = new AccountState[](users[stage].length);
            {
                UserActions memory userActions = actions[stage].userActions[0];
        userParams[stage][0].stakeAmount = userParams[stage-1][0].stakeAmount; //no changes in stake at second stage
        userParams[stage][0].predictedBonusMP =  userParams[stage-1][0].predictedBonusMP; //no changes in bonusMP at
        second stage
        userParams[stage][0].increasedAccuredMP = _calculeAccuredMP(amountStaked, timestamp[stage] -
        timestamp[stage-1]);
        userParams[stage][0].predictedAccuredMP = userParams[stage-1][0].predictedAccuredMP +
        userParams[stage][0].increasedAccuredMP; 
            }
        }

        stage++; //third stage =  reduce stake
        {
            timestamp[stage] = timestamp[stage-1]; //no time increased in third stage
            users[stage] = users[stage-1]; //no new users in third stage
            userParams[stage] = new AccountState[](users[stage].length);
            {
                userParams[stage][0].stakeAmount = userParams[stage-1][0].stakeAmount - reducedStake;
    //bonusMP from this stage is a proportion from the difference of current stakeAmount and past stage stakeAmount
                //if the account reduced 50% of its stake, the bonusMP should be reduced by 50%
        userParams[stage][0].predictedBonusMP = (userParams[stage][0].stakeAmount *
        userParams[stage-1][0].predictedBonusMP) / userParams[stage-1][0].stakeAmount;
                userParams[stage][0].increasedAccuredMP = 0; //no accuredMP in third stage;
        //total accuredMP from this stage is a proportion from the difference of current stakeAmount and past stage
        stakeAmount
                //if the account reduced 50% of its stake, the accuredMP should be reduced by 50%
        userParams[stage][0].predictedAccuredMP = (userParams[stage][0].stakeAmount * predictedAccuredMP[stage-1]) /
        userParams[stage-1][0].stakeAmount;;
            }
        }

        // stages execution
        stage = 0; // first stage =  initialization
        {
            _stake(amountStaked, secondsLocked);
            for(uint i = 0; i < users[stage].length; i++) {
                RewardsStreamerMP.UserInfo memory userInfo = streamer.getUserInfo(users[stage][i]);
                assertEq(userInfo.stakedBalance, userParams[stage][i].stakeAmount, "wrong user staked balance");
        assertEq(userInfo.userMP, userParams[stage][i].predictedAccuredMP + userParams[stage][i].predictedBonusMP,
        "wrong user MP");
        assertEq(userInfo.maxMP, userParams[stage][i].stakeAmount * MAX_MULTIPLIER
        +userParams[stage][i].predictedBonusMP, "wrong user max MP");
                //sum all usersParams to globalParams
                globalParams[stage].stakeAmount += userParams[stage][i].stakeAmount;
                globalParams[stage].predictedBonusMP += userParams[stage][i].predictedBonusMP;
                globalParams[stage].increasedAccuredMP += userParams[stage][i].increasedAccuredMP;
                globalParams[stage].predictedAccuredMP += userParams[stage][i].predictedAccuredMP;
            }
            assertEq(streamer.totalStaked(), globalParams[stage].stakeAmount, "wrong total staked");
            assertEq(streamer.totalMP(), globalParams[stage].predictedBonusMP, "wrong total MP");
        assertEq(streamer.totalMaxMP(), globalParams[stage].stakeAmount * MAX_MULTIPLIER +
        globalParams[stage].predictedBonusMP, "wrong totalMaxMP MP");
        }

        stage++; // second stage =  progress in time
        {
            vm.warp(timestamp[stage]);
            for(uint i = 0; i < users[stage].length; i++) {
                RewardsStreamerMP.UserInfo memory userInfo = streamer.getUserInfo(users[stage][i]);
                assertEq(userInfo.stakedBalance, userParams[stage][i].stakeAmount, "wrong user staked balance");
        assertEq(userInfo.userMP, userParams[stage][i].predictedAccuredMP + userParams[stage][i].predictedBonusMP,
        "wrong user MP");
        assertEq(userInfo.maxMP, userParams[stage][i].stakeAmount * MAX_MULTIPLIER
        +userParams[stage][i].predictedBonusMP, "wrong user max MP");
                //sum all usersParams to globalParams
                globalParams[stage].stakeAmount += userParams[stage][i].stakeAmount;
                globalParams[stage].predictedBonusMP += userParams[stage][i].predictedBonusMP;
                globalParams[stage].increasedAccuredMP += userParams[stage][i].increasedAccuredMP;
                globalParams[stage].predictedAccuredMP += userParams[stage][i].predictedAccuredMP;
            }
            assertEq(streamer.totalStaked(), globalParams[stage].stakeAmount, "wrong total staked");
            assertEq(streamer.totalMP(), globalParams[stage].predictedBonusMP, "wrong total MP");
        assertEq(streamer.totalMaxMP(), globalParams[stage].stakeAmount * MAX_MULTIPLIER +
        globalParams[stage].predictedBonusMP, "wrong totalMaxMP MP");
        }

        stage++; // third stage =  reduce stake
        {
            _unstake(reducedStake);
            for(uint i = 0; i < users[stage].length; i++) {
                RewardsStreamerMP.UserInfo memory userInfo = streamer.getUserInfo(users[stage][i]);
                assertEq(userInfo.stakedBalance, userParams[stage][i].stakeAmount, "wrong user staked balance");
        assertEq(userInfo.userMP, userParams[stage][i].predictedAccuredMP + userParams[stage][i].predictedBonusMP,
        "wrong user MP");
        assertEq(userInfo.maxMP, userParams[stage][i].stakeAmount * MAX_MULTIPLIER +
        userParams[stage][i].predictedBonusMP, "wrong user max MP");
                //sum all usersParams to globalParams
                globalParams[stage].stakeAmount += userParams[stage][i].stakeAmount;
                globalParams[stage].predictedBonusMP += userParams[stage][i].predictedBonusMP;
                globalParams[stage].increasedAccuredMP += userParams[stage][i].increasedAccuredMP;
                globalParams[stage].predictedAccuredMP += userParams[stage][i].predictedAccuredMP;
            }
            assertEq(streamer.totalStaked(), globalParams[stage].stakeAmount, "wrong total staked");
            assertEq(streamer.totalMP(), globalParams[stage].predictedBonusMP, "wrong total MP");
        assertEq(streamer.totalMaxMP(), globalParams[stage].stakeAmount * MAX_MULTIPLIER +
        globalParams[stage].predictedBonusMP, "wrong totalMaxMP MP");
        }
    }*/
}
