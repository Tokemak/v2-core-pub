// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.

pragma solidity 0.8.17;

import { Errors } from "src/utils/Errors.sol";
import { IDestinationVault } from "src/interfaces/vault/IDestinationVault.sol";
import { EnumerableSet } from "openzeppelin-contracts/utils/structs/EnumerableSet.sol";
import { ISystemRegistry, IDestinationVaultRegistry } from "src/interfaces/ISystemRegistry.sol";

library LMPDestinations {
    using EnumerableSet for EnumerableSet.AddressSet;

    uint256 public constant MAX_DESTINATIONS = 50;

    error DestinationLimitExceeded();

    event DestinationVaultAdded(address destination);
    event DestinationVaultRemoved(address destination);
    event WithdrawalQueueSet(address[] destinations);
    event AddedToRemovalQueue(address destination);
    event RemovedFromRemovalQueue(address destination);

    function removeFromRemovalQueue(EnumerableSet.AddressSet storage removalQueue, address vaultToRemove) external {
        if (!removalQueue.remove(vaultToRemove)) {
            revert Errors.ItemNotFound();
        }

        emit RemovedFromRemovalQueue(vaultToRemove);
    }

    function setWithdrawalQueue(
        IDestinationVault[] storage withdrawalQueue,
        address[] calldata _destinations,
        ISystemRegistry systemRegistry
    ) external {
        IDestinationVaultRegistry destinationVaultRegistry = systemRegistry.destinationVaultRegistry();
        (uint256 oldLength, uint256 newLength) = (withdrawalQueue.length, _destinations.length);

        // run through new destinations list and propagate the values to our existing collection
        uint256 i;
        for (i = 0; i < newLength; ++i) {
            address destAddress = _destinations[i];
            Errors.verifyNotZero(destAddress, "destination");

            // check if destination vault is registered with the system
            if (!destinationVaultRegistry.isRegistered(destAddress)) {
                revert Errors.InvalidAddress(destAddress);
            }

            IDestinationVault destination = IDestinationVault(destAddress);

            // if we're still overwriting, just set the value
            if (i < oldLength) {
                // only write if values differ
                if (withdrawalQueue[i] != destination) {
                    withdrawalQueue[i] = destination;
                }
            } else {
                // if already past old bounds, append new values
                withdrawalQueue.push(destination);
            }
        }

        // if old list was larger than new list, pop the remaining values
        if (oldLength > newLength) {
            for (; i < oldLength; ++i) {
                // slither-disable-next-line costly-loop
                withdrawalQueue.pop();
            }
        }

        emit WithdrawalQueueSet(_destinations);
    }

    function removeDestinations(
        EnumerableSet.AddressSet storage removalQueue,
        EnumerableSet.AddressSet storage destinations,
        address[] calldata _destinations
    ) external {
        for (uint256 i = 0; i < _destinations.length; ++i) {
            address dAddress = _destinations[i];
            IDestinationVault destination = IDestinationVault(dAddress);

            // remove from main list (NOTE: done here so balance check below doesn't explode if address is invalid)
            if (!destinations.remove(dAddress)) {
                revert Errors.ItemNotFound();
            }

            if (destination.balanceOf(address(this)) > 0 && !removalQueue.contains(dAddress)) {
                // we still have funds in it! move it to removalQueue for rebalancer to handle it later
                // slither-disable-next-line unused-return
                removalQueue.add(dAddress);

                emit AddedToRemovalQueue(dAddress);
            }

            emit DestinationVaultRemoved(dAddress);
        }
    }

    function addDestinations(
        EnumerableSet.AddressSet storage removalQueue,
        EnumerableSet.AddressSet storage destinations,
        address[] calldata _destinations,
        ISystemRegistry systemRegistry
    ) external {
        IDestinationVaultRegistry destinationRegistry = systemRegistry.destinationVaultRegistry();

        uint256 numDestinations = _destinations.length;
        if (numDestinations == 0) revert Errors.InvalidParams();
        if (numDestinations + destinations.length() > MAX_DESTINATIONS) revert DestinationLimitExceeded();

        address dAddress;
        for (uint256 i = 0; i < numDestinations; ++i) {
            dAddress = _destinations[i];

            if (dAddress == address(0) || !destinationRegistry.isRegistered(dAddress)) {
                revert Errors.InvalidAddress(dAddress);
            }

            if (!destinations.add(dAddress)) {
                revert Errors.ItemExists();
            }

            // just in case it's in removal queue, take it out
            // slither-disable-next-line unused-return
            removalQueue.remove(dAddress);

            emit DestinationVaultAdded(dAddress);
        }
    }
}
