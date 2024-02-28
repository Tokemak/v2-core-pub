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
import { SecurityBase } from "src/security/SecurityBase.sol";
import { ILMPVault } from "src/interfaces/vault/ILMPVault.sol";
import { AutoPoolFees } from "src/vault/libs/AutoPoolFees.sol";
import { AutoPoolToken } from "src/vault/libs/AutoPoolToken.sol";
import { AutoPool4626 } from "src/vault/libs/AutoPool4626.sol";
import { IStrategy } from "src/interfaces/strategy/IStrategy.sol";
import { Math } from "openzeppelin-contracts/utils/math/Math.sol";
import { WithdrawalQueue } from "src/strategy/WithdrawalQueue.sol";
import { LMPDestinations } from "src/vault/libs/LMPDestinations.sol";
import { ISystemRegistry } from "src/interfaces/ISystemRegistry.sol";
import { IERC20 } from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import { ISystemComponent } from "src/interfaces/ISystemComponent.sol";
import { ILMPStrategy } from "src/interfaces/strategy/ILMPStrategy.sol";
import { IERC4626 } from "openzeppelin-contracts/interfaces/IERC4626.sol";
import { IMainRewarder } from "src/interfaces/rewarders/IMainRewarder.sol";
import { StructuredLinkedList } from "src/strategy/StructuredLinkedList.sol";
import { IDestinationVault } from "src/interfaces/vault/IDestinationVault.sol";
import { SafeERC20 } from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";
import { Initializable } from "openzeppelin-contracts/proxy/utils/Initializable.sol";
import { EnumerableSet } from "openzeppelin-contracts/utils/structs/EnumerableSet.sol";
import { IERC20Metadata } from "openzeppelin-contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { IERC3156FlashBorrower } from "openzeppelin-contracts/interfaces/IERC3156FlashBorrower.sol";

