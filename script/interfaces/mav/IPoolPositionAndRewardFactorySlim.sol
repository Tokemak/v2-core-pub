// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.17;

import { IPool } from "script/interfaces/mav/IPool.sol";

interface IPoolPositionAndRewardFactorySlim {
    function createPoolPositionAndRewards(
        IPool pool,
        uint128[] calldata binIds,
        uint128[] calldata ratios,
        bool isStatic
    ) external returns (address);
}
