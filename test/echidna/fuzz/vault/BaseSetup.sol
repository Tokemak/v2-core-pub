// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

/* solhint-disable func-name-mixedcase,max-states-count,max-line-length,no-console,gas-custom-errors */

import { AutoPoolETH } from "src/vault/AutoPoolETH.sol";
import { TestERC20 } from "test/mocks/TestERC20.sol";
import { ILMPStrategy } from "src/interfaces/strategy/ILMPStrategy.sol";
import { ISystemRegistry } from "src/interfaces/ISystemRegistry.sol";
import { IStrategy } from "src/interfaces/strategy/IStrategy.sol";
import { SystemRegistry } from "src/SystemRegistry.sol";
import { WETH9 } from "test/echidna/fuzz/mocks/WETH9.sol";
import { SystemSecurity } from "src/security/SystemSecurity.sol";
import { Clones } from "openzeppelin-contracts/proxy/Clones.sol";
import { MockRootOracle } from "test/echidna/fuzz/mocks/MockRootOracle.sol";
import { Math } from "openzeppelin-contracts/utils/math/Math.sol";
import { IAutoPool } from "src/interfaces/vault/IAutoPool.sol";
import { DestinationVault } from "src/vault/DestinationVault.sol";
import { IRootPriceOracle } from "src/interfaces/oracles/IRootPriceOracle.sol";
import { Numbers } from "test/echidna/fuzz/utils/Numbers.sol";
import { DestinationVaultRegistry } from "src/vault/DestinationVaultRegistry.sol";
import { DestinationVaultFactory } from "src/vault/DestinationVaultFactory.sol";
import { DestinationRegistry } from "src/destinations/DestinationRegistry.sol";
import { IDestinationVault } from "src/interfaces/vault/IDestinationVault.sol";
import { LMPDebt } from "src/vault/libs/LMPDebt.sol";
import { IERC3156FlashBorrower } from "openzeppelin-contracts/interfaces/IERC3156FlashBorrower.sol";
import { CryticIERC4626Internal } from "crytic/properties/contracts/ERC4626/util/IERC4626Internal.sol";
import { TestIncentiveCalculator } from "test/mocks/TestIncentiveCalculator.sol";

