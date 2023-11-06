// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved
pragma solidity 0.8.17;

// solhint-disable func-name-mixedcase

import { MainRewarderBaseTest, IMainRewarder } from "test/rewarders/MainRewarderBase.t.sol";
import { DestinationVaultMainRewarder, MainRewarder, Roles } from "src/rewarders/DestinationVaultMainRewarder.sol";

contract DestinationVaultMainRewarderTest is MainRewarderBaseTest {
    function setUp() public virtual override {
        super.setUp();

        accessController.grantRole(Roles.DV_REWARD_MANAGER_ROLE, address(this));

        rewarder = MainRewarder(
            new DestinationVaultMainRewarder(systemRegistry,
            address(stakeTracker),
            address(rewardToken),
            newRewardRatio,
            durationInBlock,
            true)
        );
    }

    function test_RevertIf_ExtraRewardsNotAllowed() public {
        MainRewarder mainRewarder = MainRewarder(
            new DestinationVaultMainRewarder(systemRegistry,
            address(stakeTracker),
            address(rewardToken),
            newRewardRatio,
            durationInBlock,
            false)
        );

        vm.expectRevert(abi.encodeWithSelector(IMainRewarder.ExtraRewardsNotAllowed.selector));
        mainRewarder.addExtraReward(makeAddr("EXTRA_REWARD"));
    }
}
