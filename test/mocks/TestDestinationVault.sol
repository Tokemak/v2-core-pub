// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

import { ISystemRegistry } from "src/interfaces/ISystemRegistry.sol";
import { DestinationVault } from "src/vault/DestinationVault.sol";

import { IncentiveCalculatorBase } from "src/stats/calculators/base/IncentiveCalculatorBase.sol";

contract TestDestinationVault is DestinationVault {
    uint256 private _debtVault;
    uint256 private _claimVested;
    uint256 private _reclaimDebtAmount;
    uint256 private _reclaimDebtLoss;
    address private _pool;

    constructor(ISystemRegistry systemRegistry) DestinationVault(systemRegistry) { }

    /*//////////////////////////////////////////////////////////////
                            TEST HELPERS
    //////////////////////////////////////////////////////////////*/

    function setPool(address pool) public {
        _pool = pool;
    }

    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }

    function burn(address account, uint256 amount) public {
        _burn(account, amount);
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

    /*//////////////////////////////////////////////////////////////
                            OVERRIDE FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function underlying() public view override returns (address) {
        // just return the test baseasset for now (ignore extra level of wrapping)
        return address(_baseAsset);
    }

    function exchangeName() external pure override returns (string memory) {
        return "test";
    }

    function poolType() external pure override returns (string memory) {
        return "test";
    }

    function poolDealInEth() external pure override returns (bool) {
        return false;
    }

    function underlyingTokens() external view override returns (address[] memory tokens) {
        tokens = new address[](1);
        tokens[0] = _underlying;
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

    function getPool() public view override returns (address poolAddress) {
        return _pool;
    }

    function _validateCalculator(address incentiveCalculator) internal view override {
        address lp = IncentiveCalculatorBase(incentiveCalculator).lpToken();
        if (lp != _underlying) {
            revert InvalidIncentiveCalculator(lp, _underlying, "lp");
        }
    }
}