contract BasePoolSetup {
    TestingStrategy internal _strategy;
    SystemRegistry internal _systemRegistry;
    SystemSecurity internal _systemSecurity;
    TestingAccessController internal _accessController;
    MockRootOracle internal _rootPriceOracle;

    WETH9 internal _weth;
    TestERC20 internal _toke;

    TestingPool internal _pool;

    TestDestinationVault internal _destVault1;
    TestERC20 internal _destVault1Underlyer;

    TestDestinationVault internal _destVault2;
    TestERC20 internal _destVault2Underlyer;

    TestDestinationVault internal _destVault3;
    TestERC20 internal _destVault3Underlyer;

    TestSolver internal _solver;

    address[] internal _destinations;
    address[] internal _users;

    uint256 internal _user1PrivateKey = 0x99e68c2e298699c8ce941a8fd1086fe4e19beeaa92a5dbcd35d3f47bb26e2894;
    address internal _user1 = address(0xc36846871EA9e4fb0C6eDE4961Ff5531d41Da053);

    uint256 internal _user2PrivateKey = 0x04dde89c5bb25286e5b5d5bee9ee1a136544b67d63b67d2fa181fa4c936442ff;
    address internal _user2 = address(0xbf56cdF1477215Ac338D4768ECa0C78b38D7E694);

    uint256 internal _user3PrivateKey = 0x986937dcc86261d55711604ed8600925a1d45224ad089c6cf3c3ab7ea1a3f362;
    address internal _user3 = address(0x73C689aa3121E38B15B0C9d46Fd9147214214c56);

    constructor() {
        _users = new address[](3);
        _users[0] = _user1;
        _users[1] = _user2;
        _users[2] = _user3;
    }

    function initializeBaseSetup(address vaultAsset) public {
        // Setup Assets
        _weth = new WETH9();

        _toke = new TestERC20("toke", "toke");

        _systemRegistry = new SystemRegistry(address(_toke), address(_weth));
        _systemRegistry.addRewardToken(address(vaultAsset));
        _systemRegistry.addRewardToken(address(_weth));
        _systemRegistry.addRewardToken(address(_toke));

        _accessController = new TestingAccessController(_systemRegistry);

        _systemRegistry.setAccessController(address(_accessController));

        _systemSecurity = new SystemSecurity(_systemRegistry);
        _systemRegistry.setSystemSecurity(address(_systemSecurity));

        TestAutoPoolRegistry autoPoolRegistry = new TestAutoPoolRegistry(_systemRegistry);
        _systemRegistry.setAutoPoolRegistry(address(autoPoolRegistry));

        // Setup Strategy
        _strategy = new TestingStrategy();

        // Setup Pool
        TestingPool poolTemplate = new TestingPool(_systemRegistry, address(vaultAsset));
        _pool = TestingPool(Clones.clone(address(poolTemplate)));

        _pool.setRewarder(address(vaultAsset));

        DestinationVaultRegistry destVaultRegistry = new DestinationVaultRegistry(_systemRegistry);
        _systemRegistry.setDestinationVaultRegistry(address(destVaultRegistry));

        DestinationRegistry destTemplateRegistry = new DestinationRegistry(_systemRegistry);
        _systemRegistry.setDestinationTemplateRegistry(address(destTemplateRegistry));

        DestinationVaultFactory destVaultFactory = new DestinationVaultFactory(_systemRegistry, 800, 800);
        destVaultRegistry.setVaultFactory(address(destVaultFactory));

        TestDestinationVault destVaultTemplate = new TestDestinationVault(_systemRegistry);

        bytes32 dvType = keccak256(abi.encode("template"));
        bytes32[] memory dvTypes = new bytes32[](1);
        dvTypes[0] = dvType;
        destTemplateRegistry.addToWhitelist(dvTypes);
        address[] memory dvAddresses = new address[](1);
        dvAddresses[0] = address(destVaultTemplate);
        destTemplateRegistry.register(dvTypes, dvAddresses);
        address[] memory additionalTrackedTokens = new address[](0);

        _destVault1Underlyer = new TestERC20("DV1", "DV1");
        TestIncentiveCalculator dv1Calc = new TestIncentiveCalculator();
        dv1Calc.setLpToken(address(_destVault1Underlyer));
        _destVault1 = TestDestinationVault(
            destVaultFactory.create(
                "template",
                address(vaultAsset),
                address(_destVault1Underlyer),
                address(dv1Calc),
                additionalTrackedTokens,
                keccak256("salt1"),
                abi.encode("")
            )
        );

        _destVault2Underlyer = new TestERC20("DV2", "DV2");
        TestIncentiveCalculator dv2Calc = new TestIncentiveCalculator();
        dv2Calc.setLpToken(address(_destVault2Underlyer));
        _destVault2 = TestDestinationVault(
            destVaultFactory.create(
                "template",
                address(vaultAsset),
                address(_destVault2Underlyer),
                address(dv2Calc),
                additionalTrackedTokens,
                keccak256("salt2"),
                abi.encode("")
            )
        );

        _destVault3Underlyer = new TestERC20("DV3", "DV3");
        TestIncentiveCalculator dv3Calc = new TestIncentiveCalculator();
        dv3Calc.setLpToken(address(_destVault3Underlyer));
        _destVault3 = TestDestinationVault(
            destVaultFactory.create(
                "template",
                address(vaultAsset),
                address(_destVault3Underlyer),
                address(dv3Calc),
                additionalTrackedTokens,
                keccak256("salt3"),
                abi.encode("")
            )
        );

        _destinations = new address[](3);
        _destinations[0] = address(_destVault1);
        _destinations[1] = address(_destVault2);
        _destinations[2] = address(_destVault3);
        _pool.addDestinations(_destinations);

        // Setup Oracle
        _rootPriceOracle = new MockRootOracle(address(_systemRegistry));
        _systemRegistry.setRootPriceOracle(address(_rootPriceOracle));

        _rootPriceOracle.setPrice(address(_toke), 1e18);
        _rootPriceOracle.setPrice(address(_weth), 1e18);
        _rootPriceOracle.setPrice(address(vaultAsset), 1e18);
        _rootPriceOracle.setPrice(address(_destVault1Underlyer), 1e18);
        _rootPriceOracle.setPrice(address(_destVault2Underlyer), 1e18);
        _rootPriceOracle.setPrice(address(_destVault3Underlyer), 1e18);

        _solver = new TestSolver();

        _pool.toggleAllowedUser(address(this));
        _pool.toggleAllowedUser(_user1);
        _pool.toggleAllowedUser(_user2);
        _pool.toggleAllowedUser(_user3);
        _pool.toggleAllowedUser(address(8));
        _pool.toggleAllowedUser(address(9));
        _pool.toggleAllowedUser(address(10));
    }
}

