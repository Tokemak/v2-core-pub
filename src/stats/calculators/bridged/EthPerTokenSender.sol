// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

import { SystemComponent } from "src/SystemComponent.sol";
import { Roles } from "src/libs/Roles.sol";
import { IStatsCalculator } from "src/interfaces/stats/IStatsCalculator.sol";
import { ISystemRegistry } from "src/interfaces/ISystemRegistry.sol";
import { IMessageProxy } from "src/interfaces/messageProxy/IMessageProxy.sol";
import { Errors } from "src/utils/Errors.sol";
import { LSTCalculatorBase } from "src/stats/calculators/base/LSTCalculatorBase.sol";
import { EnumerableSet } from "openzeppelin-contracts/utils/structs/EnumerableSet.sol";
import { SecurityBase } from "src/security/SecurityBase.sol";
import { MessageTypes } from "src/libs/MessageTypes.sol";
import { SafeCast } from "openzeppelin-contracts/utils/math/SafeCast.sol";
import { IStatsCalculatorRegistry } from "src/interfaces/stats/IStatsCalculatorRegistry.sol";
import { IStatsCalculator } from "src/interfaces/stats/IStatsCalculator.sol";

/// @notice Sends the result of `calculateEthPerToken()` for each registered LST calculator to other chains
contract EthPerTokenSender is SystemComponent, SecurityBase {
    using EnumerableSet for EnumerableSet.AddressSet;

    /// =====================================================
    /// Internal Vars
    /// =====================================================

    /// @notice Calculators that are configured to send data
    /// @dev Exposed via getCalculators()
    EnumerableSet.AddressSet internal _calculators;

    /// =====================================================
    /// Public Vars
    /// =====================================================

    /// @notice Last sent value for a calculator
    /// @dev calculator -> ethPerToken
    mapping(address => uint256) public lastValue;

    /// =====================================================
    /// Events
    /// =====================================================

    event CalculatorsRegistered(bytes32[] calculators);
    event CalculatorsUnregistered(address[] calculators);

    /// =====================================================
    /// Errors
    /// =====================================================

    error InvalidCalculator(address calculator);

    /// =====================================================
    /// Functions - Constructor
    /// =====================================================

    constructor(ISystemRegistry _systemRegistry)
        SystemComponent(_systemRegistry)
        SecurityBase(address(_systemRegistry.accessController()))
    { }

    /// =====================================================
    /// Functions - External
    /// =====================================================

    /// @notice Get the latest ethPerToken for the specified calculators and send to other chains
    /// @dev Does not validate if the send is necessary. Use `shouldSend()` to filter first
    /// @param calculators Calculators to query
    function send(address[] memory calculators) external hasRole(Roles.STATS_LST_ETH_TOKEN_EXECUTOR) {
        uint256 len = calculators.length;
        Errors.verifyNotZero(len, "len");

        IMessageProxy messageProxy = systemRegistry.messageProxy();
        Errors.verifyNotZero(address(messageProxy), "messageProxy");

        for (uint256 i = 0; i < len;) {
            address calculator = calculators[i];
            if (!_calculators.contains(calculator)) {
                revert InvalidCalculator(calculator);
            }
            uint256 currentValue = LSTCalculatorBase(calculator).calculateEthPerToken();
            lastValue[calculator] = currentValue;
            address lst = LSTCalculatorBase(calculator).lstTokenAddress();

            bytes memory message = abi.encode(
                MessageTypes.LstBackingMessage({
                    token: lst,
                    ethPerToken: SafeCast.toUint208(currentValue),
                    timestamp: uint48(block.timestamp)
                })
            );

            // slither-disable-next-line reentrancy-benign
            messageProxy.sendMessage(MessageTypes.LST_BACKING_MESSAGE_TYPE, message);

            unchecked {
                ++i;
            }
        }
    }

    /// @notice Checks latest ethPerToken against last sent value to determine if a message should be sent
    /// @param skip Number of calculators to skip when iterating the list
    /// @param take Number of calculators to evaluate when iterating the list. Pass uint256.max for all
    /// @return data Address of calculators to send
    function shouldSend(uint256 skip, uint256 take) external view returns (address[] memory data) {
        take = _validateSkipTake(skip, take);

        address[] memory results = new address[](take);
        uint256 r = 0;
        for (uint256 i = 0; i < take; ++i) {
            address calculator = _calculators.at(skip + i);
            uint256 currentValue = LSTCalculatorBase(calculator).calculateEthPerToken();
            if (currentValue != lastValue[calculator]) {
                results[r] = calculator;
                ++r;
            }
        }

        data = new address[](r);
        for (uint256 i = 0; i < r; ++i) {
            data[i] = results[i];
        }
    }

    /// @notice Add calculators that should send their data to other chains
    /// @param calculators The apr id's of the calculators to add
    function registerCalculators(bytes32[] memory calculators) external hasRole(Roles.STATS_GENERAL_MANAGER) {
        uint256 len = calculators.length;
        Errors.verifyNotZero(len, "len");

        IStatsCalculatorRegistry calcRegistry = systemRegistry.statsCalculatorRegistry();

        for (uint256 i = 0; i < len;) {
            IStatsCalculator calculator = calcRegistry.getCalculator(calculators[i]);

            // If we passed in unnecessary data revert so we can figure out why
            if (!_calculators.add(address(calculator))) {
                revert Errors.AlreadyRegistered(address(calculator));
            }
            unchecked {
                ++i;
            }
        }

        emit CalculatorsRegistered(calculators);
    }

    /// @notice Removes calculators that have already been added
    /// @param calculators Addresses of the calculators to remove
    function unregisterCalculators(address[] memory calculators) external hasRole(Roles.STATS_GENERAL_MANAGER) {
        uint256 len = calculators.length;
        Errors.verifyNotZero(len, "len");

        for (uint256 i = 0; i < len;) {
            // If we passed in unnecessary data revert so we can figure out why
            if (!_calculators.remove(calculators[i])) {
                revert Errors.NotRegistered();
            }
            unchecked {
                ++i;
            }
        }

        emit CalculatorsUnregistered(calculators);
    }

    /// @notice Returns all currently registered calculators
    function getCalculators() external view returns (address[] memory data) {
        uint256 len = _calculators.length();
        data = new address[](len);
        for (uint256 i = 0; i < len; i++) {
            data[i] = _calculators.at(i);
        }
    }

    /// =====================================================
    /// Functions - Internal
    /// =====================================================

    /// @dev Sanitize skip and take parameters for the calculator list
    function _validateSkipTake(uint256 skip, uint256 take) internal view returns (uint256 takeRet) {
        uint256 len = _calculators.length();
        if (take == type(uint256).max) {
            take = len;
        }
        if (skip >= len) {
            revert Errors.InvalidParam("skip");
        }
        if (skip + take > len) {
            takeRet = len - skip;
        } else {
            takeRet = take;
        }
    }
}
