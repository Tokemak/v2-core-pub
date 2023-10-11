// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

// solhint-disable max-states-count

import { Roles } from "src/libs/Roles.sol";
import { Errors } from "src/utils/Errors.sol";
import { LMPDebt } from "src/vault/libs/LMPDebt.sol";
import { Pausable } from "src/security/Pausable.sol";
import { VaultTypes } from "src/vault/VaultTypes.sol";
import { NonReentrant } from "src/utils/NonReentrant.sol";
import { SystemComponent } from "src/SystemComponent.sol";
import { LMPStrategy } from "src/strategy/LMPStrategy.sol";
import { SecurityBase } from "src/security/SecurityBase.sol";
import { ILMPVault } from "src/interfaces/vault/ILMPVault.sol";
import { IStrategy } from "src/interfaces/strategy/IStrategy.sol";
import { Math } from "openzeppelin-contracts/utils/math/Math.sol";
import { LMPDestinations } from "src/vault/libs/LMPDestinations.sol";
import { ERC20 } from "openzeppelin-contracts/token/ERC20/ERC20.sol";
import { IERC4626 } from "openzeppelin-contracts/interfaces/IERC4626.sol";
import { IMainRewarder } from "src/interfaces/rewarders/IMainRewarder.sol";
import { IDestinationVault } from "src/interfaces/vault/IDestinationVault.sol";
import { SafeERC20 } from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";
import { Initializable } from "openzeppelin-contracts/proxy/utils/Initializable.sol";
import { EnumerableSet } from "openzeppelin-contracts/utils/structs/EnumerableSet.sol";
import { ISystemRegistry, IDestinationVaultRegistry } from "src/interfaces/ISystemRegistry.sol";
import { ERC20Permit } from "openzeppelin-contracts/token/ERC20/extensions/draft-ERC20Permit.sol";
import { IERC3156FlashBorrower } from "openzeppelin-contracts/interfaces/IERC3156FlashBorrower.sol";
import { IERC20Metadata as IERC20 } from "openzeppelin-contracts/token/ERC20/extensions/IERC20Metadata.sol";

// Cross functional reentrancy was identified between updateDebtReporting and the
// destinationInfo. Have nonReentrant and read-only nonReentrant modifier on them both
// but slither was still complaining
//slither-disable-start reentrancy-no-eth,reentrancy-benign

