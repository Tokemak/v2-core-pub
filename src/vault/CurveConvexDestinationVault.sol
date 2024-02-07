// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

import { Errors } from "src/utils/Errors.sol";
import { LibAdapter } from "src/libs/LibAdapter.sol";
import { IWETH9 } from "src/interfaces/utils/IWETH9.sol";
import { DestinationVault } from "src/vault/DestinationVault.sol";
import { ISystemRegistry } from "src/interfaces/ISystemRegistry.sol";
import { ICurveResolver } from "src/interfaces/utils/ICurveResolver.sol";
import { IMainRewarder } from "src/interfaces/rewarders/IMainRewarder.sol";
import { IConvexBooster } from "src/interfaces/external/convex/IConvexBooster.sol";
import { ConvexStaking } from "src/destinations/adapters/staking/ConvexAdapter.sol";
import { IBaseRewardPool } from "src/interfaces/external/convex/IBaseRewardPool.sol";
import { ConvexRewards } from "src/destinations/adapters/rewards/ConvexRewardsAdapter.sol";
import { CurveV2FactoryCryptoAdapter } from "src/destinations/adapters/CurveV2FactoryCryptoAdapter.sol";
import { IERC20Metadata as IERC20 } from "openzeppelin-contracts/token/ERC20/extensions/IERC20Metadata.sol";

