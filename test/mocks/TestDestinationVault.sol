// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

import { ISystemRegistry } from "src/interfaces/ISystemRegistry.sol";
import { DestinationVault } from "src/vault/DestinationVault.sol";
import { IERC20, ERC20 } from "openzeppelin-contracts/token/ERC20/ERC20.sol";
import { IERC20Metadata } from "openzeppelin-contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { IMainRewarder } from "src/interfaces/rewarders/IMainRewarder.sol";
import { EnumerableSet } from "openzeppelin-contracts/utils/structs/EnumerableSet.sol";

contract TestDestinationVault is DestinationVault {
    using EnumerableSet for EnumerableSet.AddressSet;

    uint256 private _debtVault;
    uint256 private _claimVested;
    uint256 private _reclaimDebtAmount;
    uint256 private _reclaimDebtLoss;

    constructor(
        ISystemRegistry systemRegistry,
        address rewarder,
        address token,
        address underlyer,
        address incentiveCalculator
    ) DestinationVault(systemRegistry) {
        initialize(
            IERC20Metadata(token),
            IERC20Metadata(underlyer),
            IMainRewarder(rewarder),
            incentiveCalculator,
            new address[](0),
            abi.encode("")
        );
    }

    function underlying() public view override returns (address) {
        // just return the test baseasset for now (ignore extra level of wrapping)
        return address(_baseAsset);
    }

    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }

    function debtValue() public view override returns (uint256 value) {
        return _debtVault;
    }

    function exchangeName() external pure override returns (string memory) {
        return "test";
    }

    function underlyingTokens() external view override returns (address[] memory tokens) {
        tokens = new address[](1);
        tokens[0] = _underlying;
    }

    function setDebtValue(uint256 val) public {
        _debtVault = val;
    }

    function setClaimVested(uint256 val) public {
        _claimVested = val;
    }

    function setReclaimDebtAmount(uint256 val) public {
        _reclaimDebtAmount = val;
    }

    function setReclaimDebtLoss(uint256 val) public {
        _reclaimDebtLoss = val;
    }

    function setDebt(uint256 val) public {
        //debt = val;
    }

    function _burnUnderlyer(uint256)
        internal
        virtual
        override
        returns (address[] memory tokens, uint256[] memory amounts)
    {
        tokens = new address[](1);
        tokens[0] = address(0);

        amounts = new uint256[](1);
        amounts[0] = 0;
    }

    function _ensureLocalUnderlyingBalance(uint256 amount) internal virtual override { }

    function _onDeposit(uint256 amount) internal virtual override { }

    function balanceOfUnderlyingDebt() public pure override returns (uint256) {
        return 0;
    }

    function _collectRewards() internal override returns (uint256[] memory amounts, address[] memory tokens) { }

    function reset() external { }

    function externalDebtBalance() public pure override returns (uint256) {
        return 0;
    }

    function internalDebtBalance() public pure override returns (uint256) {
        return 0;
    }

    function externalQueriedBalance() public pure override returns (uint256) {
        return 0;
    }

    function getPool() external pure override returns (address poolAddress) {
        return address(0);
    }
}