contract LMPVault is ISystemComponent, Initializable, ILMPVault, IStrategy, SecurityBase, Pausable, NonReentrant {
    using EnumerableSet for EnumerableSet.AddressSet;
    using Math for uint256;
    using SafeERC20 for IERC20Metadata;
    using WithdrawalQueue for StructuredLinkedList.List;
    using AutoPoolToken for AutoPoolToken.TokenData;

    /// Be careful around the use of totalSupply and balanceOf. If you go directly to the _tokenData struct you may miss
    /// out on the profit share unlock logic or the checking the balance of the pool itself

    /// =====================================================
    /// Constant Vars
    /// =====================================================

    /// @notice 100% == 10000
    uint256 public constant FEE_DIVISOR = 10_000;

    /// =====================================================
    /// Immutable Vars
    /// =====================================================

    /// @notice Overarching baseAsset type
    bytes32 public immutable vaultType = VaultTypes.LST;

    /// @notice Instance of this system this vault is tied to
    /// @dev Exposed via `getSystemRegistry()`
    ISystemRegistry internal immutable _systemRegistry;

    /// @notice The asset that is deposited into the vault
    /// @dev Exposed via `asset()`
    IERC20Metadata internal immutable _baseAsset;

    /// @notice Decimals of the base asset. Used as the decimals for the vault itself
    /// @dev Exposed via `decimals()`
    uint8 internal immutable _baseAssetDecimals;

    bool public immutable _checkUsers;

    /// =====================================================
    /// Internal Vars
    /// =====================================================

    /// @notice Balances, allowances, and supply for the pool
    /// @dev Want to keep this var in this position
    AutoPoolToken.TokenData internal _tokenData;

    /// @notice Pool/token name
    string internal _name;

    /// @notice Pool/token symbol
    string internal _symbol;

    /// @notice Full list of possible destinations that could be deployed to
    /// @dev Exposed via `getDestinations()`
    EnumerableSet.AddressSet internal _destinations;

    /// @notice Destinations that are queued for removal
    /// @dev Exposed via `getRemovalQueue`
    EnumerableSet.AddressSet internal _removalQueue;

    /// @notice Lookup of destinationVaultAddress -> Info .. Debt reporting snapshot info
    /// @dev Exposed via `getDestinationInfo`
    mapping(address => LMPDebt.DestinationInfo) internal _destinationInfo;

    /// @notice Whether or not the vault has been shutdown
    /// @dev Exposed via `isShutdown()`
    bool internal _shutdown;

    /// @notice Reason for shutdown (or `Active` if not shutdown)
    /// @dev Exposed via `shutdownStatus()`
    VaultShutdownStatus internal _shutdownStatus;

    /// @notice Ordered list of destinations to withdraw from
    /// @dev Exposed via `getWithdrawalQueue()`
    StructuredLinkedList.List internal _withdrawalQueue;

    /// @notice Ordered list of destinations to debt report on. Ordered from oldest to newest
    /// @dev Exposed via `getDebtReportingQueue()`
    StructuredLinkedList.List internal _debtReportQueue;

    /// @notice State and settings related to gradual profit unlock
    /// @dev Exposed via `getProfitUnlockSettings()`
    ILMPVault.ProfitUnlockSettings internal _profitUnlockSettings;

    /// @notice State and settings related to periodic and streaming fees
    /// @dev Exposed via `getFeeSettings()`
    ILMPVault.AutoPoolFeeSettings internal _feeSettings;

    /// @notice Asset tracking for idle and debt values
    /// @dev Exposed via `getAssetBreakdown()`
    ILMPVault.AssetBreakdown internal _assetBreakdown;

    /// @notice Rewarders that have been replaced.
    /// @dev Exposed via `getPastRewarders()`
    EnumerableSet.AddressSet internal _pastRewarders;

    /// =====================================================
    /// Public Vars
    /// =====================================================

    /// @notice Factory contract that created this vault
    address public factory;

    /// @notice Main rewarder for this contract
    IMainRewarder public rewarder;

    /// @notice The strategy logic for the LMP
    ILMPStrategy public lmpStrategy;

    /// @notice Temporary restriction of depositors
    mapping(address => bool) public allowedUsers;

    /// =====================================================
    /// Events
    /// =====================================================

    event NewNavShareFeeMark(uint256 navPerShare, uint256 timestamp);
    event SymbolAndDescSet(string symbol, string desc);

    /// =====================================================
    /// Errors
    /// =====================================================

    error WithdrawShareCalcInvalid(uint256 currentShares, uint256 cachedShares);
    error RewarderAlreadySet();
    error RebalanceDestinationsMatch(address destinationVault);
    error InvalidDestination(address destination);
    error NavChanged(uint256 oldNav, uint256 newNav);
    error NavOpsInProgress();
    error VaultShutdown();
    error NavDecreased(uint256 oldNav, uint256 newNav);
    error InvalidUser();

    /// =====================================================
    /// Modifiers
    /// =====================================================

    modifier onlyAllowedUsers(address receiver) {
        _ensureAllowedUsers(receiver);
        _;
    }

    /// @notice Reverts if nav/share decreases during a deposit/mint/withdraw/redeem
    /// @dev Increases are allowed. Ignored when supply is 0
    modifier noNavPerShareDecrease(TotalAssetPurpose purpose) {
        (uint256 oldNav, uint256 startingTotalSupply) = _snapStartNav(purpose);
        _;
        _ensureNoNavPerShareDecrease(oldNav, startingTotalSupply, purpose);
    }

    /// @notice Reverts if any nav/share changing operations are in progress across the system
    /// @dev Any rebalance or debtReporting on any pool
    modifier ensureNoNavOps() {
        if (_systemRegistry.systemSecurity().navOpsInProgress() > 0) {
            revert NavOpsInProgress();
        }
        _;
    }

    /// @notice Globally track operations that change nav/share in a vault
    /// @dev Doesn't revert, only meant to track so that `ensureNoNavOps()` can revert when appropriate
    modifier trackNavOps() {
        _systemRegistry.systemSecurity().enterNavOperation();
        _;
        // slither-disable-next-line reentrancy-no-eth
        _systemRegistry.systemSecurity().exitNavOperation();
    }

    /// =====================================================
    /// Functions - Constructor
    /// =====================================================

    constructor(
        ISystemRegistry systemRegistry,
        address _vaultAsset,
        bool checkUsers
    ) SecurityBase(address(systemRegistry.accessController())) Pausable(systemRegistry) {
        Errors.verifyNotZero(address(systemRegistry), "systemRegistry");
        _systemRegistry = systemRegistry;

        uint8 dec = IERC20Metadata(_vaultAsset).decimals();

        _baseAssetDecimals = dec;
        _baseAsset = IERC20Metadata(_vaultAsset);
        _symbol = string(abi.encodePacked("lmp", IERC20Metadata(_vaultAsset).symbol()));
        _name = string(abi.encodePacked(IERC20Metadata(_vaultAsset).name(), " Pool Token"));

        _checkUsers = checkUsers;

        _disableInitializers();
    }

    /// =====================================================
    /// Functions - External
    /// =====================================================

    function initialize(
        address strategy,
        string memory symbolSuffix,
        string memory descPrefix,
        bytes memory
    ) external virtual initializer {
        Errors.verifyNotEmpty(symbolSuffix, "symbolSuffix");
        Errors.verifyNotEmpty(descPrefix, "descPrefix");
        Errors.verifyNotZero(strategy, "lmpStrategyAddress");

        factory = msg.sender;

        _symbol = string(abi.encodePacked("lmp", symbolSuffix));
        _name = string(abi.encodePacked(descPrefix, " Pool Token"));

        AutoPoolFees.initializeFeeSettings(_feeSettings);

        lmpStrategy = ILMPStrategy(strategy);
    }

    /// @notice Mints Vault shares to receiver by depositing exactly amount of underlying tokens
    /// @dev No nav/share changing operations, debt reportings or rebalances,
    /// can be happening throughout the entire system
    function deposit(
        uint256 assets,
        address receiver
    )
        external
        virtual
        override
        nonReentrant
        noNavPerShareDecrease(TotalAssetPurpose.Deposit)
        ensureNoNavOps
        onlyAllowedUsers(receiver)
        returns (uint256 shares)
    {
        Errors.verifyNotZero(assets, "assets");

        // Handles the vault being paused, returns 0
        if (assets > maxDeposit(receiver)) {
            revert ERC4626DepositExceedsMax(assets, maxDeposit(receiver));
        }

        uint256 ta = LMPDebt._totalAssetsTimeChecked(_debtReportQueue, _destinationInfo, TotalAssetPurpose.Deposit);
        shares = convertToShares(assets, ta, totalSupply(), Math.Rounding.Down);

        Errors.verifyNotZero(shares, "shares");

        _transferAndMint(assets, shares, receiver);
    }

    /// @notice Mints exactly shares Vault shares to receiver by depositing amount of underlying tokens.
    function mint(
        uint256 shares,
        address receiver
    )
        public
        virtual
        override
        nonReentrant
        noNavPerShareDecrease(TotalAssetPurpose.Deposit)
        ensureNoNavOps
        onlyAllowedUsers(receiver)
        returns (uint256 assets)
    {
        // Handles the vault being paused, returns 0
        if (shares > maxMint(receiver)) {
            revert ERC4626MintExceedsMax(shares, maxMint(receiver));
        }

        uint256 ta = LMPDebt._totalAssetsTimeChecked(_debtReportQueue, _destinationInfo, TotalAssetPurpose.Deposit);
        assets = convertToAssets(shares, ta, totalSupply(), Math.Rounding.Up);

        _transferAndMint(assets, shares, receiver);
    }

    /// @notice Burns shares from owner and sends exactly assets of underlying tokens to receiver.
    function withdraw(
        uint256 assets,
        address receiver,
        address owner
    )
        public
        virtual
        override
        nonReentrant
        whenNotPaused
        noNavPerShareDecrease(TotalAssetPurpose.Withdraw)
        ensureNoNavOps
        onlyAllowedUsers(receiver)
        returns (uint256 shares)
    {
        Errors.verifyNotZero(assets, "assets");

        //slither-disable-next-line unused-return
        (uint256 actualAssets, uint256 actualShares,) = LMPDebt.withdraw(
            assets,
            LMPDebt._totalAssetsTimeChecked(_debtReportQueue, _destinationInfo, TotalAssetPurpose.Withdraw),
            _assetBreakdown,
            _withdrawalQueue,
            _destinationInfo
        );

        shares = actualShares;

        // TODO: Pretty sure we can just pass assets here instead of actualAssets.
        // We know it can't be less because of check above, and _withdraw will ensure
        // its not more.
        _completeWithdrawal(actualAssets, shares, owner, receiver);
    }

    /// @notice Burns exactly shares from owner and sends assets of underlying tokens to receiver.
    function redeem(
        uint256 shares,
        address receiver,
        address owner
    )
        public
        virtual
        override
        nonReentrant
        whenNotPaused
        noNavPerShareDecrease(TotalAssetPurpose.Withdraw)
        ensureNoNavOps
        onlyAllowedUsers(receiver)
        returns (uint256 assets)
    {
        uint256 maxShares = maxRedeem(owner);
        if (shares > maxShares) {
            revert ERC4626ExceededMaxRedeem(owner, shares, maxShares);
        }

        uint256 ta = LMPDebt._totalAssetsTimeChecked(_debtReportQueue, _destinationInfo, TotalAssetPurpose.Withdraw);
        uint256 possibleAssets = convertToAssets(shares, ta, totalSupply(), Math.Rounding.Down);
        Errors.verifyNotZero(possibleAssets, "possibleAssets");

        //slither-disable-next-line unused-return
        (uint256 actualAssets, uint256 actualShares,) =
            LMPDebt.redeem(possibleAssets, ta, _assetBreakdown, _withdrawalQueue, _destinationInfo);

        assets = actualAssets;

        assert(actualShares <= shares);

        _completeWithdrawal(assets, shares, owner, receiver);
    }

    /// @notice Enable or disable the high water mark on the rebalance fee
    /// @dev Will revert if set to the same value
    function setRebalanceFeeHighWaterMarkEnabled(bool enabled) external hasRole(Roles.LMP_FEE_SETTER_ROLE) {
        AutoPoolFees.setRebalanceFeeHighWaterMarkEnabled(_feeSettings, enabled);
    }

    /// @notice Set the fee that will be taken when profit is realized
    /// @dev Resets the high water to current value
    /// @param fee Percent. 100% == 10000
    function setStreamingFeeBps(uint256 fee) external nonReentrant hasRole(Roles.LMP_FEE_SETTER_ROLE) {
        AutoPoolFees.setStreamingFeeBps(_feeSettings, fee);
    }

    /// @notice Set the periodic fee taken.
    /// @dev Depending on time until next fee take, may update periodicFeeBps directly or queue fee.
    /// @param fee Fee to update periodic fee to.
    function setPeriodicFeeBps(uint256 fee) external hasRole(Roles.LMP_PERIODIC_FEE_SETTER_ROLE) {
        AutoPoolFees.setPeriodicFeeBps(_feeSettings, fee);
    }

    /// @notice Set the address that will receive fees
    /// @param newFeeSink Address that will receive fees
    function setFeeSink(address newFeeSink) external hasRole(Roles.LMP_FEE_SETTER_ROLE) {
        AutoPoolFees.setFeeSink(_feeSettings, newFeeSink);
    }

    /// @notice Sets the address that will receive periodic fees.
    /// @dev Zero address allowable.  Disables fees.
    /// @param newPeriodicFeeSink New periodic fee address.
    function setPeriodicFeeSink(address newPeriodicFeeSink) external hasRole(Roles.LMP_PERIODIC_FEE_SETTER_ROLE) {
        AutoPoolFees.setPeriodicFeeSink(_feeSettings, newPeriodicFeeSink);
    }

    function setProfitUnlockPeriod(uint48 newUnlockPeriodSeconds) external hasRole(Roles.AUTO_POOL_ADMIN) {
        AutoPoolFees.setProfitUnlockPeriod(_profitUnlockSettings, _tokenData, newUnlockPeriodSeconds);
    }

    function toggleAllowedUser(address user) external hasRole(Roles.AUTO_POOL_ADMIN) {
        allowedUsers[user] = !allowedUsers[user];
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
        if (_pastRewarders.contains(_rewarder) || toBeReplaced == _rewarder) {
            revert Errors.ItemExists();
        }

        if (toBeReplaced != address(0)) {
            // slither-disable-next-line unused-return
            _pastRewarders.add(toBeReplaced);
        }

        rewarder = IMainRewarder(_rewarder);
        emit RewarderSet(_rewarder, toBeReplaced);
    }

    /// @inheritdoc ILMPVault
    function getPastRewarders() external view returns (address[] memory) {
        return _pastRewarders.values();
    }

    /// @inheritdoc ILMPVault
    function isPastRewarder(address _pastRewarder) external view returns (bool) {
        return _pastRewarders.contains(_pastRewarder);
    }

    /// @notice Allow the updating of symbol/desc for the vault (only AFTER shutdown)
    function setSymbolAndDescAfterShutdown(
        string memory newSymbol,
        string memory newName
    ) external hasRole(Roles.AUTO_POOL_ADMIN) {
        Errors.verifyNotEmpty(newSymbol, "newSymbol");
        Errors.verifyNotEmpty(newName, "newName");

        // make sure the vault is no longer active
        if (_shutdownStatus == VaultShutdownStatus.Active) {
            revert InvalidShutdownStatus(_shutdownStatus);
        }

        emit SymbolAndDescSet(newSymbol, newName);

        _symbol = newSymbol;
        _name = newName;
    }

    /// @inheritdoc ILMPVault
    function isShutdown() external view returns (bool) {
        return _shutdown;
    }

    /// @inheritdoc ILMPVault
    function shutdownStatus() external view returns (VaultShutdownStatus) {
        return _shutdownStatus;
    }

    /// @notice Returns state and settings related to gradual profit unlock
    function getProfitUnlockSettings() external view returns (ILMPVault.ProfitUnlockSettings memory) {
        return _profitUnlockSettings;
    }

    /// @notice Returns state and settings related to periodic and streaming fees
    function getFeeSettings() external view returns (ILMPVault.AutoPoolFeeSettings memory) {
        return _feeSettings;
    }

    /// @notice Returns the name of the token
    function name() public view virtual override returns (string memory) {
        return _name;
    }

    /// @notice Returns the symbol of the token
    function symbol() public view virtual override returns (string memory) {
        return _symbol;
    }

    /// @notice Returns the decimals of the token, same as the underlying asset
    function decimals() public view virtual override returns (uint8) {
        return _baseAssetDecimals;
    }

    /// @notice Returns the address of the underlying token used for the Vault for accounting, depositing, and
    /// withdrawing.
    function asset() public view virtual override returns (address) {
        return address(_baseAsset);
    }

    /// @notice Returns the total amount of the underlying asset that is “managed” by Vault.
    /// @dev Utilizes the "Global" purpose internally
    function totalAssets() public view override returns (uint256) {
        return AutoPool4626.totalAssets(_assetBreakdown, TotalAssetPurpose.Global);
    }

    /// @notice Returns the total amount of the underlying asset that is “managed” by the Vault with respect to its
    /// usage
    /// @dev Value changes based on purpose. Global is an avg. Deposit is valued higher. Withdraw is valued lower.
    /// @param purpose The calculation the total assets will be used in
    function totalAssets(TotalAssetPurpose purpose) public view returns (uint256) {
        return AutoPool4626.totalAssets(_assetBreakdown, purpose);
    }

    function getAssetBreakdown() public view override returns (ILMPVault.AssetBreakdown memory) {
        return _assetBreakdown;
    }

    /// @notice Returns the amount of shares that the Vault would exchange for the amount of assets provided,
    /// in an ideal scenario where all the conditions are met
    function convertToShares(uint256 assets) public view virtual returns (uint256 shares) {
        shares = convertToShares(assets, totalAssets(TotalAssetPurpose.Global), totalSupply(), Math.Rounding.Down);
    }

    /// @notice Returns the amount of shares that the Vault would exchange for the amount of assets provided,
    /// in an ideal scenario where all the conditions are met
    function convertToShares(
        uint256 assets,
        uint256 totalAssetsForPurpose,
        uint256 supply,
        Math.Rounding rounding
    ) public view virtual returns (uint256 shares) {
        // slither-disable-next-line incorrect-equality
        shares = (assets == 0 || supply == 0) ? assets : assets.mulDiv(supply, totalAssetsForPurpose, rounding);
    }

    /// @notice Returns the amount of assets that the Vault would exchange for the amount of shares provided, in an
    /// ideal
    /// scenario where all the conditions are met.
    function convertToAssets(uint256 shares) external view virtual returns (uint256 assets) {
        assets = convertToAssets(shares, totalAssets(TotalAssetPurpose.Global), totalSupply(), Math.Rounding.Down);
    }

    /// @notice Returns the amount of assets that the Vault would exchange for the amount of shares provided, in an
    /// ideal
    /// scenario where all the conditions are met.
    function convertToAssets(
        uint256 shares,
        uint256 totalAssetsForPurpose,
        uint256 supply,
        Math.Rounding rounding
    ) public view virtual returns (uint256 assets) {
        // slither-disable-next-line incorrect-equality
        assets = (supply == 0) ? shares : shares.mulDiv(totalAssetsForPurpose, supply, rounding);
    }

    /// @notice Returns the amount of unlocked profit shares that will be burned
    function unlockedShares() external view returns (uint256 shares) {
        shares = AutoPoolFees.unlockedShares(_profitUnlockSettings, _tokenData);
    }

    /// @notice Returns the amount of tokens in existence.
    /// @dev Subtracts any unlocked profit shares that will be burned
    function totalSupply() public view virtual override(IERC20) returns (uint256 shares) {
        shares = AutoPool4626.totalSupply(_tokenData, _profitUnlockSettings);
    }

    /// @notice Returns the amount of tokens owned by account.
    /// @dev Subtracts any unlocked profit shares that will be burned when account is the Vault itself
    function balanceOf(address account) public view override(IERC20) returns (uint256) {
        return AutoPool4626.balanceOf(_tokenData, _profitUnlockSettings, account);
    }

    /// @notice Returns the amount of tokens owned by wallet.
    /// @dev Does not subtract any unlocked profit shares that should be burned when wallet is the Vault itself
    function balanceOfActual(address account) public view returns (uint256) {
        return _tokenData.balances[account];
    }

    /// @notice Returns the remaining number of tokens that `spender` will be allowed to spend on
    /// behalf of `owner` through {transferFrom}. This is zero by default
    /// @dev This value changes when `approve` or `transferFrom` are called
    function allowance(address owner, address spender) public view virtual returns (uint256) {
        return _tokenData.allowances[owner][spender];
    }

    /// @notice Sets a `value` amount of tokens as the allowance of `spender` over the caller's tokens.
    function approve(address spender, uint256 value) public virtual returns (bool) {
        return _tokenData.approve(spender, value);
    }

    /// @notice Moves a `value` amount of tokens from `from` to `to` using the allowance mechanism.
    /// `value` is then deducted from the caller's allowance.
    function transferFrom(address from, address to, uint256 value) public virtual whenNotPaused returns (bool) {
        return _tokenData.transferFrom(from, to, value);
    }

    /// @notice Moves a `value` amount of tokens from the caller's account to `to`
    function transfer(address to, uint256 value) public virtual whenNotPaused returns (bool) {
        return _tokenData.transfer(to, value);
    }

    /// @notice Returns the next unused nonce for an address.
    function nonces(address owner) public view virtual returns (uint256) {
        return _tokenData.nonces[owner];
    }

    function getSystemRegistry() external view override returns (address) {
        return address(_systemRegistry);
    }

    // solhint-disable-next-line func-name-mixedcase
    function DOMAIN_SEPARATOR() public view virtual returns (bytes32) {
        return keccak256(
            abi.encode(
                AutoPoolToken.TYPE_HASH,
                keccak256(bytes("Tokemak")),
                keccak256(bytes("1")),
                block.chainid,
                address(this)
            )
        );
    }

    function permit(
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) public virtual {
        _tokenData.permit(owner, spender, value, deadline, v, r, s);
    }

    /// @notice Returns the maximum amount of the underlying asset that can be
    /// deposited into the Vault for the receiver, through a deposit call
    function maxDeposit(address wallet) public view virtual override returns (uint256 maxAssets) {
        maxAssets =
            convertToAssets(maxMint(wallet), totalAssets(TotalAssetPurpose.Deposit), totalSupply(), Math.Rounding.Up);
    }

    /// @notice Simulate the effects of the deposit at the current block, given current on-chain conditions.
    function previewDeposit(uint256 assets) public view virtual returns (uint256 shares) {
        shares = convertToShares(assets, totalAssets(TotalAssetPurpose.Deposit), totalSupply(), Math.Rounding.Down);
    }

    /// @notice Returns the maximum amount of the Vault shares that
    /// can be minted for the receiver, through a mint call.
    function maxMint(address wallet) public view virtual override returns (uint256 maxShares) {
        maxShares =
            AutoPool4626.maxMint(_assetBreakdown, _tokenData, _profitUnlockSettings, wallet, paused(), _shutdown);
    }

    /// @notice Returns the maximum amount of the underlying asset that can
    /// be withdrawn from the owner balance in the Vault, through a withdraw call
    function maxWithdraw(address owner) public view virtual returns (uint256 maxAssets) {
        maxAssets = paused() ? 0 : previewRedeem(balanceOf(owner));
    }

    /// @notice Returns the maximum amount of Vault shares that can be redeemed
    /// from the owner balance in the Vault, through a redeem call
    function maxRedeem(address owner) public view virtual returns (uint256 maxShares) {
        maxShares = _maxRedeem(owner);
    }

    /// @notice Simulate the effects of a mint at the current block, given current on-chain conditions
    function previewMint(uint256 shares) public view virtual returns (uint256 assets) {
        assets = convertToAssets(shares, totalAssets(TotalAssetPurpose.Deposit), totalSupply(), Math.Rounding.Up);
    }

    /// @notice Simulate the effects of their withdrawal at the current block, given current on-chain conditions.
    function previewWithdraw(uint256 assets) public view virtual returns (uint256 shares) {
        shares = convertToShares(assets, totalAssets(TotalAssetPurpose.Withdraw), totalSupply(), Math.Rounding.Up);
    }

    /// @notice Simulate the effects of their redemption at the current block, given current on-chain conditions.
    function previewRedeem(uint256 shares) public view virtual override returns (uint256) {
        return convertToAssets(shares, totalAssets(TotalAssetPurpose.Withdraw), totalSupply(), Math.Rounding.Down);
    }

    function _completeWithdrawal(uint256 assets, uint256 shares, address owner, address receiver) internal virtual {
        if (msg.sender != owner) {
            uint256 allowed = allowance(owner, msg.sender);
            if (allowed != type(uint256).max) {
                if (shares > allowed) revert AmountExceedsAllowance(shares, allowed);

                unchecked {
                    _tokenData.approve(owner, msg.sender, allowed - shares);
                }
            }
        }

        _tokenData.burn(owner, shares);

        // if totalSupply is now 0, reset the high water mark
        // slither-disable-next-line incorrect-
        uint256 ts = totalSupply();
        if (ts == 0) {
            _feeSettings.navPerShareLastFeeMark = FEE_DIVISOR;

            emit NewNavShareFeeMark(FEE_DIVISOR, block.timestamp);
        }

        emit Withdraw(msg.sender, receiver, owner, assets, shares);

        emit Nav(_assetBreakdown.totalIdle, _assetBreakdown.totalDebt, ts);

        _baseAsset.safeTransfer(receiver, assets);
    }

    /// @notice Transfer out non-tracked tokens
    function recover(
        address[] calldata tokens,
        uint256[] calldata amounts,
        address[] calldata destinations
    ) external virtual override hasRole(Roles.TOKEN_RECOVERY_ROLE) {
        AutoPool4626.recover(tokens, amounts, destinations);
    }

    /// @inheritdoc ILMPVault
    function shutdown(VaultShutdownStatus reason) external hasRole(Roles.AUTO_POOL_ADMIN) {
        if (reason == VaultShutdownStatus.Active) {
            revert InvalidShutdownStatus(reason);
        }

        _shutdown = true;
        _shutdownStatus = reason;

        emit Shutdown(reason);
    }

    function _maxRedeem(address owner) internal view virtual returns (uint256 maxShares) {
        maxShares = paused() ? 0 : balanceOf(owner);
    }

    function _transferAndMint(uint256 assets, uint256 shares, address receiver) internal virtual {
        AutoPool4626.transferAndMint(
            _baseAsset, _assetBreakdown, _tokenData, _profitUnlockSettings, assets, shares, receiver
        );
    }

    function updateDebtReporting(uint256 numToProcess)
        external
        nonReentrant
        hasRole(Roles.LMP_UPDATE_DEBT_REPORTING_ROLE)
        trackNavOps
    {
        // Persist our change in idle and debt
        uint256 startingIdle = _assetBreakdown.totalIdle;
        uint256 startingDebt = _assetBreakdown.totalDebt;

        // slither-disable-next-line reentrancy-no-eth
        LMPDebt.IdleDebtUpdates memory result =
            LMPDebt._updateDebtReporting(_debtReportQueue, _destinations, _destinationInfo, numToProcess);

        uint256 newIdle = startingIdle + result.totalIdleIncrease;
        uint256 newDebt = startingDebt + result.totalDebtIncrease - result.totalDebtDecrease;

        _assetBreakdown.totalIdle = newIdle;
        _assetBreakdown.totalDebt = newDebt;
        _assetBreakdown.totalDebtMin =
            _assetBreakdown.totalDebtMin + result.totalMinDebtIncrease - result.totalMinDebtDecrease;
        _assetBreakdown.totalDebtMax =
            _assetBreakdown.totalDebtMax + result.totalMaxDebtIncrease - result.totalMaxDebtDecrease;

        uint256 newTotalSupply = _feeAndProfitHandling(newIdle + newDebt, startingIdle + startingDebt);

        lmpStrategy.navUpdate((newIdle + newDebt) * 10 ** decimals() / totalSupply());

        emit Nav(newIdle, newDebt, newTotalSupply);
    }

    function _feeAndProfitHandling(
        uint256 newTotalAssets,
        uint256 startingTotalAssets
    ) internal returns (uint256 newTotalSupply) {
        // Collect any fees and lock any profit if appropriate
        // idle+debt here represent the new totalAssets we just need them separate
        // for fee calcs
        AutoPoolFees.burnUnlockedShares(_profitUnlockSettings, _tokenData);

        uint256 startingTotalSupply = totalSupply();

        newTotalSupply = _collectFees(newTotalAssets, startingTotalSupply);

        newTotalSupply = AutoPoolFees.calculateProfitLocking(
            _profitUnlockSettings,
            _tokenData,
            newTotalSupply - startingTotalSupply, // new feeShares
            newTotalAssets,
            startingTotalAssets,
            newTotalSupply,
            balanceOfActual(address(this))
        );
    }

    function _collectFees(uint256 currentTotalAssets, uint256 currentTotalSupply) internal virtual returns (uint256) {
        return AutoPoolFees.collectFees(currentTotalAssets, currentTotalSupply, _feeSettings, _tokenData);
    }

    function getDestinations() public view override(ILMPVault, IStrategy) returns (address[] memory) {
        return _destinations.values();
    }

    function getWithdrawalQueue() public view returns (address[] memory) {
        return _withdrawalQueue.getList();
    }

    function getDebtReportingQueue() public view returns (address[] memory) {
        return _debtReportQueue.getList();
    }

    /// @inheritdoc ILMPVault
    function isDestinationRegistered(address destination) external view returns (bool) {
        return _destinations.contains(destination);
    }

    function addDestinations(address[] calldata destinations) public hasRole(Roles.DESTINATION_VAULTS_UPDATER) {
        LMPDestinations.addDestinations(_removalQueue, _destinations, destinations, _systemRegistry);
    }

    function removeDestinations(address[] calldata destinations) public hasRole(Roles.DESTINATION_VAULTS_UPDATER) {
        LMPDestinations.removeDestinations(_removalQueue, _destinations, destinations);
    }

    function getRemovalQueue() public view override returns (address[] memory) {
        return _removalQueue.values();
    }

    function removeFromRemovalQueue(address vaultToRemove) public override hasRole(Roles.REBALANCER_ROLE) {
        LMPDestinations.removeFromRemovalQueue(_removalQueue, vaultToRemove);
    }

    /// @inheritdoc ILMPVault
    function getDestinationInfo(address destVault) external view returns (LMPDebt.DestinationInfo memory) {
        return _destinationInfo[destVault];
    }

    /// @inheritdoc IStrategy
    function flashRebalance(
        IERC3156FlashBorrower receiver,
        RebalanceParams memory rebalanceParams,
        bytes calldata data
    ) public whenNotPaused nonReentrant hasRole(Roles.SOLVER_ROLE) trackNavOps {
        LMPDebt.IdleDebtUpdates memory result = _processRebalance(receiver, rebalanceParams, data);

        uint256 idle = _assetBreakdown.totalIdle;
        uint256 debt = _assetBreakdown.totalDebt;
        uint256 startTotalAssets = idle + debt;

        idle = idle + result.totalIdleIncrease - result.totalIdleDecrease;
        debt = debt + result.totalDebtIncrease - result.totalDebtDecrease;

        _assetBreakdown.totalIdle = idle;
        _assetBreakdown.totalDebt = debt;
        _assetBreakdown.totalDebtMin =
            _assetBreakdown.totalDebtMin + result.totalMinDebtIncrease - result.totalMinDebtDecrease;
        _assetBreakdown.totalDebtMax =
            _assetBreakdown.totalDebtMax + result.totalMaxDebtIncrease - result.totalMaxDebtDecrease;

        uint256 newTotalSupply = _feeAndProfitHandling(idle + debt, startTotalAssets);

        // Ensure the destinations are in the queues they should be
        LMPDestinations._manageQueuesForDestination(
            rebalanceParams.destinationOut, false, _withdrawalQueue, _debtReportQueue
        );
        LMPDestinations._manageQueuesForDestination(
            rebalanceParams.destinationIn, true, _withdrawalQueue, _debtReportQueue
        );

        // Signal to the strategy that everything went well
        // and it can gather its final state/stats
        lmpStrategy.rebalanceSuccessfullyExecuted(rebalanceParams);

        lmpStrategy.navUpdate((idle + debt) * 10 ** decimals() / totalSupply());

        emit Nav(idle, debt, newTotalSupply);
    }

    function _processRebalance(
        IERC3156FlashBorrower receiver,
        RebalanceParams memory rebalanceParams,
        bytes calldata data
    ) internal virtual returns (LMPDebt.IdleDebtUpdates memory result) {
        // make sure there's something to do
        if (rebalanceParams.amountIn == 0 && rebalanceParams.amountOut == 0) {
            revert Errors.InvalidParams();
        }

        if (rebalanceParams.destinationIn == rebalanceParams.destinationOut) {
            revert RebalanceDestinationsMatch(rebalanceParams.destinationOut);
        }

        // Get out destination summary stats
        IStrategy.SummaryStats memory outSummary = lmpStrategy.getRebalanceOutSummaryStats(rebalanceParams);
        result = LMPDebt.flashRebalance(
            _destinationInfo[rebalanceParams.destinationOut],
            _destinationInfo[rebalanceParams.destinationIn],
            receiver,
            rebalanceParams,
            outSummary,
            lmpStrategy,
            LMPDebt.FlashRebalanceParams({
                totalIdle: _assetBreakdown.totalIdle,
                totalDebt: _assetBreakdown.totalDebt,
                baseAsset: _baseAsset,
                shutdown: _shutdown
            }),
            data
        );
    }

    /// @inheritdoc ILMPVault
    function isDestinationQueuedForRemoval(address dest) external view returns (bool) {
        return _removalQueue.contains(dest);
    }

    function oldestDebtReporting() public view returns (uint256) {
        address destVault = _debtReportQueue.peekHead();
        return _destinationInfo[destVault].lastReport;
    }

    function _ensureAllowedUsers(address receiver) internal view {
        if (_checkUsers && (!allowedUsers[msg.sender] || !allowedUsers[receiver])) {
            revert InvalidUser();
        }
    }

    function _snapStartNav(TotalAssetPurpose purpose)
        private
        view
        returns (uint256 oldNav, uint256 startingTotalSupply)
    {
        startingTotalSupply = totalSupply();
        // slither-disable-next-line incorrect-equality
        if (startingTotalSupply == 0) {
            return (0, 0);
        }
        oldNav = (totalAssets(purpose) * FEE_DIVISOR) / startingTotalSupply;
    }

    /// @notice Vault nav/share shouldn't decrease on withdraw/redeem within rounding tolerance
    /// @dev No check when no shares
    function _ensureNoNavPerShareDecrease(
        uint256 oldNav,
        uint256 startingTotalSupply,
        TotalAssetPurpose purpose
    ) internal view virtual {
        uint256 ts = totalSupply();
        // slither-disable-next-line incorrect-equality
        if (ts == 0 || startingTotalSupply == 0) {
            return;
        }
        uint256 newNav = (totalAssets(purpose) * FEE_DIVISOR) / ts;
        if (newNav < oldNav) {
            revert NavDecreased(oldNav, newNav);
        }
    }
}
