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
import { ILMPVault, IMainRewarder } from "src/interfaces/vault/ILMPVault.sol";
import { IStrategy } from "src/interfaces/strategy/IStrategy.sol";
import { Math } from "openzeppelin-contracts/utils/math/Math.sol";
import { LMPDestinations } from "src/vault/libs/LMPDestinations.sol";
import { ERC20 } from "openzeppelin-contracts/token/ERC20/ERC20.sol";
import { IERC4626 } from "openzeppelin-contracts/interfaces/IERC4626.sol";
import { IDestinationVault } from "src/interfaces/vault/IDestinationVault.sol";
import { SafeERC20 } from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";
import { Initializable } from "openzeppelin-contracts/proxy/utils/Initializable.sol";
import { EnumerableSet } from "openzeppelin-contracts/utils/structs/EnumerableSet.sol";
import { ISystemRegistry, IDestinationVaultRegistry } from "src/interfaces/ISystemRegistry.sol";
import { ERC20Permit } from "openzeppelin-contracts/token/ERC20/extensions/draft-ERC20Permit.sol";
import { IERC3156FlashBorrower } from "openzeppelin-contracts/interfaces/IERC3156FlashBorrower.sol";
import { IERC20Metadata as IERC20 } from "openzeppelin-contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { ILMPStrategy } from "src/interfaces/strategy/ILMPStrategy.sol";