/// @notice Destination Vault to proxy a Curve Pool that goes into Convex
/// @dev Supports Curve V1 StableSwap, Curve V2 CryptoSwap, and Curve-ng pools
contract CurveConvexDestinationVault is DestinationVault {
    /// @notice Only used to initialize the vault
    struct InitParams {
        /// @notice Pool this vault proxies
        address curvePool;
        /// @notice Convex reward contract
        address convexStaking;
        /// @notice Numeric pool id used to reference Curve pool
        uint256 convexPoolId;
        /// @notice Coin index of token we'll perform withdrawals to
        uint256 baseAssetBurnTokenIndex;
    }

    string private constant EXCHANGE_NAME = "curve";

    /// @notice Coin index of token we'll perform withdrawals to
    address public immutable defaultStakingRewardToken;

    /// @notice Invalid coin index was provided for withdrawal
    error InvalidBaseTokenBurnIndex(uint256 provided, uint256 numTokens);

    /// @notice Pool is shutdown
    error PoolShutdown();

    /* ******************************** */
    /* State Variables                  */
    /* ******************************** */

    /// @notice Pool this vault proxies
    address public curvePool;

    /// @notice LP token this vault proxies
    /// @dev May be same as curvePool, depends on the pool type
    address public curveLpToken;

    /// @notice Convex reward contract
    address public convexStaking;

    /// @notice Convex Booster contract
    address public immutable convexBooster;

    /// @notice Numeric pool id used to reference Curve pool
    uint256 public convexPoolId;

    /// @notice Coin index of token we'll perform withdrawals to
    uint256 public baseAssetBurnTokenIndex;

    /// @dev Tokens that make up the LP token. Meta tokens not broken up
    address[] private constituentTokens;

    /// @dev Always 0, used as min amounts during withdrawals
    uint256[] private minAmounts;

    constructor(
        ISystemRegistry sysRegistry,
        address _defaultStakingRewardToken,
        address _convexBooster
    ) DestinationVault(sysRegistry) {
        // Zero is valid here if no default token is minted by the reward system
        // slither-disable-next-line missing-zero-check
        defaultStakingRewardToken = _defaultStakingRewardToken;

        Errors.verifyNotZero(_convexBooster, "_convexBooster");
        // slither-disable-next-line missing-zero-check
        convexBooster = _convexBooster;
    }

    ///@notice Support ETH operations
    receive() external payable { }

    /// @inheritdoc DestinationVault
    function initialize(
        IERC20 baseAsset_,
        IERC20 underlyer_,
        IMainRewarder rewarder_,
        address incentiveCalculator_,
        address[] memory additionalTrackedTokens_,
        bytes memory params_
    ) public virtual override {
        // Base class has the initializer() modifier to prevent double-setup
        // If you don't call the base initialize, make sure you protect this call
        super.initialize(baseAsset_, underlyer_, rewarder_, incentiveCalculator_, additionalTrackedTokens_, params_);

        // We must configure a the curve resolver to setup the vault
        ICurveResolver curveResolver = _systemRegistry.curveResolver();
        Errors.verifyNotZero(address(curveResolver), "curveResolver");

        // Decode the init params, validate, and save off
        InitParams memory initParams = abi.decode(params_, (InitParams));
        Errors.verifyNotZero(initParams.curvePool, "curvePool");
        Errors.verifyNotZero(initParams.convexStaking, "convexStaking");

        curvePool = initParams.curvePool;
        convexStaking = initParams.convexStaking;
        convexPoolId = initParams.convexPoolId;
        baseAssetBurnTokenIndex = initParams.baseAssetBurnTokenIndex;

        // Setup pool tokens as tracked. If we want to handle meta pools and their tokens
        // we will pass them in as additional, not currently a use case
        // slither-disable-next-line unused-return
        (address[8] memory tokens, uint256 numTokens, address curveQueriedLpToken,) =
            curveResolver.resolveWithLpToken(initParams.curvePool);

        Errors.verifyNotZero(numTokens, "numTokens");

        // slither-disable-next-line unused-return
        (address lpToken,,, address crvRewards,, bool _isShutdown) =
            IConvexBooster(convexBooster).poolInfo(initParams.convexPoolId);

        if (_isShutdown) {
            revert PoolShutdown();
        }

        Errors.verifyNotZero(lpToken, "lpToken");

        if (curveQueriedLpToken != lpToken) {
            revert Errors.InvalidParam("lpToken");
        }

        if (crvRewards != initParams.convexStaking) {
            revert Errors.InvalidParam("crvRewards");
        }

        for (uint256 i = 0; i < numTokens; ++i) {
            address weth = address(_systemRegistry.weth());
            address token = tokens[i] == LibAdapter.CURVE_REGISTRY_ETH_ADDRESS_POINTER ? weth : tokens[i];
            _addTrackedToken(token);
            constituentTokens.push(token);
        }

        if (baseAssetBurnTokenIndex > numTokens - 1) {
            revert InvalidBaseTokenBurnIndex(baseAssetBurnTokenIndex, numTokens);
        }

        // Initialize our min amounts for withdrawals to 0 for all tokens
        minAmounts = new uint256[](numTokens);

        // Checked above
        // slither-disable-next-line missing-zero-check
        curveLpToken = lpToken;
    }

    /// @inheritdoc DestinationVault
    /// @notice In this vault all underlyer should be staked externally, so internal debt should be 0.
    function internalDebtBalance() public pure override returns (uint256) {
        return 0;
    }

    /// @inheritdoc DestinationVault
    /// @notice In this vault all underlyer should be staked, and mint is 1:1, so external debt is `totalSupply()`.
    function externalDebtBalance() public view override returns (uint256) {
        return totalSupply();
    }

    /// @notice Get the balance of underlyer currently staked in Convex
    /// @return Balance of underlyer currently staked in Convex
    function externalQueriedBalance() public view override returns (uint256) {
        return IBaseRewardPool(convexStaking).balanceOf(address(this));
    }

    /// @inheritdoc DestinationVault
    function exchangeName() external pure override returns (string memory) {
        return EXCHANGE_NAME;
    }

    /// @inheritdoc DestinationVault
    function underlyingTokens() external view override returns (address[] memory result) {
        uint256 len = constituentTokens.length;
        result = new address[](len);
        for (uint256 i = 0; i < len; ++i) {
            result[i] = constituentTokens[i];
        }
    }

    /// @notice Callback during a deposit after the sender has been minted shares (if applicable)
    /// @dev Should be used for staking tokens into protocols, etc
    /// @param amount underlying tokens received
    function _onDeposit(uint256 amount) internal virtual override {
        ConvexStaking.depositAndStake(IConvexBooster(convexBooster), _underlying, convexStaking, convexPoolId, amount);
    }

    /// @inheritdoc DestinationVault
    function _ensureLocalUnderlyingBalance(uint256 amount) internal virtual override {
        ConvexStaking.withdrawStake(_underlying, convexStaking, amount);
    }

    /// @inheritdoc DestinationVault
    function _collectRewards() internal virtual override returns (uint256[] memory amounts, address[] memory tokens) {
        (amounts, tokens) =
            ConvexRewards.claimRewards(convexStaking, defaultStakingRewardToken, msg.sender, _trackedTokens);
    }

    /// @inheritdoc DestinationVault
    function _burnUnderlyer(uint256 underlyerAmount)
        internal
        virtual
        override
        returns (address[] memory tokens, uint256[] memory amounts)
    {
        // We withdraw everything in one coin to ease swapping
        // re: minAmount == 0, this call is only made during a user initiated withdraw where slippage is
        // controlled for at the router

        // We always want our tokens back in WETH so useEth false
        (tokens, amounts) = CurveV2FactoryCryptoAdapter.removeLiquidity(
            minAmounts, underlyerAmount, curvePool, curveLpToken, IWETH9(_systemRegistry.weth())
        );
    }

    /// @inheritdoc DestinationVault
    function getPool() external view override returns (address) {
        return curvePool;
    }
}
