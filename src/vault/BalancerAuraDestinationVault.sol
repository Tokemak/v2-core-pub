// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

import { Errors } from "src/utils/Errors.sol";
import { DestinationVault } from "src/vault/DestinationVault.sol";
import { BalancerUtilities } from "src/libs/BalancerUtilities.sol";
import { IVault } from "src/interfaces/external/balancer/IVault.sol";
import { ISystemRegistry } from "src/interfaces/ISystemRegistry.sol";
import { IERC20 } from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import { IMainRewarder } from "src/interfaces/rewarders/IMainRewarder.sol";
import { AuraStaking } from "src/destinations/adapters/staking/AuraAdapter.sol";
import { IConvexBooster } from "src/interfaces/external/convex/IConvexBooster.sol";
import { IBalancerPool } from "src/interfaces/external/balancer/IBalancerPool.sol";
import { AuraRewards } from "src/destinations/adapters/rewards/AuraRewardsAdapter.sol";
import { BalancerBeethovenAdapter } from "src/destinations/adapters/BalancerBeethovenAdapter.sol";
import { IERC20Metadata } from "openzeppelin-contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { IBalancerComposableStablePool } from "src/interfaces/external/balancer/IBalancerComposableStablePool.sol";

/// @title Destination Vault to proxy a Balancer Pool that goes into Aura
contract BalancerAuraDestinationVault is DestinationVault {
    /// @notice Only used to initialize the vault
    struct InitParams {
        /// @notice Pool and LP token this vault proxies
        address balancerPool;
        /// @notice Aura reward contract
        address auraStaking;
        /// @notice Aura Booster contract
        address auraBooster;
        /// @notice Numeric pool id used to reference Balancer pool
        uint256 auraPoolId;
    }

    string internal constant EXCHANGE_NAME = "balancer";

    /// @notice Balancer Vault
    IVault public immutable balancerVault;

    /// @notice Token minted during reward claiming. Specific to Convex-style rewards. Aura in this case.
    address public immutable defaultStakingRewardToken;

    /* ******************************** */
    /* State Variables                  */
    /* ******************************** */

    IERC20[] internal poolTokens;

    /// @notice Pool and LP token this vault proxies
    address public balancerPool;

    /// @notice Aura reward contract
    address public auraStaking;

    /// @notice Aura Booster contract
    address public auraBooster;

    /// @notice Numeric pool id used to reference balancer pool
    uint256 public auraPoolId;

    /// @notice Whether the balancePool is a ComposableStable pool. false -> MetaStable
    bool public isComposable;

    constructor(
        ISystemRegistry sysRegistry,
        address _balancerVault,
        address _defaultStakingRewardToken
    ) DestinationVault(sysRegistry) {
        Errors.verifyNotZero(_balancerVault, "_balancerVault");
        Errors.verifyNotZero(_defaultStakingRewardToken, "_defaultStakingRewardToken");

        // Both are checked above
        // slither-disable-next-line missing-zero-check
        balancerVault = IVault(_balancerVault);
        // slither-disable-next-line missing-zero-check
        defaultStakingRewardToken = _defaultStakingRewardToken;
    }

    /// @inheritdoc DestinationVault
    function initialize(
        IERC20Metadata baseAsset_,
        IERC20Metadata underlyer_,
        IMainRewarder rewarder_,
        address[] memory additionalTrackedTokens_,
        bytes memory params_
    ) public virtual override {
        // Base class has the initializer() modifier to prevent double-setup
        // If you don't call the base initialize, make sure you protect this call
        super.initialize(baseAsset_, underlyer_, rewarder_, additionalTrackedTokens_, params_);

        // Decode the init params, validate, and save off
        InitParams memory initParams = abi.decode(params_, (InitParams));
        Errors.verifyNotZero(initParams.balancerPool, "balancerPool");
        Errors.verifyNotZero(initParams.auraStaking, "auraStaking");
        Errors.verifyNotZero(initParams.auraBooster, "auraBooster");
        Errors.verifyNotZero(initParams.auraPoolId, "auraPoolId");

        balancerPool = initParams.balancerPool;
        auraStaking = initParams.auraStaking;
        auraBooster = initParams.auraBooster;
        auraPoolId = initParams.auraPoolId;
        isComposable = BalancerUtilities.isComposablePool(initParams.balancerPool);

        // Tokens that are used by the proxied pool cannot be removed from the vault
        // via recover(). Make sure we track those tokens here.
        bytes32 poolId = IBalancerPool(initParams.balancerPool).getPoolId();
        // Partial return values are intentionally ignored. This call provides the most efficient way to get the data.
        // slither-disable-next-line unused-return
        (IERC20[] memory balancerPoolTokens,,) = balancerVault.getPoolTokens(poolId);
        if (balancerPoolTokens.length == 0) revert ArrayLengthMismatch();
        poolTokens = balancerPoolTokens;

        for (uint256 i = 0; i < balancerPoolTokens.length; ++i) {
            _addTrackedToken(address(balancerPoolTokens[i]));
        }
    }

    /// @notice Get the balance of underlyer currently staked in Aura
    /// @return Balance of underlyer currently staked in Aura
    function externalBalance() public view override returns (uint256) {
        return IERC20(auraStaking).balanceOf(address(this));
    }

    /// @inheritdoc DestinationVault
    function exchangeName() external pure override returns (string memory) {
        return EXCHANGE_NAME;
    }

    /// @inheritdoc DestinationVault
    function underlyingTokens() external view override returns (address[] memory ret) {
        if (isComposable) {
            ret = new address[](poolTokens.length -1);
            uint256 bptIndex = IBalancerComposableStablePool(balancerPool).getBptIndex();
            uint256 h = 0;
            for (uint256 i = 0; i < poolTokens.length; ++i) {
                if (i != bptIndex) {
                    ret[h] = address(poolTokens[i]);
                    h++;
                }
            }
        } else {
            ret = _convertToAddresses(poolTokens);
        }
    }

    /// @inheritdoc DestinationVault
    function _onDeposit(uint256 amount) internal virtual override {
        AuraStaking.depositAndStake(IConvexBooster(auraBooster), _underlying, auraStaking, auraPoolId, amount);
    }

    /// @inheritdoc DestinationVault
    function _ensureLocalUnderlyingBalance(uint256 amount) internal virtual override {
        // We should almost always have our balance of LP tokens in Aura.
        // The exception being a donation we've made.
        // Withdraw from Aura back to this vault for use in a withdrawal
        uint256 balancerLpBalance = internalBalance();
        if (amount > balancerLpBalance) {
            AuraStaking.withdrawStake(balancerPool, auraStaking, amount - balancerLpBalance);
        }
    }

    /// @inheritdoc DestinationVault
    function _collectRewards() internal virtual override returns (uint256[] memory amounts, address[] memory tokens) {
        (amounts, tokens) = AuraRewards.claimRewards(auraStaking, defaultStakingRewardToken, msg.sender);
    }

    /// @inheritdoc DestinationVault
    function _burnUnderlyer(uint256 underlyerAmount)
        internal
        virtual
        override
        returns (address[] memory tokens, uint256[] memory amounts)
    {
        // Min amounts are intentionally 0. This fn is only called during a
        // user initiated withdrawal where they've accounted for slippage
        // at the router or otherwise
        uint256[] memory minAmounts = new uint256[](poolTokens.length);
        tokens = _convertToAddresses(poolTokens);
        amounts = isComposable
            ? BalancerBeethovenAdapter.removeLiquidity(
                balancerVault,
                balancerPool,
                BalancerUtilities._convertERC20sToAddresses(poolTokens),
                minAmounts,
                underlyerAmount
            )
            : BalancerBeethovenAdapter.removeLiquidityImbalance(
                balancerVault,
                balancerPool,
                underlyerAmount,
                BalancerUtilities._convertERC20sToAddresses(poolTokens),
                minAmounts
            );
    }

    function _convertToAddresses(IERC20[] memory tokens) internal pure returns (address[] memory assets) {
        //slither-disable-start assembly
        //solhint-disable-next-line no-inline-assembly
        assembly {
            assets := tokens
        }
        //slither-disable-end assembly
    }
}
