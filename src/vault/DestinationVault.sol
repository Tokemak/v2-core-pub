// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

import { Roles } from "src/libs/Roles.sol";
import { Errors } from "src/utils/Errors.sol";
import { LibAdapter } from "src/libs/LibAdapter.sol";
import { SecurityBase } from "src/security/SecurityBase.sol";
import { Math } from "openzeppelin-contracts/utils/math/Math.sol";
import { ERC20 } from "openzeppelin-contracts/token/ERC20/ERC20.sol";
import { ISystemRegistry } from "src/interfaces/ISystemRegistry.sol";
import { ISwapRouter } from "src/interfaces/swapper/ISwapRouter.sol";
import { IMainRewarder } from "src/interfaces/rewarders/IMainRewarder.sol";
import { IDestinationVault } from "src/interfaces/vault/IDestinationVault.sol";
import { SafeERC20 } from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";
import { Initializable } from "openzeppelin-contracts/proxy/utils/Initializable.sol";
import { EnumerableSet } from "openzeppelin-contracts/utils/structs/EnumerableSet.sol";
import { IERC20Metadata as IERC20 } from "openzeppelin-contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { IDexLSTStats } from "src/interfaces/stats/IDexLSTStats.sol";
import { IncentiveCalculatorBase } from "src/stats/calculators/base/IncentiveCalculatorBase.sol";

