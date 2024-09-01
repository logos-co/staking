// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.0;

import "./StakeVault.sol";
import "./StakeManager.sol";
import { IERC20 } from "@openzeppelin/contracts/token/IERC20/IERC20.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

contract VaultManager is IERC4626 {
    using Math for uint256;
    error VaultFactory__InvalidStakeManagerAddress();

    StakeManager public stakeManager;
    IERC20 public assetToken;

    mapping(address => address vault) public vaults;
    mapping(address => address vault) public emptyVaults;


    modifier onlyVaultOwner(address _owner) {
        require(vaults[_owner] == msg.sender, "VaultManager: Only vault owner can call this function");
        _;
    }

    constructor(address _stakeManager) {
        if (_stakeManager == address(0)) {
            revert VaultFactory__InvalidStakeManagerAddress();
        }
        stakeManager = StakeManager(_stakeManager);
        assetToken = _stakeManager.stakedToken();
    }

    function mint(uint256 shares, address receiver) external returns (uint256 assets){
        return _stake(_convertToAssets(shares), receiver, 0);
    }

    function deposit(uint256 assets, address receiver) external returns (uint256 shares){
        return _stake(assets, receiver, 0);
    }
    function _updateStakeManager() internal {
        StakeManager currentStakeManager = stakeManager;
        while(currentStakeManager.migration() != address(0)) {
            currentStakeManager = currentStakeManager.migration();
        }
        stakeManager = currentStakeManager;
    }
    function _stake(uint256 assets, address _owner, uint256 secondsToLock) onlyVaultOwner(_owner) internal returns (uint256 shares){
        _updateStakeManager();
        StakeVault vault;
        if(emptyVaults[_owner].lenght > 0) {
            vault = StakeVault(emptyVaults[_owner][emptyVaults[_owner].lenght - 1]);
            while(vault.stakeManager().migration != address(0)) {
                vault.acceptMigration();
            }
            vaults[_owner].push(vault);
            emptyVaults[_owner].pop();
        } else {
            vault = new StakeVault(_owner, stakeManager.stakedToken(), address(this));
            vaults[_owner].push(address(vault));
        }
        assetToken.transferFrom(_owner, address(this), assets);
        assetToken.approve(address(vault), assets);
        vault.stake(assets, secondsToLock);
        shares = _convertToShares(assets);
        emit Deposit(msg.sender, _owner, assets, shares);
    }


    function redeem(uint256 _shares, address receiver, address _owner) onlyVaultOwner(_owner) external returns (uint256 assets){      
        uint256 shares = _shares;
        for (uint256 i = vaults[_owner].length; i > 0 ; i--) {
            address userVault = vaults[_owner][i-1];
            if (stakeManager.assetsLockedUntil(userVault) > block.timestamp) {
                uint256 vaultShares = stakeManager.balanceOf(userVault);
                if (_shares > vaultShares) {
                    uint256 userAssets = stakeManager.accountAssets(userVault);
                    shares -= vaultShares;
                    assets += userAssets;
                    StakeVault(userVault).unstake(userAssets, receiver);
                    vaults[_owner].pop();
                    emptyVaults[_owner].push(userVault);
                } else {
                    uint256 remainingAssets = _convertToAssets(shares);
                    assets += remainingAssets;
                    shares -= vaultShares;
                    StakeVault(userVault).unstake(remainingAssets, receiver);
                    break;
                }
            }
        }
        emit Withdraw(msg.sender, receiver, _owner, assets, _shares);
    }
    
    function withdraw(uint256 assets, address receiver, address _owner) onlyVaultOwner(_owner) external returns (uint256 shares){
        for (uint256 i = vaults[_owner].length; i > 0 ; i--) {
            address userVault = vaults[_owner][i-1];
            if (stakeManager.assetsLockedUntil(userVault) > block.timestamp) {
                uint256 userAssets = stakeManager.accountAssets(userVault);
                if (assets > userAssets) {
                    assets -= userAssets;
                    shares += stakeManager.balanceOf(userVault);
                    StakeVault(userVault).unstake(userAssets, receiver);
                    vaults[_owner].pop();
                    emptyVaults[_owner].push(userVault);
                } else {
                    shares += stakeManager.balanceOf(userVault);
                    StakeVault(userVault).unstake(assets, receiver);
                    break;
                }
            }
        }
        emit Withdraw(msg.sender, receiver, _owner, assets, shares);
    }

    function leave(address receiver, address _owner) onlyVaultOwner(_owner) external returns (uint256 assets){
        for (uint256 i = 0; i < vaults[_owner].length; i++) {
            StakeVault(vaults[_owner][i]).leave(receiver);
        }
    }

    function acceptMigration(address _owner) onlyVaultOwner(_owner) external {
        for (uint256 i = 0; i < vaults[_owner].length; i++) {
            StakeVault vault = StakeVault(vaults[_owner][i]);
            while(vault.stakeManager().migration != address(0)) {
                vault.acceptMigration();
            }
        }
    }

    // Functions for asset and total assets
    function asset() external view returns (address assetTokenAddress){
        return stakeManager.stakedToken();
    }
    
    function totalAssets() public view returns (uint256 totalManagedAssets){
        return stakeManager.totalSupplyBalance();
    }

    // Functions for conversion
    function convertToShares(uint256 assets) external view returns (uint256 shares){
        return _convertToShares(assets);
    }
    function convertToAssets(uint256 shares) external view returns (uint256 assets){
        return _convertToAssets(shares);
    }

    // Functions for deposit, mint, withdraw, and redeem
    function maxDeposit(address) external view returns (uint256 maxAssets){
        return type(uint256).max;
    }

    function maxMint(address ) external view returns (uint256 maxShares){
        return type(uint256).max;
    }

    function previewDeposit(uint256 assets) external view returns (uint256 shares){
        return _convertToShares(assets);
    }

    function previewMint(uint256 shares) external view returns (uint256 assets){
        return _convertToAssets(shares);
    }

    function maxWithdraw(address _owner) external view returns (uint256 maxAssets){
        for (uint256 i = 0; i < vaults[_owner].length; i++) {
            address userVault = vaults[_owner][i];
            if (stakeManager.assetsLockedUntil(userVault) > block.timestamp) {
                maxAssets += stakeManager.accountAssets(userVault);
            }
        }
        return maxAssets;
    }

    function maxRedeem(address _owner) external view returns (uint256 maxShares){
        for (uint256 i = 0; i < vaults[_owner].length; i++) {
            address userVault = vaults[_owner][i];
            if (stakeManager.assetsLockedUntil(userVault) > block.timestamp) {
                maxShares += stakeManager.balanceOf(userVault);
            }
        }
        return maxShares;
    }
    function previewWithdraw(uint256 assets) external view returns (uint256 shares){
        return _convertToShares(assets);
    }

    function previewRedeem(uint256 shares) external view returns (uint256 assets){
        return _convertToAssets(shares);
    }


    /**
     * @dev Internal conversion function (from assets to shares) with support for rounding direction.
     */
    function _convertToShares(uint256 assets) internal view virtual returns (uint256) {
        return assets.mulDiv(totalSupply() + 10 , totalAssets() + 1);
    }

    /**
     * @dev Internal conversion function (from shares to assets) with support for rounding direction.
     */
    function _convertToAssets(uint256 shares) internal view virtual returns (uint256) {
        return shares.mulDiv(totalAssets() + 1, totalSupply() + 10);
    }

    // Functions for ERC20
    function name() external view returns (string memory) {
        return assetToken.name();
    }

    function symbol() external view returns (string memory) {
        return assetToken.symbol();
    }

    function decimals() external view returns (uint8) {
        return assetToken.decimals();
    }

    function totalSupply() external view returns (uint256) {
        return stakeManager.totalSupply();
    }

    function balanceOf(address _owner) public view returns (uint256 assets){
        return _convertToAssets(stakeManager.balanceOf(_owner));
    }

     function transfer(address, uint256) external returns (bool) {
        revert();
        return false;
    }

    function transferFrom(address, address, uint256) external returns (bool) {
        revert();
        return false;
    }

    function approve(address, uint256) external returns (bool) {
        revert();
        return false;
    }

    function allowance(address, address) external view returns (uint256) {
        return 0;
    }
    

}