contract TestDestinationVault is DestinationVault, Numbers {
    int16 internal _nextBurnSlippage;

    constructor(ISystemRegistry sysRegistry) DestinationVault(sysRegistry) { }

    function setNextBurnSlippage(int16 slippage) public {
        _nextBurnSlippage = slippage;
    }

    function _validateCalculator(address calculator) internal virtual override { }

    function exchangeName() external pure override returns (string memory) {
        return "test";
    }

    function poolType() external pure override returns (string memory) {
        return "test";
    }

    function poolDealInEth() external pure override returns (bool) {
        return false;
    }

    function _ensureLocalUnderlyingBalance(uint256 amount) internal virtual override { }

    function burn(address account, uint256 amount) public {
        _burn(account, amount);
    }

    function _burnUnderlyer(uint256 underlyerAmount)
        internal
        virtual
        override
        returns (address[] memory tokens, uint256[] memory amounts)
    {
        TestERC20(_underlying).burn(address(this), underlyerAmount);

        // Just convert the tokens back based on price
        IRootPriceOracle oracle = systemRegistry.rootPriceOracle();

        uint256 underlyingPrice = oracle.getPriceInEth(_underlying);
        uint256 assetPrice = oracle.getPriceInEth(_baseAsset);
        uint256 amount = (underlyerAmount * underlyingPrice) / assetPrice;
        amount = tweak16(amount, _nextBurnSlippage);
        _nextBurnSlippage = 0;

        TestERC20(_baseAsset).mint(address(this), amount);

        tokens = new address[](1);
        tokens[0] = _baseAsset;

        amounts = new uint256[](1);
        amounts[0] = amount;
    }

    function _onDeposit(uint256 amount) internal virtual override { }

    function balanceOfUnderlyingDebt() public view override returns (uint256) {
        return TestERC20(_underlying).balanceOf(address(this));
    }

    function externalDebtBalance() public pure override returns (uint256) {
        return 0;
    }

    function internalDebtBalance() public pure override returns (uint256) {
        return 0;
    }

    function externalQueriedBalance() public pure override returns (uint256) {
        return 0;
    }

    function _collectRewards() internal virtual override returns (uint256[] memory amounts, address[] memory tokens) { }

    function getPool() public pure override returns (address) {
        return address(0);
    }

    function underlyingTokens() external pure override returns (address[] memory) {
        address[] memory x = new address[](0);
        return x;
    }
}

contract TestDestVaultRegistry {
    address public getSystemRegistry;

    constructor(address systemRegistry) {
        getSystemRegistry = systemRegistry;
    }

    function isRegistered(address) external pure returns (bool) {
        return true;
    }
}

