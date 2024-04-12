// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { IChildChainStreamer } from "src/interfaces/external/beethoven/IChildChainStreamer.sol";

// solhint-disable func-name-mixedcase
// slither-disable-start naming-convention
interface IRewardsOnlyGauge {
    /// @notice The address of the reward token
    function reward_contract() external view returns (IChildChainStreamer);

    function claimable_reward(address _addr, address _token) external view returns (uint256);
}
// slither-disable-end naming-convention