contract LMPVault is
    SystemComponent,
    Initializable,
    ILMPVault,
    IStrategy,
    ERC20Permit,
    SecurityBase,
    Pausable,
    NonReentrant
{
    using EnumerableSet for EnumerableSet.AddressSet;
    using Math for uint256;
    using SafeERC20 for ERC20;
    using SafeERC20 for IERC20;

    /// @dev In memory struct only for managing vars in _withdraw
    struct WithdrawInfo {
        uint256 currentIdle;
        uint256 assetsFromIdle;
        uint256 totalAssetsToPull;
        uint256 totalAssetsPulled;
        uint256 idleIncrease;
        uint256 debtDecrease;
    }

    /// @notice Max fee. 100% == 10000
    uint256 public constant MAX_FEE_BPS = 10_000;

    uint256 public constant NAV_CHANGE_ROUNDING_BUFFER = 100;

    /// @notice Factory contract that created this vault
    address public factory;

    /// @notice Overarching baseAsset type
    bytes32 public immutable vaultType = VaultTypes.LST;

    /// @dev The asset that is deposited into the vault
    IERC20 internal immutable _baseAsset;

    /// @notice Decimals of the base asset. Used as the decimals for the vault itself
    uint8 internal immutable _baseAssetDecimals;

    /// @dev Full list of possible destinations that could be deployed to
    EnumerableSet.AddressSet internal destinations;

    /// @dev Destinations that queued for removal
    EnumerableSet.AddressSet internal removalQueue;

    /// @dev destinationVaultAddress -> Info .. Debt reporting snapshot info
    mapping(address => LMPDebt.DestinationInfo) internal destinationInfo;

    /// @dev whether or not the vault has been shutdown
    bool internal _shutdown;

    /// @notice The amount of baseAsset deposited into the contract pending deployment
    uint256 public totalIdle = 0;

    /// @notice The current (though cached) value of assets we've deployed
    uint256 public totalDebt = 0;

    /// @notice The destinations, in order, in which withdrawals will be attempted from
    IDestinationVault[] public withdrawalQueue;

    /// @notice Main rewarder for this contract
    IMainRewarder public rewarder;

    /// @notice Current performance fee taken on profit. 100% == 10000
    uint256 public performanceFeeBps;

    /// @notice Where claimed fees are sent
    address public feeSink;

    /// @notice The last nav/share height we took fees at
    uint256 public navPerShareHighMark = MAX_FEE_BPS;

    /// @notice The last timestamp we took fees at
    uint256 public navPerShareHighMarkTimestamp;

    /// @notice The max total supply of shares we'll allow to be minted
    uint256 public totalSupplyLimit;

    /// @notice The max shares a single wallet is allowed to hold
    uint256 public perWalletLimit;

    string private _desc;
    string private _symbol;

    error TooFewAssets(uint256 requested, uint256 actual);
    error WithdrawShareCalcInvalid(uint256 currentShares, uint256 cachedShares);
    error InvalidFee(uint256 newFee);
    error RewarderAlreadySet();
    error RebalanceDestinationsMatch(address destinationVault);
    error InvalidDestination(address destination);
    error NavChanged(uint256 oldNav, uint256 newNav);
    error NavOpsInProgress();
    error OverWalletLimit(address to);
    error VaultShutdown();

    event PerformanceFeeSet(uint256 newFee);
    event FeeSinkSet(address newFeeSink);
    event NewNavHighWatermark(uint256 navPerShare, uint256 timestamp);
    event TotalSupplyLimitSet(uint256 limit);
    event PerWalletLimitSet(uint256 limit);

    modifier noNavChange() {
        (uint256 oldNav, uint256 startingTotalSupply) = _snapStartNav();
        _;
        _ensureNoNavChange(oldNav, startingTotalSupply);
    }

    modifier noNavDecrease() {
        (uint256 oldNav, uint256 startingTotalSupply) = _snapStartNav();
        _;
        _ensureNoNavDecrease(oldNav, startingTotalSupply);
    }

    modifier ensureNoNavOps() {
        if (systemRegistry.systemSecurity().navOpsInProgress() > 0) {
            revert NavOpsInProgress();
        }
        _;
    }

    modifier trackNavOps() {
        systemRegistry.systemSecurity().enterNavOperation();
        _;
        systemRegistry.systemSecurity().exitNavOperation();
    }

    constructor(
        ISystemRegistry _systemRegistry,
        address _vaultAsset
    )
        SystemComponent(_systemRegistry)
        ERC20(
            string(abi.encodePacked(ERC20(_vaultAsset).name(), " Pool Token")),
            string(abi.encodePacked("lmp", ERC20(_vaultAsset).symbol()))
        )
        ERC20Permit(string(abi.encodePacked("lmp", ERC20(_vaultAsset).symbol())))
        SecurityBase(address(_systemRegistry.accessController()))
        Pausable(_systemRegistry)
    {
        _baseAsset = IERC20(_vaultAsset);
        _baseAssetDecimals = IERC20(_vaultAsset).decimals();

        _symbol = ERC20(_vaultAsset).symbol();
        _desc = ERC20(_vaultAsset).name();

        _disableInitializers();
    }

    function initialize(
        uint256 supplyLimit,
        uint256 walletLimit,
        string memory symbolSuffix,
        string memory descPrefix,
        bytes memory
    ) public virtual initializer {
        Errors.verifyNotEmpty(symbolSuffix, "symbolSuffix");
        Errors.verifyNotEmpty(descPrefix, "descPrefix");

        // init withdrawal queue to empty (slither issue)
        withdrawalQueue = new IDestinationVault[](0);

        navPerShareHighMarkTimestamp = block.timestamp;

        _setTotalSupplyLimit(supplyLimit);
        _setPerWalletLimit(walletLimit);

        factory = msg.sender;

        _symbol = symbolSuffix;
        _desc = descPrefix;
    }

    /**
     * @dev Returns the name of the token.
     */
    function name() public view virtual override(ERC20, IERC20) returns (string memory) {
        return string(abi.encodePacked(_desc, " Pool Token"));
    }

    /**
     * @dev Returns the symbol of the token, usually a shorter version of the
     * name.
     */
    function symbol() public view virtual override(ERC20, IERC20) returns (string memory) {
        return string(abi.encodePacked("lmp", _symbol));
    }

    /// @inheritdoc IERC20
    function decimals() public view virtual override(ERC20, IERC20) returns (uint8) {
        return _baseAssetDecimals;
    }

    /// @notice Set the global share limit
    /// @dev Zero is allowed here and used as a way to stop deposits but allow withdrawals
    /// @param newSupplyLimit new total amount of shares allowed to be minted
    function setTotalSupplyLimit(uint256 newSupplyLimit) external onlyOwner {
        _setTotalSupplyLimit(newSupplyLimit);
    }

    /// @notice Set the per-wallet share limit
    /// @param newWalletLimit new total shares a wallet is allowed to hold
    function setPerWalletLimit(uint256 newWalletLimit) external onlyOwner {
        _setPerWalletLimit(newWalletLimit);
    }

    /// @notice Set the fee that will be taken when profit is realized
    /// @dev Resets the high water to current value
    /// @param fee Percent. 100% == 10000
    function setPerformanceFeeBps(uint256 fee) external nonReentrant hasRole(Roles.LMP_FEE_SETTER_ROLE) {
        if (fee >= MAX_FEE_BPS) {
            revert InvalidFee(fee);
        }

        performanceFeeBps = fee;

        // Set the high mark when we change the fee so we aren't able to go farther back in
        // time than one debt reporting and claim fee's against past profits
        uint256 supply = totalSupply();
        if (supply > 0) {
            navPerShareHighMark = (totalAssets() * MAX_FEE_BPS) / supply;
        } else {
            // The default high mark is 1:1. We don't want to be able to take
            // fee's before the first debt reporting
            // Before a rebalance, everything will be in idle and we don't want to take
            // fee's on pure idle
            navPerShareHighMark = MAX_FEE_BPS;
        }

        emit PerformanceFeeSet(fee);
    }

    /// @notice Set the address that will receive fees
    /// @param newFeeSink Address that will receive fees
    function setFeeSink(address newFeeSink) external onlyOwner {
        emit FeeSinkSet(newFeeSink);

        // Zero is valid. One way to disable taking fees
        // slither-disable-next-line missing-zero-check
        feeSink = newFeeSink;
    }

    /// @notice Set the rewarder contract used by the vault
    /// @dev Must be set immediately on initialization/creation and only once
    function setRewarder(address _rewarder) external {
        if (msg.sender != factory) {
            revert Errors.AccessDenied();
        }

        Errors.verifyNotZero(_rewarder, "rewarder");

        if (address(rewarder) != address(0)) {
            revert RewarderAlreadySet();
        }

        rewarder = IMainRewarder(_rewarder);

        emit RewarderSet(_rewarder);
    }

    /// @dev See {IERC4626-asset}.
    function asset() public view virtual override returns (address) {
        return address(_baseAsset);
    }

    function totalAssets() public view override returns (uint256) {
        return totalIdle + totalDebt;
    }

    /// @dev See {IERC4626-convertToShares}.
    function convertToShares(uint256 assets) public view virtual returns (uint256 shares) {
        shares = _convertToShares(assets, Math.Rounding.Down);
    }

    /// @dev See {IERC4626-convertToAssets}.
    function convertToAssets(uint256 shares) public view virtual returns (uint256 assets) {
        assets = _convertToAssets(shares, Math.Rounding.Down);
    }

    //////////////////////////////////////////////////////////////////////
    //								Deposit								//
    //////////////////////////////////////////////////////////////////////

    /// @dev See {IERC4626-maxDeposit}.
    function maxDeposit(address wallet) public view virtual override returns (uint256 maxAssets) {
        maxAssets = convertToAssets(_maxMint(wallet));
    }

    /// @dev See {IERC4626-previewDeposit}.
    function previewDeposit(uint256 assets) public view virtual returns (uint256 shares) {
        shares = _convertToShares(assets, Math.Rounding.Down);
    }

    function deposit(
        uint256 assets,
        address receiver
    ) public virtual override nonReentrant noNavChange ensureNoNavOps returns (uint256 shares) {
        Errors.verifyNotZero(assets, "assets");
        if (assets > maxDeposit(receiver)) {
            revert ERC4626DepositExceedsMax(assets, maxDeposit(receiver));
        }

        shares = previewDeposit(assets);

        _transferAndMint(assets, shares, receiver);
    }

    /// @dev See {IERC4626-maxMint}.
    function maxMint(address wallet) public view virtual override returns (uint256 maxShares) {
        maxShares = _maxMint(wallet);
    }

    /// @dev See {IERC4626-maxWithdraw}.
    function maxWithdraw(address owner) public view virtual returns (uint256 maxAssets) {
        maxAssets = paused() ? 0 : previewRedeem(balanceOf(owner));
    }

    /// @dev See {IERC4626-maxRedeem}.
    function maxRedeem(address owner) public view virtual returns (uint256 maxShares) {
        maxShares = _maxRedeem(owner);
    }

    /// @dev See {IERC4626-previewMint}.
    function previewMint(uint256 shares) public view virtual returns (uint256 assets) {
        assets = _convertToAssets(shares, Math.Rounding.Up);
    }

    /// @dev See {IERC4626-previewWithdraw}.
    function previewWithdraw(uint256 assets) public view virtual returns (uint256 shares) {
        shares = _convertToShares(assets, Math.Rounding.Up);
    }

    /// @dev See {IERC4626-previewRedeem}.
    function previewRedeem(uint256 shares) public view virtual override returns (uint256) {
        return _convertToAssets(shares, Math.Rounding.Down);
    }

    /**
     * @dev See {IERC4626-mint}.
     *
     * As opposed to {deposit}, minting is allowed even if the vault is in a state where the price of a share is zero.
     * In this case, the shares will be minted without requiring any assets to be deposited.
     */
    function mint(
        uint256 shares,
        address receiver
    ) public virtual override nonReentrant noNavChange ensureNoNavOps returns (uint256 assets) {
        if (shares > maxMint(receiver)) {
            revert ERC4626MintExceedsMax(shares, maxMint(receiver));
        }

        assets = previewMint(shares);

        _transferAndMint(assets, shares, receiver);
    }

    //////////////////////////////////////////////////////////////////////
    //								Withdraw							//
    //////////////////////////////////////////////////////////////////////

    /// @dev See {IERC4626-withdraw}.
    function withdraw(
        uint256 assets,
        address receiver,
        address owner
    ) public virtual override nonReentrant noNavDecrease ensureNoNavOps returns (uint256 shares) {
        Errors.verifyNotZero(assets, "assets");
        uint256 maxAssets = maxWithdraw(owner);
        if (assets > maxAssets) {
            revert ERC4626ExceededMaxWithdraw(owner, assets, maxAssets);
        }

        // query number of shares these assets match
        shares = previewWithdraw(assets);

        uint256 actualAssets = _withdraw(assets, shares, receiver, owner);

        if (actualAssets < assets) {
            revert TooFewAssets(assets, actualAssets);
        }
    }

    /// @dev See {IERC4626-redeem}.
    function redeem(
        uint256 shares,
        address receiver,
        address owner
    ) public virtual override nonReentrant noNavDecrease ensureNoNavOps returns (uint256 assets) {
        uint256 maxShares = maxRedeem(owner);
        if (shares > maxShares) {
            revert ERC4626ExceededMaxRedeem(owner, shares, maxShares);
        }
        uint256 possibleAssets = previewRedeem(shares);

        assets = _withdraw(possibleAssets, shares, receiver, owner);
    }

    function _calcUserWithdrawSharesToBurn(
        IDestinationVault destVault,
        uint256 userShares,
        uint256 maxAssetsToPull,
        uint256 totalVaultShares
    ) internal returns (uint256 sharesToBurn, uint256 totalDebtBurn) {
        (sharesToBurn, totalDebtBurn) = LMPDebt._calcUserWithdrawSharesToBurn(
            destinationInfo[address(destVault)], destVault, userShares, maxAssetsToPull, totalVaultShares
        );
    }

    // slither-disable-next-line cyclomatic-complexity
    function _withdraw(
        uint256 assets,
        uint256 shares,
        address receiver,
        address owner
    ) internal virtual returns (uint256) {
        uint256 idle = totalIdle;
        WithdrawInfo memory info = WithdrawInfo({
            currentIdle: idle,
            assetsFromIdle: assets >= idle ? idle : assets,
            totalAssetsToPull: assets - (assets >= idle ? idle : assets),
            totalAssetsPulled: 0,
            idleIncrease: 0,
            debtDecrease: 0
        });

        // If not enough funds in idle, then pull what we need from destinations
        if (info.totalAssetsToPull > 0) {
            uint256 totalVaultShares = totalSupply();

            // Using pre-set withdrawalQueue for withdrawal order to help minimize user gas
            uint256 withdrawalQueueLength = withdrawalQueue.length;
            for (uint256 i = 0; i < withdrawalQueueLength; ++i) {
                IDestinationVault destVault = IDestinationVault(withdrawalQueue[i]);
                (uint256 sharesToBurn, uint256 totalDebtBurn) = _calcUserWithdrawSharesToBurn(
                    destVault,
                    shares,
                    info.totalAssetsToPull - Math.max(info.debtDecrease, info.totalAssetsPulled),
                    totalVaultShares
                );
                if (sharesToBurn == 0) {
                    continue;
                }

                uint256 assetPreBal = _baseAsset.balanceOf(address(this));
                uint256 assetPulled = destVault.withdrawBaseAsset(sharesToBurn, address(this));

                // Destination Vault rewards will be transferred to us as part of burning out shares
                // Back into what that amount is and make sure it gets into idle
                info.idleIncrease += _baseAsset.balanceOf(address(this)) - assetPreBal - assetPulled;
                info.totalAssetsPulled += assetPulled;
                info.debtDecrease += totalDebtBurn;

                // It's possible we'll get back more assets than we anticipate from a swap
                // so if we do, throw it in idle and stop processing. You don't get more than we've calculated
                if (info.totalAssetsPulled > info.totalAssetsToPull) {
                    info.idleIncrease = info.totalAssetsPulled - info.totalAssetsToPull;
                    info.totalAssetsPulled = info.totalAssetsToPull;
                    break;
                }

                // No need to keep going if we have the amount we're looking for
                // Any overage is accounted for above. Anything lower and we need to keep going
                // slither-disable-next-line incorrect-equality
                if (info.totalAssetsPulled == info.totalAssetsToPull) {
                    break;
                }
            }
        }

        // At this point should have all the funds we need sitting in in the vault
        uint256 returnedAssets = info.assetsFromIdle + info.totalAssetsPulled;

        // subtract what's taken out of idle from totalIdle
        // slither-disable-next-line events-maths
        totalIdle = info.currentIdle + info.idleIncrease - info.assetsFromIdle;

        if (info.debtDecrease > totalDebt) {
            totalDebt = 0;
        } else {
            totalDebt -= info.debtDecrease;
        }

        // do the actual withdrawal (going off of total # requested)
        uint256 allowed = allowance(owner, msg.sender);
        if (msg.sender != owner && allowed != type(uint256).max) {
            if (shares > allowed) revert AmountExceedsAllowance(shares, allowed);

            unchecked {
                _approve(owner, msg.sender, allowed - shares);
            }
        }

        _burn(owner, shares);

        emit Withdraw(msg.sender, receiver, owner, returnedAssets, shares);

        emit Nav(totalIdle, totalDebt, totalSupply());

        _baseAsset.safeTransfer(receiver, returnedAssets);

        return returnedAssets;
    }

    function claimRewards() public whenNotPaused {
        rewarder.getReward(msg.sender, true);
    }

    /// @notice Transfer out non-tracked tokens
    function recover(
        address[] calldata tokens,
        uint256[] calldata amounts,
        address[] calldata _destinations
    ) external virtual override hasRole(Roles.TOKEN_RECOVERY_ROLE) {
        // Makes sure our params are valid
        uint256 len = tokens.length;
        if (len == 0) {
            revert Errors.InvalidParams();
        }
        Errors.verifyArrayLengths(len, amounts.length, "tokens+amounts");
        Errors.verifyArrayLengths(len, _destinations.length, "tokens+_destinations");

        emit TokensRecovered(tokens, amounts, _destinations);

        for (uint256 i = 0; i < len; ++i) {
            (address tokenAddress, uint256 amount, address destination) = (tokens[i], amounts[i], _destinations[i]);

            // Ensure this isn't an asset we care about
            if (_isTrackedAsset(tokenAddress)) {
                revert Errors.AssetNotAllowed(tokenAddress);
            }

            IERC20(tokenAddress).safeTransfer(destination, amount);
        }
    }

    /// @inheritdoc ILMPVault
    function shutdown() external onlyOwner {
        _shutdown = true;

        emit Shutdown();
    }

    /// @inheritdoc ILMPVault
    function isShutdown() external view returns (bool) {
        return _shutdown;
    }

    /**
     * @dev Internal conversion function (from assets to shares) with support for rounding direction.
     */
    function _convertToShares(uint256 assets, Math.Rounding rounding) internal view virtual returns (uint256 shares) {
        uint256 supply = totalSupply();

        // slither-disable-next-line incorrect-equality
        shares = (assets == 0 || supply == 0) ? assets : assets.mulDiv(supply, totalAssets(), rounding);
    }

    /// @dev Internal conversion function (from shares to assets) with support for rounding direction.
    function _convertToAssets(uint256 shares, Math.Rounding rounding) internal view virtual returns (uint256 assets) {
        uint256 supply = totalSupply();
        assets = (supply == 0) ? shares : shares.mulDiv(totalAssets(), supply, rounding);
    }

    function _maxRedeem(address owner) internal view virtual returns (uint256 maxShares) {
        maxShares = paused() ? 0 : balanceOf(owner);
    }

    function _transferAndMint(uint256 assets, uint256 shares, address receiver) internal virtual {
        // From OZ documentation:
        // ----------------------
        // If _asset is ERC777, `transferFrom` can trigger a reentrancy BEFORE the transfer happens through the
        // `tokensToSend` hook. On the other hand, the `tokenReceived` hook, that is triggered after the transfer,
        // calls the vault, which is assumed not malicious.
        //
        // Conclusion: we need to do the transfer before we mint so that any reentrancy would happen before the
        // assets are transferred and before the shares are minted, which is a valid state.
        // slither-disable-next-line reentrancy-no-eth
        _baseAsset.safeTransferFrom(msg.sender, address(this), assets);

        totalIdle += assets;

        _mint(receiver, shares);

        emit Deposit(msg.sender, receiver, assets, shares);

        emit Nav(totalIdle, totalDebt, totalSupply());
    }

    ///@dev Checks if vault is "healthy" in the sense of having assets backing the circulating shares.
    function _isVaultCollateralized() internal view returns (bool) {
        return totalAssets() > 0 || totalSupply() == 0;
    }

    function updateDebtReporting(address[] calldata _destinations) external nonReentrant trackNavOps {
        _updateDebtReporting(_destinations);
    }

    //////////////////////////////////////////////////////////////////////////
    //							  Destinations     							//
    //////////////////////////////////////////////////////////////////////////

    function getDestinations() public view override(ILMPVault, IStrategy) returns (address[] memory) {
        return destinations.values();
    }

    function isDestinationRegistered(address destination) external view returns (bool) {
        return destinations.contains(destination);
    }

    function addDestinations(address[] calldata _destinations) public hasRole(Roles.DESTINATION_VAULTS_UPDATER) {
        LMPDestinations.addDestinations(removalQueue, destinations, _destinations, systemRegistry);
    }

    function removeDestinations(address[] calldata _destinations) public hasRole(Roles.DESTINATION_VAULTS_UPDATER) {
        LMPDestinations.removeDestinations(removalQueue, destinations, _destinations);
    }

    function getRemovalQueue() public view override returns (address[] memory) {
        return removalQueue.values();
    }

    function removeFromRemovalQueue(address vaultToRemove) public override hasRole(Roles.REBALANCER_ROLE) {
        LMPDestinations.removeFromRemovalQueue(removalQueue, vaultToRemove);
    }

    /// @dev Order is set as list of interfaces to minimize gas for our users
    function setWithdrawalQueue(address[] calldata _destinations)
        public
        override
        hasRole(Roles.SET_WITHDRAWAL_QUEUE_ROLE)
    {
        LMPDestinations.setWithdrawalQueue(withdrawalQueue, _destinations, systemRegistry);
    }

    /// @notice Get the current withdrawal queue
    function getWithdrawalQueue() public view override returns (IDestinationVault[] memory withdrawalDestinations) {
        return withdrawalQueue;
    }

    /// @notice Get the current snapshot debt info for a destination
    function getDestinationInfo(address destVault)
        external
        view
        nonReentrantReadOnly
        returns (LMPDebt.DestinationInfo memory)
    {
        return destinationInfo[destVault];
    }

    //////////////////////////////////////////////////////////////////////////
    //                                                                      //
    //							Strategy Related   							//
    //                                                                      //
    //////////////////////////////////////////////////////////////////////////

    /// @inheritdoc IStrategy
    function rebalance(RebalanceParams memory params) public nonReentrant hasRole(Roles.SOLVER_ROLE) trackNavOps {
        (uint256 idle, uint256 debt) = LMPDebt.rebalance(
            destinationInfo[params.destinationOut],
            destinationInfo[params.destinationIn],
            params,
            _baseAsset,
            _shutdown,
            totalIdle,
            totalDebt
        );
        totalIdle = idle;
        totalDebt = debt;
        _collectFees(idle, debt, totalSupply());

        emit Nav(totalIdle, totalDebt, totalSupply());
    }

    /// @inheritdoc IStrategy
    function flashRebalance(
        IERC3156FlashBorrower receiver,
        RebalanceParams memory rebalanceParams,
        bytes calldata data
    ) public nonReentrant hasRole(Roles.SOLVER_ROLE) trackNavOps {
        (uint256 idle, uint256 debt) = LMPDebt.flashRebalance(
            destinationInfo[rebalanceParams.destinationOut],
            destinationInfo[rebalanceParams.destinationIn],
            receiver,
            rebalanceParams,
            LMPDebt.FlashRebalanceParams({
                totalIdle: totalIdle,
                totalDebt: totalDebt,
                baseAsset: _baseAsset,
                shutdown: _shutdown
            }),
            data
        );
        totalIdle = idle;
        totalDebt = debt;
        _collectFees(idle, debt, totalSupply());

        emit Nav(totalIdle, totalDebt, totalSupply());
    }

    /// @inheritdoc IStrategy
    function verifyRebalance(
        address destinationIn,
        address tokenIn,
        uint256 amountIn,
        address destinationOut,
        address tokenOut,
        uint256 amountOut
    ) public view virtual returns (bool success, string memory message) {
        (success, message) = LMPStrategy.verifyRebalance(
            IStrategy.RebalanceParams({
                destinationIn: destinationIn,
                tokenIn: tokenIn,
                amountIn: amountIn,
                destinationOut: destinationOut,
                tokenOut: tokenOut,
                amountOut: amountOut
            })
        );
    }

    /// @notice Process the destinations calculating current value and snapshotting for safe deposit/mint'ing
    function _updateDebtReporting(address[] memory _destinations) private {
        uint256 nDest = _destinations.length;

        uint256 idleIncrease = 0;
        uint256 prevNTotalDebt = 0;
        uint256 afterNTotalDebt = 0;

        for (uint256 i = 0; i < nDest; ++i) {
            IDestinationVault destVault = IDestinationVault(_destinations[i]);

            if (!destinations.contains(address(destVault))) {
                revert InvalidDestination(address(destVault));
            }

            // Get the reward value we've earned. DV rewards are always in terms of base asset
            // We track the gas used purely for off-chain stats purposes
            // Main rewarder on DV's store the earned and liquidated rewards
            // Extra rewarders are disabled at the DV level
            uint256 claimGasUsed = gasleft();
            uint256 beforeBaseAsset = _baseAsset.balanceOf(address(this));
            // We don't want any extras, those would likely not be baseAsset
            IMainRewarder(destVault.rewarder()).getReward(address(this), false);
            uint256 claimedRewardValue = _baseAsset.balanceOf(address(this)) - beforeBaseAsset;
            claimGasUsed -= gasleft();
            idleIncrease += claimedRewardValue;

            // Recalculate the debt info figuring out the change in
            // total debt value we can roll up later
            uint256 currentShareBalance = destVault.balanceOf(address(this));
            (uint256 totalDebtDecrease, uint256 totalDebtIncrease) = LMPDebt.recalculateDestInfo(
                destinationInfo[address(destVault)], destVault, currentShareBalance, currentShareBalance, false
            );
            prevNTotalDebt += totalDebtDecrease;
            afterNTotalDebt += totalDebtIncrease;

            emit DestinationDebtReporting(address(destVault), totalDebtIncrease, claimedRewardValue, claimGasUsed);
        }

        // Persist our change in idle and debt
        uint256 idle = totalIdle + idleIncrease;
        uint256 debt = totalDebt - prevNTotalDebt + afterNTotalDebt;

        totalIdle = idle;
        totalDebt = debt;

        _collectFees(idle, debt, totalSupply());

        emit Nav(totalIdle, totalDebt, totalSupply());
    }

    function _collectFees(uint256 idle, uint256 debt, uint256 totalSupply) internal {
        address sink = feeSink;
        uint256 fees = 0;
        uint256 shares = 0;
        uint256 profit = 0;

        // If there's no supply then there should be no assets and so nothing
        // to actually take fees on
        if (totalSupply == 0) {
            return;
        }

        uint256 currentNavPerShare = ((idle + debt) * MAX_FEE_BPS) / totalSupply;
        uint256 effectiveNavPerShareHighMark = navPerShareHighMark;

        if (currentNavPerShare > effectiveNavPerShareHighMark) {
            // Even if we aren't going to take the fee (haven't set a sink)
            // We still want to calculate so we can emit for off-chain analysis
            profit = (currentNavPerShare - effectiveNavPerShareHighMark) * totalSupply;
            fees = profit.mulDiv(performanceFeeBps, (MAX_FEE_BPS ** 2), Math.Rounding.Up);
            if (fees > 0 && sink != address(0)) {
                // Calculated separate from other mints as normal share mint is round down
                shares = _convertToShares(fees, Math.Rounding.Up);
                _mint(sink, shares);
                emit Deposit(address(this), sink, fees, shares);
            }
            // Set our new high water mark, the last nav/share height we took fees
            navPerShareHighMark = currentNavPerShare;
            navPerShareHighMarkTimestamp = block.timestamp;
            emit NewNavHighWatermark(currentNavPerShare, block.timestamp);
        }
        emit FeeCollected(fees, sink, shares, profit, idle, debt);

        // NOTE: NavChanged event thrown in higher level caller
    }

    function _beforeTokenTransfer(address from, address to, uint256 amount) internal virtual override whenNotPaused {
        // Nothing to do really do here
        if (from == to) {
            return;
        }

        // If this isn't a mint of new tokens, then they are being transferred
        // from someone who is "staked" in the rewarder. Make sure they stop earning
        // When they transfer those funds
        if (from != address(0)) {
            rewarder.withdraw(from, amount, true);
        }

        // Make sure the destination wallet total share balance doesn't go above the
        // current perWalletLimit, except for the feeSink
        if (to != feeSink && to != address(0) && balanceOf(to) + amount > perWalletLimit) {
            revert OverWalletLimit(to);
        }

        // If this isn't a burn, then the recipient should be earning in the rewarder
        // "Stake" the tokens there so they start earning
        if (to != address(0)) {
            rewarder.stake(to, amount);
        }
    }

    function _afterTokenTransfer(address from, address to, uint256) internal virtual override {
        // Nothing to do really do here
        if (from == to) {
            return;
        }
    }

    function _snapStartNav() private view returns (uint256 oldNav, uint256 startingTotalSupply) {
        startingTotalSupply = totalSupply();
        if (startingTotalSupply == 0) {
            return (0, 0);
        }
        oldNav = (totalAssets() * MAX_FEE_BPS) / startingTotalSupply;
    }

    /// @notice Vault nav/share should not change on deposit/mint within rounding tolerance
    /// @dev Disregarded for initial deposit
    function _ensureNoNavChange(uint256 oldNav, uint256 startingTotalSupply) private view {
        // Can change on initial deposit
        if (startingTotalSupply == 0) {
            return;
        }

        uint256 ts = totalSupply();

        // Calculate the valid range
        uint256 lowerBound = Math.max(oldNav, NAV_CHANGE_ROUNDING_BUFFER) - NAV_CHANGE_ROUNDING_BUFFER;
        uint256 upperBound = oldNav > type(uint256).max - NAV_CHANGE_ROUNDING_BUFFER
            ? type(uint256).max
            : oldNav + NAV_CHANGE_ROUNDING_BUFFER;

        // Make sure new nav is in range
        uint256 newNav = (totalAssets() * MAX_FEE_BPS) / ts;
        if (newNav < lowerBound || newNav > upperBound) {
            revert NavChanged(oldNav, newNav);
        }
    }

    /// @notice Vault nav/share shouldn't decrease on withdraw/redeem within rounding tolerance
    /// @dev No check when no shares
    function _ensureNoNavDecrease(uint256 oldNav, uint256 startingTotalSupply) private view {
        uint256 ts = totalSupply();
        if (ts == 0 || startingTotalSupply == 0) {
            return;
        }
        uint256 lowerBound = Math.max(oldNav, NAV_CHANGE_ROUNDING_BUFFER) - NAV_CHANGE_ROUNDING_BUFFER;
        uint256 newNav = (totalAssets() * MAX_FEE_BPS) / ts;
        if (newNav < lowerBound) {
            revert NavChanged(oldNav, newNav);
        }
    }

    /// @notice Returns true if the provided asset one that is allowed to be transferred out via recover()
    function _isTrackedAsset(address _asset) private view returns (bool) {
        // Any asset that is core to functionality of this vault should not be removed
        if (_asset == address(this) || _asset == address(_baseAsset)) {
            return true;
        }
        return destinations.contains(_asset);
    }

    function _maxMint(address wallet) internal view virtual returns (uint256 shares) {
        // If we are temporarily paused, or in full shutdown mode,
        // no new shares are able to be minted
        if (paused() || _shutdown) {
            return 0;
        }

        uint256 tsLimit = totalSupplyLimit;
        uint256 walletLimit = perWalletLimit;

        if (!_isVaultCollateralized()) {
            return Math.min(tsLimit, walletLimit);
        }

        // Return max if there is no limit as per spec
        if (tsLimit == type(uint256).max && walletLimit == type(uint256).max) {
            return type(uint256).max;
        }

        // Ensure we aren't over the total supply limit
        uint256 totalSupply = totalSupply();
        if (totalSupply >= tsLimit) {
            return 0;
        }

        // Ensure the wallet isn't over the per wallet limit
        uint256 walletBalance = balanceOf(wallet);

        if (walletBalance >= perWalletLimit) {
            return 0;
        }

        // User gets the minimum of of the limit buffers
        shares = Math.min(tsLimit - totalSupply, walletLimit - walletBalance);
    }

    /// @notice Set the global share limit
    /// @dev Zero is allowed here and used as a way to stop deposits but allow withdrawals
    /// @param newSupplyLimit new total amount of shares allowed to be minted
    function _setTotalSupplyLimit(uint256 newSupplyLimit) private {
        // We do not expect that a decrease in this value will affect any shares already minted
        // Just that new shares won't be minted until existing fall below the limit

        totalSupplyLimit = newSupplyLimit;

        emit TotalSupplyLimitSet(newSupplyLimit);
    }

    /// @notice Set the per-wallet share limit
    /// @param newWalletLimit new total shares a wallet is allowed to hold
    function _setPerWalletLimit(uint256 newWalletLimit) private {
        // Any decrease in this value shouldn't affect what a wallet is already holding
        // Just that their amount can't increase
        Errors.verifyNotZero(newWalletLimit, "newWalletLimit");

        perWalletLimit = newWalletLimit;

        emit PerWalletLimitSet(newWalletLimit);
    }
}

//slither-disable-end reentrancy-no-eth,reentrancy-benign