contract TestingAccessController {
    address public getSystemRegistry;

    constructor(ISystemRegistry systemRegistry) {
        getSystemRegistry = address(systemRegistry);
    }

    function hasRole(bytes32, address) external pure returns (bool) {
        return true;
    }

    function verifyOwner(address) external view { }
}

contract TestingPool is AutoPoolETH, CryticIERC4626Internal {
    bool private _disableNavDecreaseCheck;
    bool private _nextDepositGetsDoubleShares;
    bool private _enableCryticFns;
    LMPDebt.IdleDebtUpdates private _nextRebalanceResults;

    modifier cryticFns() {
        if (_enableCryticFns) {
            _;
        }
    }

    constructor(ISystemRegistry sr, address va) AutoPoolETH(sr, va, false) { }

    function setCryticFnsEnabled(bool val) public {
        _enableCryticFns = val;
    }

    function setDisableNavDecreaseCheck(bool val) public {
        _disableNavDecreaseCheck = val;
    }

    function setNextDepositGetsDoubleShares(bool val) public {
        _nextDepositGetsDoubleShares = val;
    }

    function setNextRebalanceResult(LMPDebt.IdleDebtUpdates memory nextRebalanceResults) public {
        _nextRebalanceResults = nextRebalanceResults;
    }

    function increaseIdle(uint256 amount) public {
        _assetBreakdown.totalIdle += amount;

        TestERC20(address(_baseAsset)).mint(address(this), amount);
    }

    /// @notice Called by the Crytic property tests.
    function recognizeProfit(uint256 profit) public cryticFns {
        uint256 startingTotalAssets = totalAssets();
        _assetBreakdown.totalIdle += profit;

        TestERC20(address(_baseAsset)).mint(address(this), profit);

        _feeAndProfitHandling(startingTotalAssets + profit, startingTotalAssets, false);
    }

    /// @notice Called by the Crytic property tests.
    function recognizeLoss(uint256 loss) public cryticFns {
        uint256 startingTotalAssets = totalAssets();
        uint256 lossLeft = loss;

        // Figure out where to take the loss from
        if (_assetBreakdown.totalIdle >= loss) {
            _assetBreakdown.totalIdle -= loss;

            TestERC20(address(_baseAsset)).burn(address(this), loss);

            lossLeft = 0;
        }

        if (lossLeft > 0 && _assetBreakdown.totalIdle > 0) {
            lossLeft -= _assetBreakdown.totalIdle;

            TestERC20(address(_baseAsset)).burn(address(this), _assetBreakdown.totalIdle);

            _assetBreakdown.totalIdle = 0;
        }

        if (lossLeft > 0) {
            if (lossLeft > _assetBreakdown.totalDebt) {
                revert("er");
            }
            uint256 totalLossLeft = lossLeft;

            address[] memory destinations = getDestinations();
            for (uint256 i = 0; i < destinations.length; i++) {
                address destVault = destinations[i];
                LMPDebt.DestinationInfo memory destInfo = _destinationInfo[destVault];

                uint256 destSharesRemaining = IDestinationVault(destVault).balanceOf(address(this));
                if (destInfo.ownedShares > 0) {
                    // Each destination is going to take the loss proportionally
                    uint256 debtValueRemaining = destInfo.cachedDebtValue * destSharesRemaining / destInfo.ownedShares;

                    uint256 lossToTake =
                        Math.mulDiv(totalLossLeft, debtValueRemaining, _assetBreakdown.totalDebt, Math.Rounding.Up);

                    if (lossToTake > lossLeft) {
                        lossToTake = lossLeft;
                    }
                    if (lossToTake > debtValueRemaining) {
                        lossToTake = debtValueRemaining;
                    }

                    uint256 sharesToBurn =
                        Math.mulDiv(destSharesRemaining, lossToTake, debtValueRemaining, Math.Rounding.Up);
                    if (sharesToBurn > destSharesRemaining) {
                        sharesToBurn = destSharesRemaining;
                    }

                    TestERC20(address(IDestinationVault(destVault).underlying())).burn(destVault, sharesToBurn);
                    TestDestinationVault(destVault).burn(address(this), sharesToBurn);

                    _assetBreakdown.totalDebtMin -= _assetBreakdown.totalDebtMin * lossToTake / destInfo.cachedDebtValue;
                    _assetBreakdown.totalDebtMax -= _assetBreakdown.totalDebtMax * lossToTake / destInfo.cachedDebtValue;

                    destInfo.cachedMinDebtValue -= destInfo.cachedMinDebtValue * lossToTake / destInfo.cachedDebtValue;
                    destInfo.cachedMaxDebtValue -= destInfo.cachedMaxDebtValue * lossToTake / destInfo.cachedDebtValue;
                    destInfo.cachedDebtValue -= lossToTake;

                    lossLeft -= lossToTake;
                }
            }
            _assetBreakdown.totalDebt -= totalLossLeft;
        }

        require(lossLeft == 0, "lossNotZero");

        _feeAndProfitHandling(startingTotalAssets - loss, startingTotalAssets, false);
    }

    // function _processRebalance(
    //     IERC3156FlashBorrower receiver,
    //     RebalanceParams memory rebalanceParams,
    //     bytes calldata data
    // ) internal virtual override returns (LMPDebt.IdleDebtUpdates memory result) {
    //     result = _nextRebalanceResults;
    // }

    function _ensureNoNavPerShareDecrease(
        uint256 oldNav,
        uint256 startingTotalSupply,
        IAutoPool.TotalAssetPurpose purpose
    ) internal view override {
        if (!_disableNavDecreaseCheck) {
            super._ensureNoNavPerShareDecrease(oldNav, startingTotalSupply, purpose);
        }
    }

    function _transferAndMint(uint256 assets, uint256 shares, address receiver) internal virtual override {
        super._transferAndMint(assets, _nextDepositGetsDoubleShares ? shares * 2 : shares, receiver);
        _nextDepositGetsDoubleShares = false;
    }
}