// Cross functional reentrancy was identified between updateDebtReporting and the
// destinationInfo. Have nonReentrant and read-only nonReentrant modifier on them both
// but slither was still complaining. Also disabling reliance on block timestamp as we're basing on it
//slither-disable-start reentrancy-no-eth,reentrancy-benign,timestamp,similar-names

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

    /// @notice Max management fee, 10%.  100% = 10_000.
    uint256 public constant MAX_MANAGEMENT_FEE_BPS = 1000;

    /// @notice Time between management fee takes.  ~ half year.
    uint256 public constant MANAGEMENT_FEE_TAKE_TIMEFRAME = 182 days;

    /// @notice Time before a management fee is taken that the fee % can be changed.
    uint256 public constant MANAGEMENT_FEE_CHANGE_CUTOFF = 45 days;

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

    /// @dev The reason for shutdown (or `Active` if not shutdown)
    VaultShutdownStatus internal _shutdownStatus;

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

    /// @notice The last totalAssets amount we took fees at
    uint256 public totalAssetsHighMark;

    /// @notice The last timestamp we updated the high water mark
    uint256 public totalAssetsHighMarkTimestamp;

    /// @notice The max total supply of shares we'll allow to be minted
    uint256 public totalSupplyLimit;

    /// @notice The max shares a single wallet is allowed to hold
    uint256 public perWalletLimit;

    // TODO: update init/constructor to support this
    /// @notice The strategy logic for the LMP
    // slither-disable-next-line uninitialized-state,constable-states
    ILMPStrategy public lmpStrategy;

    string private _desc;
    string private _symbol;

    /// @notice Address that receives management fee.
    address public managementFeeSink;

    /// @notice Timestamp of next management fee to be taken.
    uint48 public nextManagementFeeTake;

    /// @notice Current management fee.  100% == 10_000.
    uint16 public managementFeeBps;

    /// @notice Pending management fee.  Used as placeholder for new `managementFeeBps` within range of fee take.
    uint16 public pendingManagementFeeBps;

    /// @notice Rewarders that have been replaced.
    EnumerableSet.AddressSet internal pastRewarders;

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
    error TotalSupplyOverLimit();
    error PerWalletOverLimit();

    event PerformanceFeeSet(uint256 newFee);
    event FeeSinkSet(address newFeeSink);
    event NewNavHighWatermark(uint256 navPerShare, uint256 timestamp);
    event NewTotalAssetsHighWatermark(uint256 assets, uint256 timestamp);
    event TotalSupplyLimitSet(uint256 limit);
    event PerWalletLimitSet(uint256 limit);
    event SymbolAndDescSet(string symbol, string desc);
    event ManagementFeeSet(uint256 newFee);
    event PendingManagementFeeSet(uint256 pendingManagementFeeBps);
    event ManagementFeeSinkSet(address newManagementFeeSink);
    event NextManagementFeeTakeSet(uint256 nextManagementFeeTake);

    struct ExtraData {
        address lmpStrategyAddress;
    }

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

        _symbol = string(abi.encodePacked("lmp", ERC20(_vaultAsset).symbol()));
        _desc = string(abi.encodePacked(ERC20(_vaultAsset).name(), " Pool Token"));

        _disableInitializers();
    }

    function initialize(
        uint256 supplyLimit,
        uint256 walletLimit,
        string memory symbolSuffix,
        string memory descPrefix,
        bytes memory extraData
    ) public virtual initializer {
        Errors.verifyNotEmpty(symbolSuffix, "symbolSuffix");
        Errors.verifyNotEmpty(descPrefix, "descPrefix");

        // init withdrawal queue to empty (slither issue)
        withdrawalQueue = new IDestinationVault[](0);

        navPerShareHighMarkTimestamp = block.timestamp;

        _setTotalSupplyLimit(supplyLimit);
        _setPerWalletLimit(walletLimit);

        factory = msg.sender;

        _symbol = string(abi.encodePacked("lmp", symbolSuffix));
        _desc = string(abi.encodePacked(descPrefix, " Pool Token"));
        nextManagementFeeTake = uint48(block.timestamp + MANAGEMENT_FEE_TAKE_TIMEFRAME);
        emit NextManagementFeeTakeSet(nextManagementFeeTake);

        ExtraData memory decodedInitData = abi.decode(extraData, (ExtraData));
        Errors.verifyNotZero(decodedInitData.lmpStrategyAddress, "lmpStrategyAddress");
        lmpStrategy = ILMPStrategy(decodedInitData.lmpStrategyAddress);
    }

    /**
     * @dev Returns the name of the token.
     */
    function name() public view virtual override(ERC20, IERC20) returns (string memory) {
        return _desc;
    }

    /**
     * @dev Returns the symbol of the token, usually a shorter version of the
     * name.
     */
    function symbol() public view virtual override(ERC20, IERC20) returns (string memory) {
        return _symbol;
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

    /// @notice Set the management fee taken.
    /// @dev Depending on time until next fee take, may update managementFeeBps directly or queue fee.
    /// @param fee Fee to update management fee to.
    function setManagementFeeBps(uint256 fee) external hasRole(Roles.LMP_MANAGEMENT_FEE_SETTER_ROLE) {
        if (fee > MAX_MANAGEMENT_FEE_BPS) {
            revert InvalidFee(fee);
        }

        /**
         * If the current timestamp is greater than the next fee take minus 45 days, we are withing the timeframe
         *      that we do not want to be able to set a new management fee, so we set `pendingManagementFeeBps` instead.
         *      This will be set as `managementFeeBps` when management fees are taken.
         *
         * Fee checked to fit into uint16 above, able to be wrapped without safe cast here.
         */
        // slither-disable-next-line timestamp
        if (block.timestamp > nextManagementFeeTake - MANAGEMENT_FEE_CHANGE_CUTOFF) {
            emit PendingManagementFeeSet(fee);
            pendingManagementFeeBps = uint16(fee);
        } else {
            emit ManagementFeeSet(fee);
            managementFeeBps = uint16(fee);
        }
    }

    /// @notice Set the address that will receive fees
    /// @param newFeeSink Address that will receive fees
    function setFeeSink(address newFeeSink) external onlyOwner {
        emit FeeSinkSet(newFeeSink);

        // Zero is valid. One way to disable taking fees
        // slither-disable-next-line missing-zero-check
        feeSink = newFeeSink;
    }

    /// @notice Sets the address that will receive management fees.
    /// @dev Zero address allowable.  Disables fees.
    /// @param newManagementFeeSink New managment fee address.
    function setManagementFeeSink(address newManagementFeeSink) external onlyOwner {
        emit ManagementFeeSinkSet(newManagementFeeSink);

        // slither-disable-next-line missing-zero-check
        managementFeeSink = newManagementFeeSink;
    }

    /// @notice Set the rewarder contract used by the vault.
    /// @param _rewarder Address of new rewarder.
    function setRewarder(address _rewarder) external {
        // Factory needs to be able to call for vault creation.
        if (msg.sender != factory && !_hasRole(Roles.LMP_REWARD_MANAGER_ROLE, msg.sender)) {
            revert Errors.AccessDenied();
        }

        Errors.verifyNotZero(_rewarder, "rewarder");

        address toBeReplaced = address(rewarder);
        // Check that the new rewarder has not been a rewarder before, and that the current rewarder and
        //      new rewarder addresses are not the same.
        if (pastRewarders.contains(_rewarder) || toBeReplaced == _rewarder) {
            revert Errors.ItemExists();
        }

        if (toBeReplaced != address(0)) {
            // slither-disable-next-line unused-return
            pastRewarders.add(toBeReplaced);
        }

        rewarder = IMainRewarder(_rewarder);
        emit RewarderSet(_rewarder, toBeReplaced);
    }

    /// @inheritdoc ILMPVault
    function getPastRewarders() external view returns (address[] memory) {
        return pastRewarders.values();
    }

    /// @inheritdoc ILMPVault
    function isPastRewarder(address _pastRewarder) external view returns (bool) {
        return pastRewarders.contains(_pastRewarder);
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
    function convertToAssets(uint256 shares) external view virtual returns (uint256 assets) {
        assets = _convertToAssets(shares, Math.Rounding.Down);
    }

    //////////////////////////////////////////////////////////////////////
    //								Deposit								//
    //////////////////////////////////////////////////////////////////////

    /// @dev See {IERC4626-maxDeposit}.
    function maxDeposit(address wallet) public view virtual override returns (uint256 maxAssets) {
        maxAssets = _convertToAssets(_maxMint(wallet), Math.Rounding.Up);
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
        Errors.verifyNotZero(shares, "shares");

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
        Errors.verifyNotZero(possibleAssets, "possibleAssets");

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
                    info.idleIncrease += info.totalAssetsPulled - info.totalAssetsToPull;
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

        // if totalSupply is now 0, reset the high water mark
        // slither-disable-next-line incorrect-equality
        if (totalSupply() == 0) {
            navPerShareHighMark = MAX_FEE_BPS;

            emit NewNavHighWatermark(navPerShareHighMark, block.timestamp);
        }

        emit Withdraw(msg.sender, receiver, owner, returnedAssets, shares);

        emit Nav(totalIdle, totalDebt, totalSupply());

        _baseAsset.safeTransfer(receiver, returnedAssets);

        return returnedAssets;
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
    function shutdown(VaultShutdownStatus reason) external onlyOwner {
        if (reason == VaultShutdownStatus.Active) {
            revert InvalidShutdownStatus(reason);
        }

        _shutdown = true;
        _shutdownStatus = reason;

        emit Shutdown(reason);
    }

    /// @inheritdoc ILMPVault
    function isShutdown() external view returns (bool) {
        return _shutdown;
    }

    /// @inheritdoc ILMPVault
    function shutdownStatus() external view returns (VaultShutdownStatus) {
        return _shutdownStatus;
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
        // slither-disable-next-line incorrect-equality
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
        // slither-disable-next-line incorrect-equality
        return totalAssets() > 0 || totalSupply() == 0;
    }

    function updateDebtReporting(address[] calldata _destinations)
        external
        nonReentrant
        hasRole(Roles.LMP_UPDATE_DEBT_REPORTING_ROLE)
        trackNavOps
    {
        _updateDebtReporting(_destinations);
    }

    //////////////////////////////////////////////////////////////////////////
    //							  Destinations     							//
    //////////////////////////////////////////////////////////////////////////

    function getDestinations() public view override(ILMPVault, IStrategy) returns (address[] memory) {
        return destinations.values();
    }

    /// @inheritdoc ILMPVault
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

    /// @inheritdoc ILMPVault
    // solhint-disable-next-line no-unused-vars
    function addToWithdrawalQueueHead(address destinationVault) external {
        revert Errors.NotImplemented();
    }

    /// @inheritdoc ILMPVault
    // solhint-disable-next-line no-unused-vars
    function addToWithdrawalQueueTail(address destinationVault) external {
        revert Errors.NotImplemented();
    }

    /// @inheritdoc ILMPVault
    function getDestinationInfo(address destVault) external view returns (LMPDebt.DestinationInfo memory) {
        return destinationInfo[destVault];
    }

    //////////////////////////////////////////////////////////////////////////
    //                                                                      //
    //							Strategy Related   							//
    //                                                                      //
    //////////////////////////////////////////////////////////////////////////

    /// @inheritdoc IStrategy
    function flashRebalance(
        IERC3156FlashBorrower receiver,
        RebalanceParams memory rebalanceParams,
        bytes calldata data
    ) public nonReentrant hasRole(Roles.SOLVER_ROLE) trackNavOps {
        // make sure there's something to do
        if (rebalanceParams.amountIn == 0 && rebalanceParams.amountOut == 0) {
            revert Errors.InvalidParams();
        }

        if (rebalanceParams.destinationIn == rebalanceParams.destinationOut) {
            revert RebalanceDestinationsMatch(rebalanceParams.destinationOut);
        }

        // Get out destination summary stats
        IStrategy.SummaryStats memory outSummary = lmpStrategy.getRebalanceOutSummaryStats(rebalanceParams);
        (uint256 idle, uint256 debt) = LMPDebt.flashRebalance(
            destinationInfo[rebalanceParams.destinationOut],
            destinationInfo[rebalanceParams.destinationIn],
            receiver,
            rebalanceParams,
            outSummary,
            lmpStrategy,
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

    /// @inheritdoc ILMPVault
    function isDestinationQueuedForRemoval(address dest) external view returns (bool) {
        return removalQueue.contains(dest);
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
        uint256 debt = totalDebt + afterNTotalDebt - prevNTotalDebt;

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
        uint256 timestamp = block.timestamp;

        // If there's no supply then there should be no assets and so nothing
        // to actually take fees on
        // slither-disable-next-line incorrect-equality
        if (totalSupply == 0) {
            return;
        }
        uint256 assets = totalAssets();

        // slither-disable-next-line incorrect-equality
        if (totalAssetsHighMark == 0) {
            // Initialize our high water mark to the current assets
            totalAssetsHighMark = assets;
        }

        // slither-disable-start timestamp
        // If current timestamp is greater than nextManagementFeeTake, operations need to happen for management fee.
        if (timestamp > nextManagementFeeTake) {
            // If there is a management fee and fee sink set, take the fee.
            if (managementFeeBps > 0 && managementFeeSink != address(0)) {
                totalSupply = _collectManagementFees(totalSupply, assets);
            }

            // If there is a pending management fee set, replace management fee with pending after fees already taken.
            if (pendingManagementFeeBps > 0) {
                emit ManagementFeeSet(pendingManagementFeeBps);
                emit PendingManagementFeeSet(0);

                managementFeeBps = pendingManagementFeeBps;
                pendingManagementFeeBps = 0;
            }

            // Needs to be updated any time timestamp > `nextTakeManagementFee` to keep up to date.
            nextManagementFeeTake += uint48(MANAGEMENT_FEE_TAKE_TIMEFRAME);
            emit NextManagementFeeTakeSet(nextManagementFeeTake);
        }

        // slither-disable-end timestamp
        uint256 currentNavPerShare = ((idle + debt) * MAX_FEE_BPS) / totalSupply;
        uint256 effectiveNavPerShareHighMark = _calculateEffectiveNavPerShareHighMark(
            block.timestamp,
            currentNavPerShare,
            navPerShareHighMarkTimestamp,
            navPerShareHighMark,
            totalAssetsHighMark,
            assets
        );

        if (currentNavPerShare > effectiveNavPerShareHighMark) {
            // Even if we aren't going to take the fee (haven't set a sink)
            // We still want to calculate so we can emit for off-chain analysis
            profit = (currentNavPerShare - effectiveNavPerShareHighMark) * totalSupply;
            fees = profit.mulDiv(performanceFeeBps, (MAX_FEE_BPS ** 2), Math.Rounding.Up);
            if (fees > 0 && sink != address(0)) {
                // Calculated separate from other mints as normal share mint is round down
                // Note: We use Lido's formula: from https://docs.lido.fi/guides/lido-tokens-integration-guide/#fees
                // suggested by: https://github.com/sherlock-audit/2023-06-tokemak-judging/blob/main/486-H/624-best.md
                // but we scale down `profit` by MAX_FEE_BPS
                shares = Math.mulDiv(
                    performanceFeeBps * profit / MAX_FEE_BPS,
                    totalSupply,
                    (assets * MAX_FEE_BPS) - (performanceFeeBps * profit / MAX_FEE_BPS),
                    Math.Rounding.Up
                );
                _mint(sink, shares);
                totalSupply += shares;
                currentNavPerShare = ((idle + debt) * MAX_FEE_BPS) / totalSupply;
                emit Deposit(address(this), sink, 0, shares);
            }

            // Set our new high water mark, the last nav/share height we took fees
            navPerShareHighMark = currentNavPerShare;
            navPerShareHighMarkTimestamp = timestamp;
            emit NewNavHighWatermark(currentNavPerShare, timestamp);
        }
        // Set our new high water mark for totalAssets, regardless if we took fees
        if (totalAssetsHighMark < assets) {
            totalAssetsHighMark = assets;
            totalAssetsHighMarkTimestamp = block.timestamp;
            emit NewTotalAssetsHighWatermark(totalAssetsHighMark, totalAssetsHighMarkTimestamp);
        }
        emit FeeCollected(fees, sink, shares, profit, idle, debt);

        // NOTE: NavChanged event thrown in higher level caller
    }

    function _calculateEffectiveNavPerShareHighMark(
        uint256 currentBlock,
        uint256 currentNav,
        uint256 lastHighMarkTimestamp,
        uint256 lastHighMark,
        uint256 aumHighMark,
        uint256 aumCurrent
    ) internal view returns (uint256) {
        if (lastHighMark == 0) {
            // If we got 0, we shouldn't increase it
            return 0;
        }
        uint256 workingHigh = lastHighMark;
        uint256 daysSinceLastFeeEarned = (currentBlock - lastHighMarkTimestamp) / 60 / 60 / 24;

        if (daysSinceLastFeeEarned > 600) {
            return currentNav;
        }
        if (daysSinceLastFeeEarned > 60 && daysSinceLastFeeEarned <= 600) {
            uint256 one = 10 ** decimals();

            // AUM_min = min(AUM_high, AUM_current)
            uint256 minAssets = aumCurrent < aumHighMark ? aumCurrent : aumHighMark;

            // AUM_max = max(AUM_high, AUM_current);
            uint256 maxAssets = aumCurrent > aumHighMark ? aumCurrent : aumHighMark;

            /// 0.999 * (AUM_min / AUM_max)
            // dividing by `one` because we need end up with a number in the 100's wei range
            uint256 g1 = ((999 * minAssets * one) / (maxAssets * one));

            /// 0.99 * (1 - AUM_min / AUM_max)
            // dividing by `10 ** (decimals() - 1)` because we need to divide 100 out for our % and then
            // we want to end up with a number in the 10's wei range
            uint256 g2 = (99 * (one - (minAssets * one / maxAssets))) / 10 ** (decimals() - 1);

            uint256 gamma = g1 + g2;

            uint256 daysDiff = daysSinceLastFeeEarned - 60;
            for (uint256 i = 0; i < daysDiff / 25; ++i) {
                // slither-disable-next-line divide-before-multiply
                workingHigh = workingHigh * (gamma ** 25 / 1e72) / 1000;
            }
            // slither-disable-next-line weak-prng
            for (uint256 i = 0; i < daysDiff % 25; ++i) {
                // slither-disable-next-line divide-before-multiply
                workingHigh = workingHigh * gamma / 1000;
            }
        }
        return workingHigh;
    }

    /// @dev Collects management fees.
    function _collectManagementFees(uint256 totalSupply, uint256 assets) internal returns (uint256) {
        // Management fee * assets used multiple places below, gas savings when calc here.
        uint256 managementFeeMultAssets = managementFeeBps * assets;
        address managementSink = managementFeeSink;

        // We calculate the shares using the same formula as performance fees, without scaling down
        uint256 shares = Math.mulDiv(
            managementFeeMultAssets, totalSupply, (assets * MAX_FEE_BPS) - (managementFeeMultAssets), Math.Rounding.Up
        );
        _mint(managementSink, shares);
        totalSupply += shares;

        // Fee in assets that we are taking.
        uint256 fees = managementFeeMultAssets.ceilDiv(MAX_FEE_BPS);
        emit Deposit(address(this), managementSink, 0, shares);
        emit ManagementFeeCollected(fees, managementSink, shares);

        return totalSupply;
    }

    function _beforeTokenTransfer(address from, address to, uint256 amount) internal virtual override whenNotPaused {
        // Nothing to do really do here
        if (from == to) {
            return;
        }

        // Make sure the destination wallet total share balance doesn't go above the
        // current perWalletLimit, except for the feeSink, rewarder and router.
        if (
            to != feeSink && to != address(rewarder) && to != address(0)
                && to != address(systemRegistry.lmpVaultRouter())
        ) {
            if (balanceOf(to) + rewarder.balanceOf(to) + amount > perWalletLimit) revert OverWalletLimit(to);
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
        // slither-disable-next-line incorrect-equality
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
        // slither-disable-next-line incorrect-equality
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
        // overflow protection / max reasonable limit
        if (newSupplyLimit > type(uint112).max) {
            revert TotalSupplyOverLimit();
        }

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

        // overflow protection / max reasonable limit
        if (newWalletLimit > type(uint112).max) {
            revert PerWalletOverLimit();
        }

        perWalletLimit = newWalletLimit;

        emit PerWalletLimitSet(newWalletLimit);
    }

    /// @notice Allow the updating of symbol/desc for the vault (only AFTER shutdown)
    function setSymbolAndDescAfterShutdown(string memory newSymbol, string memory newDesc) external onlyOwner {
        Errors.verifyNotEmpty(newSymbol, "newSymbol");
        Errors.verifyNotEmpty(newDesc, "newDesc");

        // make sure the vault is no longer active
        if (_shutdownStatus == VaultShutdownStatus.Active) {
            revert InvalidShutdownStatus(_shutdownStatus);
        }

        emit SymbolAndDescSet(newSymbol, newDesc);

        _symbol = newSymbol;
        _desc = newDesc;
    }
}

//slither-disable-end reentrancy-no-eth,reentrancy-benign,timestamp,similar-names
