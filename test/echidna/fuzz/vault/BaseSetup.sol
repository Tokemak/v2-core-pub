// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

/* solhint-disable func-name-mixedcase,max-states-count,max-line-length */

import { LMPVault } from "src/vault/LMPVault.sol";
import { TestERC20 } from "test/mocks/TestERC20.sol";
import { ILMPStrategy } from "src/interfaces/strategy/ILMPStrategy.sol";
import { ISystemRegistry } from "src/interfaces/ISystemRegistry.sol";
import { IAccessController } from "src/interfaces/security/IAccessController.sol";
import { IStrategy } from "src/interfaces/strategy/IStrategy.sol";
import { SystemRegistry } from "src/SystemRegistry.sol";
import { WETH9 } from "test/echidna/fuzz/mocks/WETH9.sol";
import { SystemSecurity } from "src/security/SystemSecurity.sol";
import { Clones } from "openzeppelin-contracts/proxy/Clones.sol";
import { MockRootOracle } from "test/echidna/fuzz/mocks/MockRootOracle.sol";
import { Math } from "openzeppelin-contracts/utils/math/Math.sol";
import { ILMPVault } from "src/interfaces/vault/ILMPVault.sol";
import { AutoPoolFees } from "src/vault/libs/AutoPoolFees.sol";
import { DestinationVault } from "src/vault/DestinationVault.sol";
import { IRootPriceOracle } from "src/interfaces/oracles/IRootPriceOracle.sol";
import { Numbers } from "test/echidna/fuzz/utils/Numbers.sol";
import { IERC20Metadata as IERC20 } from "openzeppelin-contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { DestinationVaultRegistry } from "src/vault/DestinationVaultRegistry.sol";
import { DestinationVaultFactory } from "src/vault/DestinationVaultFactory.sol";
import { DestinationRegistry } from "src/destinations/DestinationRegistry.sol";
import { IDestinationVault } from "src/interfaces/vault/IDestinationVault.sol";
import { LMPDebt } from "src/vault/libs/LMPDebt.sol";
import { IERC3156FlashBorrower } from "openzeppelin-contracts/interfaces/IERC3156FlashBorrower.sol";
import { hevm } from "test/echidna/fuzz/utils/Hevm.sol";
import { ILMPVaultRegistry } from "src/interfaces/vault/ILMPVaultRegistry.sol";
import { CryticIERC4626Internal } from "crytic/properties/contracts/ERC4626/util/IERC4626Internal.sol";
import { console } from "forge-std/console.sol";
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

    address internal _user1 = address(111);
    address internal _user2 = address(222);
    address internal _user3 = address(333);

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

        TestLMPVaultRegistry lmpVaultRegistry = new TestLMPVaultRegistry(_systemRegistry);
        _systemRegistry.setLMPVaultRegistry(address(lmpVaultRegistry));

        // Setup Strategy
        _strategy = new TestingStrategy();

        // Setup Pool
        TestingPool poolTemplate = new TestingPool(_systemRegistry, address(vaultAsset));
        _pool = TestingPool(Clones.clone(address(poolTemplate)));

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
        TestIncentiveCalculator dv1Calc = new TestIncentiveCalculator(address(_destVault1Underlyer));
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
        TestIncentiveCalculator dv2Calc = new TestIncentiveCalculator(address(_destVault2Underlyer));
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
        TestIncentiveCalculator dv3Calc = new TestIncentiveCalculator(address(_destVault3Underlyer));
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
    }
}

contract TestDestinationVault is DestinationVault, Numbers {
    int16 internal _nextBurnSlippage;

    constructor(ISystemRegistry sysRegistry) DestinationVault(sysRegistry) { }

    function setNextBurnSlippage(int16 slippage) public {
        _nextBurnSlippage = slippage;
    }

    function exchangeName() external pure override returns (string memory) {
        return "test";
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
        IRootPriceOracle oracle = _systemRegistry.rootPriceOracle();

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

contract TestingPool is LMPVault, CryticIERC4626Internal {
    bool private _disableNavDecreaseCheck;
    bool private _nextDepositGetsDoubleShares;
    bool private _enableCryticFns;
    LMPDebt.IdleDebtUpdates private _nextRebalanceResults;

    modifier cryticFns() {
        if (_enableCryticFns) {
            _;
        }
    }

    constructor(ISystemRegistry sr, address va) LMPVault(sr, va) { }

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

        _feeAndProfitHandling(startingTotalAssets + profit, startingTotalAssets);
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

        _feeAndProfitHandling(startingTotalAssets - loss, startingTotalAssets);
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
        ILMPVault.TotalAssetPurpose purpose
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

contract TestLMPVaultRegistry {
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