contract TestSolver is Numbers, IERC3156FlashBorrower {
    struct Details {
        address tokenSent;
        uint256 amountSent;
        int16 amountTweak;
    }

    function onFlashLoan(
        address,
        address token,
        uint256 amount,
        uint256,
        bytes calldata data
    ) external override returns (bytes32) {
        Details memory details = abi.decode(data, (Details));

        TestERC20(details.tokenSent).burn(address(this), details.amountSent);
        TestERC20(token).mint(msg.sender, amount);

        return keccak256("ERC3156FlashBorrower.onFlashLoan");
    }
}

contract TestAutoPoolRegistry {
    address public getSystemRegistry;

    constructor(ISystemRegistry systemRegistry) {
        getSystemRegistry = address(systemRegistry);
    }

    function isVault(address) external pure returns (bool) {
        return true;
    }
}

contract TestingStrategy is ILMPStrategy {
    bool private _nextRebalanceSuccess;

    error BadRebalance();

    /// @notice the number of days to pause rebalancing due to NAV decay
    uint16 public immutable pauseRebalancePeriodInDays = 0;

    /// @notice the number of seconds gap between consecutive rebalances
    uint256 public immutable rebalanceTimeGapInSeconds = 0;

    /// @notice destinations trading a premium above maxPremium will be blocked from new capital deployments
    int256 public immutable maxPremium = 0; // 100% = 1e18

    /// @notice destinations trading a discount above maxDiscount will be blocked from new capital deployments
    int256 public immutable maxDiscount = 0; // 100% = 1e18

    /// @notice the allowed staleness of stats data before a revert occurs
    uint40 public immutable staleDataToleranceInSeconds = 0;

    /// @notice the swap cost offset period to initialize the strategy with
    uint16 public immutable swapCostOffsetInitInDays = 0;

    /// @notice the number of violations required to trigger a tightening of the swap cost offset period (1 to 10)
    uint16 public immutable swapCostOffsetTightenThresholdInViolations = 0;

    /// @notice the number of days to decrease the swap offset period for each tightening step
    uint16 public immutable swapCostOffsetTightenStepInDays = 0;

    /// @notice the number of days since a rebalance required to trigger a relaxing of the swap cost offset period
    uint16 public immutable swapCostOffsetRelaxThresholdInDays = 0;

    /// @notice the number of days to increase the swap offset period for each relaxing step
    uint16 public immutable swapCostOffsetRelaxStepInDays = 0;

    // slither-disable-start similar-names
    /// @notice the maximum the swap cost offset period can reach. This is the loosest the strategy will be
    uint16 public immutable swapCostOffsetMaxInDays = 0;

    /// @notice the minimum the swap cost offset period can reach. This is the most conservative the strategy will be
    uint16 public immutable swapCostOffsetMinInDays = 0;

    /// @notice the number of days for the first NAV decay comparison (e.g., 30 days)
    uint8 public immutable navLookback1InDays = 0;

    /// @notice the number of days for the second NAV decay comparison (e.g., 60 days)
    uint8 public immutable navLookback2InDays = 0;

    /// @notice the number of days for the third NAV decay comparison (e.g., 90 days)
    uint8 public immutable navLookback3InDays = 0;
    // slither-disable-end similar-names

    /// @notice the maximum slippage that is allowed for a normal rebalance
    uint256 public immutable maxNormalOperationSlippage = 0; // 100% = 1e18

    /// @notice the maximum amount of slippage to allow when a destination is trimmed due to constraint violations
    /// recommend setting this higher than maxNormalOperationSlippage
    uint256 public immutable maxTrimOperationSlippage = 0; // 100% = 1e18

    /// @notice the maximum amount of slippage to allow when a destinationVault has been shutdown
    /// shutdown for a vault is abnormal and means there is an issue at that destination
    /// recommend setting this higher than maxNormalOperationSlippage
    uint256 public immutable maxEmergencyOperationSlippage = 0; // 100% = 1e18

    /// @notice the maximum amount of slippage to allow when the LMPVault has been shutdown
    uint256 public immutable maxShutdownOperationSlippage = 0; // 100% = 1e18

    /// @notice the maximum discount used for price return
    int256 public immutable maxAllowedDiscount = 0; // 18 precision

    /// @notice model weight used for LSTs base yield, 1e6 is the highest
    uint256 public immutable weightBase = 0;

    /// @notice model weight used for DEX fee yield, 1e6 is the highest
    uint256 public immutable weightFee = 0;

    /// @notice model weight used for incentive yield
    uint256 public immutable weightIncentive = 0;

    /// @notice model weight used slashing costs
    uint256 public immutable weightSlashing = 0;

    /// @notice model weight applied to an LST discount when exiting the position
    int256 public immutable weightPriceDiscountExit = 0;

    /// @notice model weight applied to an LST discount when entering the position
    int256 public immutable weightPriceDiscountEnter = 0;

    /// @notice model weight applied to an LST premium when entering or exiting the position
    int256 public immutable weightPricePremium = 0;

    /// @notice initial value of the swap cost offset to use
    uint16 public immutable swapCostOffsetInit = 0;

    uint256 public immutable defaultLstPriceGapTolerance = 0;

    function setNextRebalanceSuccess(bool succeeds) public {
        _nextRebalanceSuccess = succeeds;
    }

    function verifyRebalance(
        IStrategy.RebalanceParams memory,
        IStrategy.SummaryStats memory
    ) external returns (bool, string memory message) {
        if (_nextRebalanceSuccess) {
            _nextRebalanceSuccess = false;
            return (true, "");
        } else {
            revert BadRebalance();
        }
    }

    function navUpdate(uint256) external { }

    function rebalanceSuccessfullyExecuted(IStrategy.RebalanceParams memory) external { }

    function getRebalanceOutSummaryStats(IStrategy.RebalanceParams memory)
        external
        returns (IStrategy.SummaryStats memory outSummary)
    { }
}
