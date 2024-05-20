// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

import { IStatsCalculator } from "src/interfaces/stats/IStatsCalculator.sol";

contract ChainlinkStatsUpkeepV3 {
    function checkUpkeep(bytes calldata checkData)
        external
        view
        returns (bool upkeepNeeded, bytes memory performData)
    {
        (address[] memory addrs) = abi.decode(checkData, (address[]));
        address[] memory found = new address[](addrs.length);
        uint256 count = 0;

        for (uint256 i = 0; i < addrs.length; i++) {
            IStatsCalculator calc = IStatsCalculator(addrs[i]);

            try calc.shouldSnapshot() returns (bool shouldSnapshot) {
                if (shouldSnapshot) {
                    ++count;
                    found[i] = address(addrs[i]);
                }
            } catch { }
        }

        address[] memory trimmed = new address[](count);
        uint256 ix = 0;
        for (uint256 i = 0; i < addrs.length; i++) {
            if (found[i] != address(0)) {
                trimmed[ix] = found[i];
                ix++;
            }
        }
        upkeepNeeded = count > 0;
        performData = abi.encode(trimmed);
    }

    function performUpkeep(bytes calldata performData) external {
        (address[] memory addrs) = abi.decode(performData, (address[]));
        for (uint256 i = 0; i < addrs.length; i++) {
            IStatsCalculator calc = IStatsCalculator(addrs[i]);
            calc.snapshot();
        }
    }
}