abstract contract DestinationVault is SecurityBase, ERC20, Initializable, IDestinationVault {
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.AddressSet;

    event Recovered(address[] tokens, uint256[] amounts, address[] destinations);
    event UnderlyerRecovered(address destination, uint256 amount);
    event UnderlyingWithdraw(uint256 amount, address owner, address to);
    event BaseAssetWithdraw(uint256 amount, address owner, address to);
    event UnderlyingDeposited(uint256 amount, address sender);
    event Shutdown(VaultShutdownStatus reason);

    error ArrayLengthMismatch();
    error PullingNonTrackedToken(address token);
    error RecoveringTrackedToken(address token);
    error RecoveringMoreThanAvailable(address token, uint256 amount, uint256 availableAmount);
    error NothingToRecover();
    error DuplicateToken(address token);
    error VaultShutdown();
    error InvalidIncentiveCalculator();

    ISystemRegistry internal immutable _systemRegistry;

    /* ******************************** */
    /* State Variables                  */
    /* ******************************** */

    string internal _name;
    string internal _symbol;
    uint8 internal _underlyingDecimals;

    address internal _baseAsset;
    address internal _underlying;
    // slither-disable-next-line similar-names
    address internal _incentiveCalculator;

    IMainRewarder internal _rewarder;

    EnumerableSet.AddressSet internal _trackedTokens;

    /// @dev whether or not the vault has been shutdown
    bool internal _shutdown;

    /// @dev The reason for shutdown (or `Active` if not shutdown)
    VaultShutdownStatus internal _shutdownStatus;

    constructor(ISystemRegistry sysRegistry) SecurityBase(address(sysRegistry.accessController())) ERC20("", "") {
        _systemRegistry = sysRegistry;
    }

    modifier onlyLMPVault() {
        if (!_systemRegistry.lmpVaultRegistry().isVault(msg.sender)) {
            revert Errors.AccessDenied();
        }
        _;
    }

    modifier notShutdown() {
        if (_shutdown) {
            revert VaultShutdown();
        }
        _;
    }

    function initialize(
        IERC20 baseAsset_,
        IERC20 underlyer_,
        IMainRewarder rewarder_,
        address incentiveCalculator_,
        address[] memory additionalTrackedTokens_,
        bytes memory
    ) public virtual initializer {
        Errors.verifyNotZero(address(baseAsset_), "baseAsset_");
        Errors.verifyNotZero(address(underlyer_), "underlyer_");
        Errors.verifyNotZero(address(rewarder_), "rewarder_");
        Errors.verifyNotZero(address(incentiveCalculator_), "incentiveCalculator_");

        _name = string.concat("Tokemak-", baseAsset_.name(), "-", underlyer_.name());
        _symbol = string.concat("toke-", baseAsset_.symbol(), "-", underlyer_.symbol());
        _underlyingDecimals = underlyer_.decimals();

        if (IncentiveCalculatorBase(incentiveCalculator_).resolveLpToken() != address(underlyer_)) {
            revert InvalidIncentiveCalculator();
        }

        _baseAsset = address(baseAsset_);
        _underlying = address(underlyer_);
        _rewarder = rewarder_;
        _incentiveCalculator = incentiveCalculator_;

        // Setup the tracked tokens
        _addTrackedToken(address(baseAsset_));
        _addTrackedToken(address(underlyer_));
        uint256 attLen = additionalTrackedTokens_.length;
        for (uint256 i = 0; i < attLen; ++i) {
            _addTrackedToken(additionalTrackedTokens_[i]);
        }
    }

    /// @inheritdoc ERC20
    function name() public view virtual override(ERC20, IERC20) returns (string memory) {
        return _name;
    }

    /// @inheritdoc ERC20
    function symbol() public view virtual override(ERC20, IERC20) returns (string memory) {
        return _symbol;
    }

    /// @inheritdoc IDestinationVault
    function baseAsset() external view virtual override returns (address) {
        return _baseAsset;
    }

    /// @inheritdoc IDestinationVault
    function underlying() external view virtual override returns (address) {
        return _underlying;
    }

    /// @inheritdoc IDestinationVault
    function balanceOfUnderlyingDebt() public view virtual override returns (uint256) {
        return internalDebtBalance() + externalDebtBalance();
    }

    /// @inheritdoc IDestinationVault
    function internalDebtBalance() public view virtual override returns (uint256);

    /// @inheritdoc IDestinationVault
    function externalDebtBalance() public view virtual override returns (uint256);

    /// @inheritdoc IDestinationVault
    function internalQueriedBalance() public view virtual override returns (uint256) {
        return IERC20(_underlying).balanceOf(address(this));
    }

    /// @inheritdoc IDestinationVault
    function externalQueriedBalance() public view virtual override returns (uint256);

    /// @inheritdoc IDestinationVault
    function rewarder() external view virtual override returns (address) {
        return address(_rewarder);
    }

    /// @inheritdoc ERC20
    function decimals() public view virtual override(ERC20, IERC20) returns (uint8) {
        return _underlyingDecimals;
    }

    /// @inheritdoc IDestinationVault
    function debtValue() public virtual override returns (uint256 value) {
        value = _debtValue(balanceOfUnderlyingDebt());
    }

    /// @inheritdoc IDestinationVault
    function debtValue(uint256 shares) external virtual returns (uint256 value) {
        value = _debtValue(shares);
    }

    /// @inheritdoc IDestinationVault
    function exchangeName() external view virtual override returns (string memory);

    /// @inheritdoc IDestinationVault
    function underlyingTokens() external view virtual override returns (address[] memory);

    /// @inheritdoc IDestinationVault
    function collectRewards()
        external
        virtual
        override
        hasRole(Roles.LIQUIDATOR_ROLE)
        returns (uint256[] memory amounts, address[] memory tokens)
    {
        (amounts, tokens) = _collectRewards();
    }

    /// @notice Collects any earned rewards from staking, incentives, etc. Transfers to sender
    /// @return amounts amount of rewards claimed for each token
    /// @return tokens tokens claimed
    function _collectRewards() internal virtual returns (uint256[] memory amounts, address[] memory tokens);

    /// @inheritdoc IDestinationVault
    function shutdown(VaultShutdownStatus reason) external onlyOwner {
        if (reason == VaultShutdownStatus.Active) {
            revert InvalidShutdownStatus(reason);
        }

        _shutdown = true;
        _shutdownStatus = reason;

        emit Shutdown(reason);
    }

    /// @inheritdoc IDestinationVault
    function isShutdown() external view returns (bool) {
        return _shutdown;
    }

    /// @inheritdoc IDestinationVault
    function shutdownStatus() external view returns (VaultShutdownStatus) {
        return _shutdownStatus;
    }

    function trackedTokens() public view virtual returns (address[] memory trackedTokensArr) {
        uint256 arLen = _trackedTokens.length();
        trackedTokensArr = new address[](arLen);
        for (uint256 i = 0; i < arLen; ++i) {
            trackedTokensArr[i] = _trackedTokens.at(i);
        }
    }

    /// @notice Checks if given token is tracked by Vault
    /// @param token Address to verify
    /// @return bool True if token is within Vault's tracked assets
    function isTrackedToken(address token) public view virtual returns (bool) {
        return _trackedTokens.contains(token);
    }

    /// @inheritdoc IDestinationVault
    function depositUnderlying(uint256 amount) external onlyLMPVault notShutdown returns (uint256 shares) {
        Errors.verifyNotZero(amount, "amount");

        emit UnderlyingDeposited(amount, msg.sender);

        IERC20(_underlying).safeTransferFrom(msg.sender, address(this), amount);
        _mint(msg.sender, amount);

        _onDeposit(amount);

        shares = amount;
    }

    /// @inheritdoc IDestinationVault
    function withdrawUnderlying(uint256 shares, address to) external onlyLMPVault returns (uint256 amount) {
        Errors.verifyNotZero(shares, "shares");
        Errors.verifyNotZero(to, "to");

        amount = shares;

        emit UnderlyingWithdraw(amount, msg.sender, to);

        // Does a balance check, will revert if trying to burn too much
        _burn(msg.sender, shares);

        _ensureLocalUnderlyingBalance(amount);

        IERC20(_underlying).safeTransfer(to, amount);
    }

    /// @notice Ensure that we have the specified balance of the underlyer in the vault itself
    /// @param amount amount of token
    function _ensureLocalUnderlyingBalance(uint256 amount) internal virtual;

    /// @notice Callback during a deposit after the sender has been minted shares (if applicable)
    /// @dev Should be used for staking tokens into protocols, etc
    /// @param amount underlying tokens received
    function _onDeposit(uint256 amount) internal virtual;

    /// @inheritdoc IDestinationVault
    function withdrawBaseAsset(uint256 shares, address to) external returns (uint256 amount) {
        return _withdrawBaseAsset(msg.sender, shares, to);
    }

    /// @inheritdoc IDestinationVault
    //slither-disable-start assembly
    function estimateWithdrawBaseAsset(uint256 shares, address to, address account) public returns (uint256) {
        // Check if the function is being called from an external source and not recursively.
        if (msg.sender != address(this)) {
            // If `account` is not the zero address during an external call, there's a logic flaw.
            // External calls to this function must always provide `account` as the zero address.
            // Only during the recursive call will the `account` be provided.
            if (account != address(0)) {
                revert LogicDefect();
            }

            // Perform a recursive call to this function. The intention is to reach the "else" block.
            // solhint-disable avoid-low-level-calls
            // slither-disable-next-line missing-zero-check,low-level-calls
            (bool success, bytes memory returnData) = address(this).call(
                abi.encodeWithSelector(this.estimateWithdrawBaseAsset.selector, shares, to, msg.sender)
            );
            // solhint-enable avoid-low-level-calls

            // If the recursive call is successful, it means an unintended code path was taken.
            if (success) {
                revert UnreachableError();
            }

            // Extract the error signature (first 4 bytes) from the revert reason.
            bytes4 errorSignature;
            // solhint-disable no-inline-assembly
            assembly {
                errorSignature := mload(add(returnData, 0x20))
            }

            bytes4 balanceAmountSig = bytes4(keccak256("BaseAmountReceived(uint256)"));

            // If the error matches the expected signature, extract the amount from the revert reason and return.
            if (errorSignature == balanceAmountSig) {
                // Extract subsequent 32 bytes for uint256
                uint256 amount;
                assembly {
                    amount := mload(add(returnData, 0x24))
                }
                return amount;
            } else {
                // If the error is not the expected one, forward the original revert reason.
                assembly {
                    revert(add(32, returnData), mload(returnData))
                }
            }
            // solhint-enable no-inline-assembly
        }
        // This branch is taken during the recursive call.
        else {
            // Perform the actual withdrawal logic to compute the amount. This will be reverted to simulate the action.
            uint256 amount = _withdrawBaseAsset(account, shares, to);

            // Revert with the computed amount as an error.
            revert BaseAmountReceived(amount);
        }
    }
    //slither-disable-end assembly

    /// @notice Burn the specified amount of underlyer for the constituent tokens
    /// @dev May return one or multiple assets. Be as efficient as you can here.
    /// @param underlyerAmount amount of underlyer to burn
    /// @return tokens the tokens to swap for base asset
    /// @return amounts the amounts we have to swap
    function _burnUnderlyer(uint256 underlyerAmount)
        internal
        virtual
        returns (address[] memory tokens, uint256[] memory amounts);

    function recover(
        address[] calldata tokens,
        uint256[] calldata amounts,
        address[] calldata destinations
    ) external override hasRole(Roles.TOKEN_RECOVERY_ROLE) {
        uint256 length = tokens.length;
        if (length == 0 || length != amounts.length || length != destinations.length) {
            revert ArrayLengthMismatch();
        }
        emit Recovered(tokens, amounts, destinations);

        for (uint256 i = 0; i < tokens.length; ++i) {
            IERC20 token = IERC20(tokens[i]);

            // Check if it's a really non-tracked token
            if (isTrackedToken(tokens[i])) revert RecoveringTrackedToken(tokens[i]);

            uint256 tokenBalance = token.balanceOf(address(this));
            if (tokenBalance < amounts[i]) revert RecoveringMoreThanAvailable(tokens[i], amounts[i], tokenBalance);

            token.safeTransfer(destinations[i], amounts[i]);
        }
    }

    /// @inheritdoc IDestinationVault
    function getValidatedSpotPrice() external pure returns (uint256 price) {
        // TODO: Implement
        // Use getPool() and underlyer() and rootPriceOracle.getRangePriceLP()
        // Revert if !isSpotSafe
        // See: https://github.com/Tokemak/v2-core/issues/371
        price = 1e18;
    }

    /// @inheritdoc IDestinationVault
    function recoverUnderlying(address destination) external override hasRole(Roles.TOKEN_RECOVERY_ROLE) {
        Errors.verifyNotZero(destination, "destination");

        // TODO: Is there a situation where we would expect debt on the vault to be > queried balance on the vault?
        uint256 externalAmount = externalQueriedBalance() - externalDebtBalance();
        uint256 totalAmount = externalAmount + internalQueriedBalance() - internalDebtBalance();
        if (totalAmount > 0) {
            if (externalAmount > 0) {
                _ensureLocalUnderlyingBalance(externalAmount);
            }
            emit UnderlyerRecovered(destination, totalAmount);
            IERC20(_underlying).safeTransfer(destination, totalAmount);
        } else {
            revert NothingToRecover();
        }
    }

    function _addTrackedToken(address token) internal {
        //slither-disable-next-line unused-return
        _trackedTokens.add(token);
    }

    function _debtValue(uint256 shares) private returns (uint256 value) {
        //slither-disable-next-line incorrect-equality
        if (shares == 0) {
            return 0;
        }

        uint256 price = _systemRegistry.rootPriceOracle().getPriceInEth(_underlying);

        // At the moment we are only supporting WETH baseAsset
        // We know its 1:1 to ETH so we'll just return the current value
        return (price * shares) / (10 ** _underlyingDecimals);
    }

    function _beforeTokenTransfer(address from, address to, uint256 amount) internal virtual override {
        if (from == to) {
            return;
        }

        if (from != address(0)) {
            _rewarder.withdraw(from, amount, true);
        }
    }

    function _afterTokenTransfer(address from, address to, uint256 amount) internal virtual override {
        if (from == to) {
            return;
        }

        if (to != address(0)) {
            _rewarder.stake(to, amount);
        }
    }

    function _withdrawBaseAsset(address account, uint256 shares, address to) internal returns (uint256 amount) {
        Errors.verifyNotZero(shares, "shares");

        emit BaseAssetWithdraw(shares, account, to);

        // Does a balance check, will revert if trying to burn too much
        _burn(account, shares);

        // Accounts for shares that may be staked
        _ensureLocalUnderlyingBalance(shares);

        (address[] memory tokens, uint256[] memory amounts) = _burnUnderlyer(shares);

        uint256 nTokens = tokens.length;
        Errors.verifyArrayLengths(nTokens, amounts.length, "token+amounts");

        // Swap what we receive if not already in base asset
        // This fn is only called during a users withdrawal. The user should be making this
        // call via the LMP Router, or through one of the other routes where
        // slippage is controlled for. 0 min amount is expected here.
        ISwapRouter swapRouter = _systemRegistry.swapRouter();
        for (uint256 i = 0; i < nTokens; ++i) {
            address token = tokens[i];

            if (token == _baseAsset) {
                amount += amounts[i];
            } else {
                if (amounts[i] > 0) {
                    LibAdapter._approve(IERC20(token), address(swapRouter), amounts[i]);
                    amount += swapRouter.swapForQuote(token, amounts[i], _baseAsset, 0);
                }
            }
        }

        if (amount > 0) {
            IERC20(_baseAsset).safeTransfer(to, amount);
        }
    }

    /// @inheritdoc IDestinationVault
    function getStats() external virtual returns (IDexLSTStats) {
        return IDexLSTStats(_incentiveCalculator);
    }

    /// @inheritdoc IDestinationVault
    function getMarketplaceRewards()
        external
        virtual
        returns (uint256[] memory rewardTokens, uint256[] memory rewardRates)
    {
        // TODO Implement
        return (new uint256[](0), new uint256[](0));
    }

    /// @inheritdoc IDestinationVault
    function getPool() external view virtual returns (address poolAddress);
}
