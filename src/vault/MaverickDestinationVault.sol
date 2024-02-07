// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

import { Errors } from "src/utils/Errors.sol";
import { DestinationVault } from "src/vault/DestinationVault.sol";
import { IPool } from "src/interfaces/external/maverick/IPool.sol";
import { ISystemRegistry } from "src/interfaces/ISystemRegistry.sol";
import { IRouter } from "src/interfaces/external/maverick/IRouter.sol";
import { IReward } from "src/interfaces/external/maverick/IReward.sol";
import { IPosition } from "src/interfaces/external/maverick/IPosition.sol";
import { IMainRewarder } from "src/interfaces/rewarders/IMainRewarder.sol";
import { IPoolPositionSlim } from "src/interfaces/external/maverick/IPoolPositionSlim.sol";
import { MaverickStakingAdapter } from "src/destinations/adapters/staking/MaverickStakingAdapter.sol";
import { MaverickRewardsAdapter } from "src/destinations/adapters/rewards/MaverickRewardsAdapter.sol";
import { IERC20Metadata as IERC20 } from "openzeppelin-contracts/token/ERC20/extensions/IERC20Metadata.sol";

contract MaverickDestinationVault is DestinationVault {
    error NothingToClaim();
    error NoDebtReclaimed();

    /// @notice Only used to initialize the vault
    struct InitParams {
        /// @notice Maverick swap and liquidity router
        address maverickRouter;
        /// @notice Maverick Boosted Position contract
        address maverickBoostedPosition;
        /// @notice Rewarder contract for the Boosted Position
        address maverickRewarder;
        /// @notice Pool that the Boosted Position proxies
        address maverickPool;
    }

    string private constant EXCHANGE_NAME = "maverick";

    /// @dev Tokens that make up the pool
    address[] private constituentTokens;

    /// @notice Maverick swap and liquidity router
    IRouter public maverickRouter;

    /// @notice Maverick Boosted Position contract
    IPoolPositionSlim public maverickBoostedPosition;

    /// @notice Rewarder contract for the Boosted Position
    IReward public maverickRewarder;

    /// @notice Pool that the Boosted Position proxies
    IPool public maverickPool;

    /// @notice Address Mavericks Position NFT
    IPosition public positionNft;

    error InvalidConfiguration();

    constructor(ISystemRegistry sysRegistry) DestinationVault(sysRegistry) { }

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

        // Decode the init params, validate, and save off
        InitParams memory initParams = abi.decode(params_, (InitParams));

        Errors.verifyNotZero(initParams.maverickRouter, "maverickRouter");
        Errors.verifyNotZero(initParams.maverickBoostedPosition, "maverickBoostedPosition");
        Errors.verifyNotZero(initParams.maverickRewarder, "maverickRewarder");
        Errors.verifyNotZero(initParams.maverickPool, "maverickPool");

        maverickRouter = IRouter(initParams.maverickRouter);
        maverickBoostedPosition = IPoolPositionSlim(initParams.maverickBoostedPosition);
        maverickRewarder = IReward(initParams.maverickRewarder);
        maverickPool = IPool(initParams.maverickPool);

        positionNft = IRouter(initParams.maverickRouter).position();
        address stakingToken = IReward(initParams.maverickRewarder).stakingToken();

        if (address(stakingToken) != address(_underlying)) {
            revert InvalidConfiguration();
        }

        address tokenA = address(IPool(initParams.maverickPool).tokenA());
        address tokenB = address(IPool(initParams.maverickPool).tokenB());
        _addTrackedToken(tokenA);
        _addTrackedToken(tokenB);

        constituentTokens = new address[](2);
        constituentTokens[0] = tokenA;
        constituentTokens[1] = tokenB;
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

    /// @notice Get the balance of underlyer currently staked in Maverick Rewarder
    /// @return Balance of underlyer currently staked in Maverick Rewarder
    function externalQueriedBalance() public view override returns (uint256) {
        return maverickRewarder.balanceOf(address(this));
    }

    /// @inheritdoc DestinationVault
    function exchangeName() external pure override returns (string memory) {
        return EXCHANGE_NAME;
    }

    /// @inheritdoc DestinationVault
    function underlyingTokens() external view override returns (address[] memory result) {
        result = new address[](2);
        for (uint256 i = 0; i < 2; ++i) {
            result[i] = constituentTokens[i];
        }
    }

    /// @notice Callback during a deposit after the sender has been minted shares (if applicable)
    /// @dev Should be used for staking tokens into protocols, etc
    /// @param amount underlying tokens received
    function _onDeposit(uint256 amount) internal virtual override {
        MaverickStakingAdapter.stakeLPs(maverickRewarder, amount);
    }

    /// @inheritdoc DestinationVault
    function _ensureLocalUnderlyingBalance(uint256 amount) internal virtual override {
        MaverickStakingAdapter.unstakeLPs(maverickRewarder, amount);
    }

    /// @inheritdoc DestinationVault
    function _collectRewards() internal virtual override returns (uint256[] memory amounts, address[] memory tokens) {
        (amounts, tokens) = MaverickRewardsAdapter.claimRewards(address(maverickRewarder), msg.sender);
    }

    /// @inheritdoc DestinationVault
    function _burnUnderlyer(uint256 underlyerAmount)
        internal
        virtual
        override
        returns (address[] memory tokens, uint256[] memory amounts)
    {
        //slither-disable-start similar-names
        (uint256 sellAmountA, uint256 sellAmountB) =
            maverickBoostedPosition.burnFromToAddressAsReserves(address(this), address(this), underlyerAmount);

        tokens = new address[](2);
        amounts = new uint256[](2);

        tokens[0] = constituentTokens[0];
        tokens[1] = constituentTokens[1];

        amounts[0] = sellAmountA;
        amounts[1] = sellAmountB;
        //slither-disable-end similar-names
    }

    /// @inheritdoc DestinationVault
    function getPool() external view override returns (address) {
        return address(maverickPool);
    }
}
