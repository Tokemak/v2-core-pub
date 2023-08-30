// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

interface IPool {
    struct State {
        int32 activeTick;
        uint8 status;
        uint128 binCounter;
        uint64 protocolFeeRatio;
    }

    /// @dev Fee for swapping in pool.  In 18 decimals.
    function fee() external view returns (uint256);

    /// @dev Tick spacing of pool. 1.0001^tickSpacing is width of bin.
    function tickSpacing() external view returns (uint256);

    function getState() external view returns (State memory);

    function binPositions(int32 tick, uint256 kind) external view returns (uint128);
}
