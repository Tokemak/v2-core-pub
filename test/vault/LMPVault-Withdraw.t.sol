// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity >=0.8.7;

// // solhint-disable func-name-mixedcase,max-states-count

// //     function test_effectiveHighMarkDoesntDecayBeforeSixty() public {
// //         uint256 currentBlock = 100 days;
// //         uint256 currentNav = 11_000;
// //         uint256 lastHighMarkTimestamp = 95 days;
// //         uint256 lastHighMark = 12_000;
// //         uint256 aumHighMark = 10e18;
// //         uint256 aumCurrent = 9e18;

// //         uint256 effectiveHigh = _lmpVault.calculateEffectiveNavPerShareHighMark(
// //             currentBlock, currentNav, lastHighMarkTimestamp, lastHighMark, aumHighMark, aumCurrent
// //         );

// //         assertEq(lastHighMark, effectiveHigh);
// //     }

// //     function test_effectiveHighMarkBecomesCurrentAfter600() public {
// //         uint256 currentBlock = 1001 days;
// //         uint256 currentNav = 11_000;
// //         uint256 lastHighMarkTimestamp = 400 days;
// //         uint256 lastHighMark = 12_000;
// //         uint256 aumHighMark = 10e18;
// //         uint256 aumCurrent = 9e18;

// //         uint256 effectiveHigh = _lmpVault.calculateEffectiveNavPerShareHighMark(
// //             currentBlock, currentNav, lastHighMarkTimestamp, lastHighMark, aumHighMark, aumCurrent
// //         );

// //         assertEq(currentNav, effectiveHigh);
// //     }

// //     function test_effectiveHighMarkDecaysPastDay25() public {
// //         uint256 currentBlock = 1000 days;
// //         uint256 currentNav = 11_000;
// //         uint256 lastHighMarkTimestamp = 900 days;
// //         uint256 lastHighMark = 12_000;
// //         uint256 aumHighMark = 10e18;
// //         uint256 aumCurrent = 9e18;

// //         uint256 effectiveHigh = _lmpVault.calculateEffectiveNavPerShareHighMark(
// //             currentBlock, currentNav, lastHighMarkTimestamp, lastHighMark, aumHighMark, aumCurrent
// //         );

// //         assertEq(11_067, effectiveHigh);
// //     }

// //     function test_effectiveHighMarkDecaysDayOne() public {
// //         uint256 currentBlock = 1000 days;
// //         uint256 currentNav = 11_000;
// //         uint256 lastHighMarkTimestamp = 939 days;
// //         uint256 lastHighMark = 12_000;
// //         uint256 aumHighMark = 10e18;
// //         uint256 aumCurrent = 9e18;

// //         uint256 effectiveHigh = _lmpVault.calculateEffectiveNavPerShareHighMark(
// //             currentBlock, currentNav, lastHighMarkTimestamp, lastHighMark, aumHighMark, aumCurrent
// //         );

// //         assertEq(11_976, effectiveHigh);
// //     }

// //     function test_effectiveHighMarkDecaysMultiple25DayIterations() public {
// //         uint256 currentBlock = 1000 days;
// //         uint256 currentNav = 11_000;
// //         uint256 lastHighMarkTimestamp = 790 days;
// //         uint256 lastHighMark = 12_000;
// //         uint256 aumHighMark = 10e18;
// //         uint256 aumCurrent = 9e18;

// //         uint256 effectiveHigh = _lmpVault.calculateEffectiveNavPerShareHighMark(
// //             currentBlock, currentNav, lastHighMarkTimestamp, lastHighMark, aumHighMark, aumCurrent
// //         );

// //         assertEq(8875, effectiveHigh);
// //     }

// //     function test_effectiveHighMarkDecaysAt600() public {
// //         uint256 currentBlock = 1000 days;
// //         uint256 currentNav = 11_000;
// //         uint256 lastHighMarkTimestamp = 400 days;
// //         uint256 lastHighMark = 12_000;
// //         uint256 aumHighMark = 10e18;
// //         uint256 aumCurrent = 9e18;

// //         uint256 effectiveHigh = _lmpVault.calculateEffectiveNavPerShareHighMark(
// //             currentBlock, currentNav, lastHighMarkTimestamp, lastHighMark, aumHighMark, aumCurrent
// //         );

// //         assertEq(4037, effectiveHigh);
// //     }

// //     function test_effectiveHighMarkDecaysEqualAums() public {
// //         uint256 currentBlock = 1000 days;
// //         uint256 currentNav = 11_000;
// //         uint256 lastHighMarkTimestamp = 900 days;
// //         uint256 lastHighMark = 12_000;
// //         uint256 aumHighMark = 10e18;
// //         uint256 aumCurrent = aumHighMark;

// //         uint256 effectiveHigh = _lmpVault.calculateEffectiveNavPerShareHighMark(
// //             currentBlock, currentNav, lastHighMarkTimestamp, lastHighMark, aumHighMark, aumCurrent
// //         );

// //         assertEq(11_520, effectiveHigh);
// //     }

// //     function test_effectiveHighMarkDecaysCurrentAumLowerAumHighMark() public {
// //         uint256 currentBlock = 1000 days;
// //         uint256 currentNav = 11_000;
// //         uint256 lastHighMarkTimestamp = 900 days;
// //         uint256 lastHighMark = 12_000;
// //         uint256 aumHighMark = 9e18;
// //         uint256 aumCurrent = 10e18;

// //         uint256 effectiveHigh = _lmpVault.calculateEffectiveNavPerShareHighMark(
// //             currentBlock, currentNav, lastHighMarkTimestamp, lastHighMark, aumHighMark, aumCurrent
// //         );

// //         assertEq(11_067, effectiveHigh);
// //     }

// //     function test_effectiveHighMarkDecaysLastHighMarkZero() public {
// //         uint256 currentBlock = 1000 days;
// //         uint256 currentNav = 11_000;
// //         uint256 lastHighMarkTimestamp = 900 days;
// //         uint256 lastHighMark = 0;
// //         uint256 aumHighMark = 9e18;
// //         uint256 aumCurrent = 10e18;

// //         uint256 effectiveHigh = _lmpVault.calculateEffectiveNavPerShareHighMark(
// //             currentBlock, currentNav, lastHighMarkTimestamp, lastHighMark, aumHighMark, aumCurrent
// //         );

// //         assertEq(0, effectiveHigh);
// //     }

// //     function test_effectiveHighMarkDecaysZeroAumCurrent() public {
// //         uint256 currentBlock = 1000 days;
// //         uint256 currentNav = 11_000;
// //         uint256 lastHighMarkTimestamp = 900 days;
// //         uint256 lastHighMark = 12_000;
// //         uint256 aumHighMark = 9e18;
// //         uint256 aumCurrent = 0;

// //         uint256 effectiveHigh = _lmpVault.calculateEffectiveNavPerShareHighMark(
// //             currentBlock, currentNav, lastHighMarkTimestamp, lastHighMark, aumHighMark, aumCurrent
// //         );

// //         assertEq(8013, effectiveHigh);
// //     }

// //     function test_effectiveHighMarkDecaysZeroAumHighMark() public {
// //         uint256 currentBlock = 1000 days;
// //         uint256 currentNav = 11_000;
// //         uint256 lastHighMarkTimestamp = 900 days;
// //         uint256 lastHighMark = 12_000;
// //         uint256 aumHighMark = 0;
// //         uint256 aumCurrent = 10e18;

// //         uint256 effectiveHigh = _lmpVault.calculateEffectiveNavPerShareHighMark(
// //             currentBlock, currentNav, lastHighMarkTimestamp, lastHighMark, aumHighMark, aumCurrent
// //         );

// //         assertEq(8013, effectiveHigh);
// //     }

// //     function test_effectiveHighMarkDecaysLowAumHighMark() public {
// //         uint256 currentBlock = 1000 days;
// //         uint256 currentNav = 11_000;
// //         uint256 lastHighMarkTimestamp = 900 days;
// //         uint256 lastHighMark = 12_000;
// //         uint256 aumHighMark = 1;
// //         uint256 aumCurrent = 10e18;

// //         uint256 effectiveHigh = _lmpVault.calculateEffectiveNavPerShareHighMark(
// //             currentBlock, currentNav, lastHighMarkTimestamp, lastHighMark, aumHighMark, aumCurrent
// //         );

// //         assertEq(8013, effectiveHigh);
// //     }

// //     function test_effectiveHighMarkDecaysLowAumCurrent() public {
// //         uint256 currentBlock = 1000 days;
// //         uint256 currentNav = 11_000;
// //         uint256 lastHighMarkTimestamp = 900 days;
// //         uint256 lastHighMark = 12_000;
// //         uint256 aumHighMark = 9e18;
// //         uint256 aumCurrent = 1;

// //         uint256 effectiveHigh = _lmpVault.calculateEffectiveNavPerShareHighMark(
// //             currentBlock, currentNav, lastHighMarkTimestamp, lastHighMark, aumHighMark, aumCurrent
// //         );

// //         assertEq(8013, effectiveHigh);
// //     }

// //     function test_effectiveHighMarkDecaysHighAumHighMark() public {
// //         uint256 currentBlock = 1000 days;
// //         uint256 currentNav = 11_000;
// //         uint256 lastHighMarkTimestamp = 900 days;
// //         uint256 lastHighMark = 12_000;
// //         uint256 aumHighMark = 500 * 9e18;
// //         uint256 aumCurrent = 10e18;

// //         uint256 effectiveHigh = _lmpVault.calculateEffectiveNavPerShareHighMark(
// //             currentBlock, currentNav, lastHighMarkTimestamp, lastHighMark, aumHighMark, aumCurrent
// //         );

// //         assertEq(7700, effectiveHigh);
// //     }

// //     function test_effectiveHighMarkDecaysHighAumCurrent() public {
// //         uint256 currentBlock = 1000 days;
// //         uint256 currentNav = 11_000;
// //         uint256 lastHighMarkTimestamp = 900 days;
// //         uint256 lastHighMark = 12_000;
// //         uint256 aumHighMark = 9e18;
// //         uint256 aumCurrent = 500 * 10e18;

// //         uint256 effectiveHigh = _lmpVault.calculateEffectiveNavPerShareHighMark(
// //             currentBlock, currentNav, lastHighMarkTimestamp, lastHighMark, aumHighMark, aumCurrent
// //         );

// //         assertEq(7700, effectiveHigh);
// //     }

// //     function test_updateDebtReporting_OnlyCallableByRole() external {
// //         assertEq(_accessController.hasRole(Roles.LMP_UPDATE_DEBT_REPORTING_ROLE, address(this)), false);

// //         address[] memory fakeDestinations = new address[](1);
// //         fakeDestinations[0] = vm.addr(1);

// //         vm.expectRevert(Errors.AccessDenied.selector);
// //         _lmpVault.updateDebtReporting(fakeDestinations);
// //     }

// //     function test_updateDebtReporting_FeesAreTakenWithoutDoubleDipping() public {
// //         _accessController.grantRole(Roles.SOLVER_ROLE, address(this));
// //         _accessController.grantRole(Roles.LMP_FEE_SETTER_ROLE, address(this));
// //         _accessController.grantRole(Roles.LMP_UPDATE_DEBT_REPORTING_ROLE, address(this));

// //         // User is going to deposit 1000 asset
// //         _asset.mint(address(this), 1000);
// //         _asset.approve(address(_lmpVault), 1000);
// //         _lmpVault.deposit(1000, address(this));

// //         // At time of writing LMPVault always returned true for verifyRebalance
// //         // Rebalance 1000 baseAsset for 500 underlyerOne+destVaultOne (price is 2:1)
// //         _underlyerOne.mint(address(this), 250);
// //         _underlyerOne.approve(address(_lmpVault), 250);
// //         _lmpVault.rebalance(
// //             address(_destVaultOne),
// //             address(_underlyerOne), // tokenIn
// //             250,
// //             address(0), // destinationOut, none when sending out baseAsset
// //             address(_asset), // baseAsset, tokenOut
// //             500
// //         );

// //         // Setting a sink but not an actual fee yet
// //         address feeSink = vm.addr(555);
// //         _lmpVault.setFeeSink(feeSink);

// //         // Dropped 1000 asset in and just did a rebalance. There's no slippage or anything
// //         // atm so assets are just moved around, should still be reporting 1000 available
// //         uint256 shareBal = _lmpVault.balanceOf(address(this));
// //         assertEq(_lmpVault.totalDebt(), 500);
// //         assertEq(_lmpVault.totalIdle(), 500);
// //         assertEq(_lmpVault.convertToAssets(shareBal), 1000);

// //         // Underlyer1 is currently worth 2 ETH a piece
// //         // Lets update the price to 1.5 ETH and trigger a debt reporting
// //         // and verify our totalDebt and asset conversions match the drop in price
// //         _mockRootPrice(address(_underlyerOne), 15e17);
// //         _lmpVault.updateDebtReporting(_destinations);

// //         // No change in idle
// //         assertEq(_lmpVault.totalIdle(), 500);
// //         // Debt value per share went from 2 to 1.5 so a 25% drop
// //         // Was 500 before
// //         assertEq(_lmpVault.totalDebt(), 375);
// //         // So overall I can get 500 + 375 back
// //         shareBal = _lmpVault.balanceOf(address(this));
// //         assertEq(_lmpVault.convertToAssets(shareBal), 875);

// //         // Lets update the price back 2 ETH. This should put the numbers back
// //         // to where they were, idle+debt+assets. We shouldn't see any fee's
// //         // taken though as this is just recovering back to where our deployment was
// //         // We're just even now
// //         _mockRootPrice(address(_underlyerOne), 2 ether);

// //         vm.expectEmit(true, true, true, true);
// //         emit FeeCollected(0, feeSink, 0, 0, 500, 500);
// //         _lmpVault.updateDebtReporting(_destinations);
// //         shareBal = _lmpVault.balanceOf(address(this));
// //         assertEq(_lmpVault.totalDebt(), 500);
// //         assertEq(_lmpVault.totalIdle(), 500);
// //         assertEq(_lmpVault.convertToAssets(shareBal), 1000);

// //         // Next price update. It'll go from 2 to 2.5 ether. 25%,
// //         // or a 125 ETH increase. There's technically a profit here but we
// //         // haven't set a fee yet so that should still be 0
// //         _mockRootPrice(address(_underlyerOne), 25e17);
// //         vm.expectEmit(true, true, true, true);
// //         emit FeeCollected(0, feeSink, 0, 1_250_000, 500, 625);
// //         _lmpVault.updateDebtReporting(_destinations);
// //         shareBal = _lmpVault.balanceOf(address(this));
// //         assertEq(_lmpVault.totalDebt(), 625);
// //         assertEq(_lmpVault.totalIdle(), 500);
// //         assertEq(_lmpVault.convertToAssets(shareBal), 1125);

// //         // Lets set a fee and and force another increase. We should only
// //         // take fee's on the increase from the original deployment
// //         // from this point forward. No back taking fee's
// //         _lmpVault.setStreamingFeeBps(2000); // 20%

// //         // From 2.5 to 3 or a 20% increase
// //         // Debt was at 625, so we have 125 profit
// //         // 1250 nav @ 1000 shares,
// //         // 25*1000/1250, 20 (+1 taking into account the new totalSupply after mint) new shares to us
// //         _mockRootPrice(address(_underlyerOne), 3e18);
// //         vm.expectEmit(true, true, true, true);
// //         emit FeeCollected(25, feeSink, 21, 1_250_000, 500, 750);
// //         _lmpVault.updateDebtReporting(_destinations);
// //         shareBal = _lmpVault.balanceOf(address(this));
// //         // Previously 625 but with 125 increase
// //         assertEq(_lmpVault.totalDebt(), 750);
// //         // Fees come from extra minted shares, idle shouldn't change
// //         assertEq(_lmpVault.totalIdle(), 500);
// //         // 20+1 Extra shares were minted to cover the fees. That's 1020+1 shares now
// //         // for 1224 assets. 1000*1250/1021
// //         assertEq(_lmpVault.convertToAssets(shareBal), 1224);

// //         // Debt report again with no changes, make sure we don't double dip fee's
// //         vm.expectEmit(true, true, true, true);
// //         emit FeeCollected(0, feeSink, 0, 0, 500, 750);
// //         _lmpVault.updateDebtReporting(_destinations);

// //         // Test the double dip again but with a decrease and
// //         // then increase price back to where we were

// //         // Decrease in price here so expect no fees
// //         _mockRootPrice(address(_underlyerOne), 2e18);
// //         vm.expectEmit(true, true, true, true);
// //         emit FeeCollected(0, feeSink, 0, 0, 500, 500);
// //         _lmpVault.updateDebtReporting(_destinations);
// //         //And back to 3, should still be 0 since we've been here before
// //         _mockRootPrice(address(_underlyerOne), 3e18);
// //         vm.expectEmit(true, true, true, true);
// //         emit FeeCollected(0, feeSink, 0, 0, 500, 750);
// //         _lmpVault.updateDebtReporting(_destinations);

// //         // And finally an increase above our last high value where we should
// //         // grab more fee's. Debt was at 750 @3 ETH. Going from 3 to 4, worth
// //         // 1000 now. Our nav is 1500 with 1020 shares. Previous was 1250 @ 1000 shares.
// //         // So that's 1.25 nav/share -> 1.467 a change of 0.217710372. With totalSupply
// //         // at 1020 that's a profit of 222.5 (our fee shares we minted docked
// //         // that from the straight up 250 we'd expect).
// //         // Our 20% on that profit gives us 44.5. 45*1020/1500, 30.6 shares
// //         _mockRootPrice(address(_underlyerOne), 4e18);
// //         // vm.expectEmit(true, true, true, true);
// //         // emit FeeCollected(45, feeSink, 31, 2_249_100, 500, 50);
// //         _lmpVault.updateDebtReporting(_destinations);
// //     }

// //     function test_updateDebtReporting_HighNavMarkResetWhenVaultEmpties() public {
// //         _accessController.grantRole(Roles.SOLVER_ROLE, address(this));
// //         _accessController.grantRole(Roles.LMP_FEE_SETTER_ROLE, address(this));

// //         // 1. User 1 deposits 1000

// //         _asset.mint(address(this), 1000);
// //         _asset.approve(address(_lmpVault), 1000);
// //         _lmpVault.deposit(1000, address(this));

// //         // 2. Rebalance

// //         // At time of writing LMPVault always returned true for verifyRebalance
// //         // Rebalance 1000 baseAsset for 500 underlyerOne+destVaultOne (price is 2:1)
// //         _underlyerOne.mint(address(this), 250);
// //         _underlyerOne.approve(address(_lmpVault), 250);
// //         _lmpVault.rebalance(
// //             address(_destVaultOne),
// //             address(_underlyerOne), // tokenIn
// //             250,
// //             address(0), // destinationOut, none when sending out baseAsset
// //             address(_asset), // baseAsset, tokenOut
// //             500
// //         );

// //         // Setting a sink but not an actual fee yet
// //         address feeSink = vm.addr(555);
// //         _lmpVault.setFeeSink(feeSink);

// //         // Dropped 1000 asset in and just did a rebalance. There's no slippage or anything
// //         // atm so assets are just moved around, should still be reporting 1000 available
// //         uint256 shareBal = _lmpVault.balanceOf(address(this));
// //         assertEq(_lmpVault.totalDebt(), 500);
// //         assertEq(_lmpVault.totalIdle(), 500);
// //         assertEq(_lmpVault.convertToAssets(shareBal), 1000);

// //         // 3. Increase the value of the DV asset 3x

// //         // Underlyer1 is currently worth 2 ETH a piece
// //         // Lets update the price to 6 ETH (3x) and trigger a debt reporting
// //         // and verify our totalDebt and asset conversions match the drop in price
// //         _mockRootPrice(address(_underlyerOne), 6e18);

// //         // 4. Debt report
// //         _accessController.grantRole(Roles.LMP_UPDATE_DEBT_REPORTING_ROLE, address(this));
// //         _lmpVault.updateDebtReporting(_destinations);

// //         // No change in idle
// //         assertEq(_lmpVault.totalIdle(), 500);
// //         // Debt value per share went 3x so it's a 200% increase. Was 500 before
// //         assertEq(_lmpVault.totalDebt(), 1500);
// //         // So overall I can get 500 + 1500 back
// //         shareBal = _lmpVault.balanceOf(address(this));
// //         assertEq(_lmpVault.convertToAssets(shareBal), 2000);

// //         // 5. Validate nav per share high water is greater than default - this is point A

// //         uint256 pointA = _lmpVault.navPerShareHighMark();
// //         assertGt(pointA, MAX_FEE_BPS);

// //         // 6. User 1 withdrawal all funds
// //         _lmpVault.withdraw(2000, address(this), address(this));

// //         // 7. Ensure nav per share high water is default
// //         assertEq(_lmpVault.navPerShareHighMark(), MAX_FEE_BPS);

// //         // 8. User 2 deposits
// //         address user2 = vm.addr(222_222);
// //         vm.label(user2, "user2");

// //         _asset.mint(user2, 1000);
// //         vm.startPrank(user2);
// //         _asset.approve(address(_lmpVault), 1000);
// //         _lmpVault.deposit(1000, user2);

// //         // 9. Set value of DV asset to 1x
// //         _mockRootPrice(address(_underlyerOne), 2e18);

// //         // 10. Rebalance
// //         vm.startPrank(address(this));
// //         _underlyerOne.mint(address(this), 250);
// //         _underlyerOne.approve(address(_lmpVault), 250);
// //         _lmpVault.rebalance(
// //             address(_destVaultOne),
// //             address(_underlyerOne), // tokenIn
// //             250,
// //             address(0), // destinationOut, none when sending out baseAsset
// //             address(_asset), // baseAsset, tokenOut
// //             500
// //         );

// //         // 11. Increase the value of the DV asset to 2x
// //         _mockRootPrice(address(_underlyerOne), 4e18);

// //         // 12. Debt report
// //         _lmpVault.updateDebtReporting(_destinations);

// //         // 13. Confirm nav share high water mark is greater than default and less than point A
// //         uint256 currentHighMark = _lmpVault.navPerShareHighMark();
// //         assertGt(currentHighMark, MAX_FEE_BPS);
// //         assertLt(currentHighMark, pointA);
// //     }

// //     function test_updateDebtReporting_FlashRebalanceFeesAreTakenWithoutDoubleDipping() public {
// //         _accessController.grantRole(Roles.SOLVER_ROLE, address(this));
// //         _accessController.grantRole(Roles.LMP_FEE_SETTER_ROLE, address(this));
// //         _accessController.grantRole(Roles.LMP_UPDATE_DEBT_REPORTING_ROLE, address(this));

// //         FlashRebalancer rebalancer = new FlashRebalancer();

// //         // User is going to deposit 1000 asset
// //         _asset.mint(address(this), 1000);
// //         _asset.approve(address(_lmpVault), 1000);
// //         _lmpVault.deposit(1000, address(this));

// //         // Tell the test harness how much it should have at mid execution
// //         rebalancer.snapshotAsset(address(_asset), 500);

// //         // At time of writing LMPVault always returned true for verifyRebalance
// //         // Rebalance 1000 baseAsset for 500 underlyerOne+destVaultOne (price is 2:1)
// //         _underlyerOne.mint(address(this), 250);
// //         _underlyerOne.approve(address(_lmpVault), 250);
// //         _lmpVault.flashRebalance(
// //             rebalancer,
// //             IStrategy.RebalanceParams({
// //                 destinationIn: address(_destVaultOne),
// //                 tokenIn: address(_underlyerOne), // tokenIn
// //                 amountIn: 250,
// //                 destinationOut: address(0), // destinationOut, none for baseAsset
// //                 tokenOut: address(_asset), // baseAsset, tokenOut
// //                 amountOut: 500
// //             }),
// //             abi.encode("")
// //         );

// //         // Setting a sink but not an actual fee yet
// //         address feeSink = vm.addr(555);
// //         _lmpVault.setFeeSink(feeSink);

// //         // Dropped 1000 asset in and just did a rebalance. There's no slippage or anything
// //         // atm so assets are just moved around, should still be reporting 1000 available
// //         uint256 shareBal = _lmpVault.balanceOf(address(this));
// //         assertEq(_lmpVault.totalDebt(), 500);
// //         assertEq(_lmpVault.totalIdle(), 500);
// //         assertEq(_lmpVault.convertToAssets(shareBal), 1000);

// //         // Underlyer1 is currently worth 2 ETH a piece
// //         // Lets update the price to 1.5 ETH and trigger a debt reporting
// //         // and verify our totalDebt and asset conversions match the drop in price
// //         _mockRootPrice(address(_underlyerOne), 15e17);
// //         _lmpVault.updateDebtReporting(_destinations);

// //         // No change in idle
// //         assertEq(_lmpVault.totalIdle(), 500);
// //         // Debt value per share went from 2 to 1.5 so a 25% drop
// //         // Was 500 before
// //         assertEq(_lmpVault.totalDebt(), 375);
// //         // So overall I can get 500 + 375 back
// //         shareBal = _lmpVault.balanceOf(address(this));
// //         assertEq(_lmpVault.convertToAssets(shareBal), 875);

// //         // Lets update the price back 2 ETH. This should put the numbers back
// //         // to where they were, idle+debt+assets. We shouldn't see any fee's
// //         // taken though as this is just recovering back to where our deployment was
// //         // We're just even now
// //         _mockRootPrice(address(_underlyerOne), 2 ether);

// //         vm.expectEmit(true, true, true, true);
// //         emit FeeCollected(0, feeSink, 0, 0, 500, 500);
// //         _lmpVault.updateDebtReporting(_destinations);
// //         shareBal = _lmpVault.balanceOf(address(this));
// //         assertEq(_lmpVault.totalDebt(), 500);
// //         assertEq(_lmpVault.totalIdle(), 500);
// //         assertEq(_lmpVault.convertToAssets(shareBal), 1000);

// //         // Next price update. It'll go from 2 to 2.5 ether. 25%,
// //         // or a 125 ETH increase. There's technically a profit here but we
// //         // haven't set a fee yet so that should still be 0
// //         _mockRootPrice(address(_underlyerOne), 25e17);
// //         vm.expectEmit(true, true, true, true);
// //         emit FeeCollected(0, feeSink, 0, 1_250_000, 500, 625);
// //         _lmpVault.updateDebtReporting(_destinations);
// //         shareBal = _lmpVault.balanceOf(address(this));
// //         assertEq(_lmpVault.totalDebt(), 625);
// //         assertEq(_lmpVault.totalIdle(), 500);
// //         assertEq(_lmpVault.convertToAssets(shareBal), 1125);

// //         // Lets set a fee and and force another increase. We should only
// //         // take fee's on the increase from the original deployment
// //         // from this point forward. No back taking fee's
// //         _lmpVault.setStreamingFeeBps(2000); // 20%

// //         // From 2.5 to 3 or a 20% increase
// //         // Debt was at 625, so we have 125 profit
// //         // 1250 nav @ 1000 shares,
// //         // 25*1000/1250, 20 (+1 taking into account the new totalSupply after mint) new shares to us
// //         _mockRootPrice(address(_underlyerOne), 3e18);
// //         vm.expectEmit(true, true, true, true);
// //         emit FeeCollected(25, feeSink, 21, 1_250_000, 500, 750);
// //         _lmpVault.updateDebtReporting(_destinations);
// //         shareBal = _lmpVault.balanceOf(address(this));
// //         // Previously 625 but with 125 increase
// //         assertEq(_lmpVault.totalDebt(), 750);
// //         // Fees come from extra minted shares, idle shouldn't change
// //         assertEq(_lmpVault.totalIdle(), 500);
// //         // 21 Extra shares were minted to cover the fees. That's 1021 shares now
// //         // for 1250 assets. 1000*1250/1021
// //         assertEq(_lmpVault.convertToAssets(shareBal), 1224);

// //         // Debt report again with no changes, make sure we don't double dip fee's
// //         vm.expectEmit(true, true, true, true);
// //         emit FeeCollected(0, feeSink, 0, 0, 500, 750);
// //         _lmpVault.updateDebtReporting(_destinations);

// //         // Test the double dip again but with a decrease and
// //         // then increase price back to where we were

// //         // Decrease in price here so expect no fees
// //         _mockRootPrice(address(_underlyerOne), 2e18);
// //         vm.expectEmit(true, true, true, true);
// //         emit FeeCollected(0, feeSink, 0, 0, 500, 500);
// //         _lmpVault.updateDebtReporting(_destinations);
// //         //And back to 3, should still be 0 since we've been here before
// //         _mockRootPrice(address(_underlyerOne), 3e18);
// //         vm.expectEmit(true, true, true, true);
// //         emit FeeCollected(0, feeSink, 0, 0, 500, 750);
// //         _lmpVault.updateDebtReporting(_destinations);

// //         // And finally an increase above our last high value where we should
// //         // grab more fee's. Debt was at 750 @3 ETH. Going from 3 to 4, worth
// //         // 1000 now. Our nav is 1500 with 1021 shares. Previous was 1250 @ 1021 shares.
// //         // So that's 1.224 nav/share -> 1.469 a change of 0.245. With totalSupply
// //         // at 1021 that's a profit of 250.145.
// //         // Our 20% on that profit gives us ~51. 51*1021/1500, ~36 shares
// //         _mockRootPrice(address(_underlyerOne), 4e18);
// //         vm.expectEmit(true, true, true, true);
// //         emit FeeCollected(51, feeSink, 36, 2_500_429, 500, 1000);
// //         _lmpVault.updateDebtReporting(_destinations);
// //     }

// //     function test_updateDebtReporting_EarnedRewardsAreFactoredIn() public {
// //         _accessController.grantRole(Roles.LMP_FEE_SETTER_ROLE, address(this));
// //         _accessController.grantRole(Roles.LMP_UPDATE_DEBT_REPORTING_ROLE, address(this));

// //         // Going to work with two users for this one to test partial ownership
// //         // Both users get 1000 asset initially
// //         address user1 = vm.addr(238_904);
// //         vm.label(user1, "user1");
// //         _asset.mint(user1, 1000);

// //         address user2 = vm.addr(89_576);
// //         vm.label(user2, "user2");
// //         _asset.mint(user2, 1000);

// //         // Configure our fees and where they will go
// //         address feeSink = vm.addr(1000);
// //         _lmpVault.setFeeSink(feeSink);
// //         vm.label(feeSink, "feeSink");
// //         _lmpVault.setStreamingFeeBps(2000); // 20%

// //         // User 1 will deposit 500 and user 2 will deposit 250
// //         vm.startPrank(user1);
// //         _asset.approve(address(_lmpVault), 500);
// //         _lmpVault.deposit(500, user1);
// //         vm.stopPrank();

// //         vm.startPrank(user2);
// //         _asset.approve(address(_lmpVault), 250);
// //         _lmpVault.deposit(250, user2);
// //         vm.stopPrank();

// //         // We only have idle funds, and haven't done a deployment
// //         // Taking a snapshot should result in no fee's as we haven't
// //         // done anything

// //         vm.expectEmit(true, true, true, true);
// //         emit FeeCollected(0, feeSink, 0, 0, 750, 0);
// //         _lmpVault.updateDebtReporting(_destinations);

// //         // Check our initial state before rebalance
// //         // Everything should be in idle with no other token balances
// //         assertEq(_underlyerOne.balanceOf(address(_destVaultOne)), 0);
// //         assertEq(_destVaultOne.balanceOf(address(_lmpVault)), 0);
// //         assertEq(_underlyerTwo.balanceOf(address(_destVaultTwo)), 0);
// //         assertEq(_destVaultTwo.balanceOf(address(_lmpVault)), 0);
// //         assertEq(_lmpVault.totalIdle(), 750);
// //         assertEq(_lmpVault.totalDebt(), 0);

// //         // Going to perform multiple rebalances. 400 asset to DV1 350 to DV2.
// //         // So that'll be 200 Underlyer 1 (U1) and 250 Underlyer 2 (U2) back (U1 is 2:1 price)
// //         address solver = vm.addr(34_343);
// //         _accessController.grantRole(Roles.SOLVER_ROLE, solver);
// //         vm.label(solver, "solver");
// //         _underlyerOne.mint(solver, 200);
// //         _underlyerTwo.mint(solver, 350);

// //         vm.startPrank(solver);
// //         _underlyerOne.approve(address(_lmpVault), 200);
// //         _underlyerTwo.approve(address(_lmpVault), 350);

// //         _lmpVault.rebalance(
// //             address(_destVaultOne),
// //             address(_underlyerOne), // tokenIn
// //             200, // Price is 2:1 for DV1 underlyer
// //             address(0), // destinationOut, none when sending out baseAsset
// //             address(_asset), // baseAsset, tokenOut
// //             400
// //         );
// //         _lmpVault.rebalance(
// //             address(_destVaultTwo),
// //             address(_underlyerTwo), // tokenIn
// //             350, // Price is 1:1 for DV2 underlyer
// //             address(0), // destinationOut, none when sending out baseAsset
// //             address(_asset), // baseAsset, tokenOut
// //             350
// //         );
// //         vm.stopPrank();

// //         // So at this point, DV1 should have 200 U1, with LMP having 200 DV1
// //         // DV2 should have 350 U2, with LMP having 350 DV2
// //         // We also rebalanced all our idle so it's at 0 with everything moved to debt

// //         assertEq(_underlyerOne.balanceOf(address(_destVaultOne)), 200);
// //         assertEq(_destVaultOne.balanceOf(address(_lmpVault)), 200);
// //         assertEq(_underlyerTwo.balanceOf(address(_destVaultTwo)), 350);
// //         assertEq(_destVaultTwo.balanceOf(address(_lmpVault)), 350);
// //         assertEq(_lmpVault.totalIdle(), 0);
// //         assertEq(_lmpVault.totalDebt(), 750);

// //         // Rebalance should have performed a minimal debt snapshot and since
// //         // there's been no change in price or amounts we should still
// //         // have 0 fee's captured

// //         vm.expectEmit(true, true, true, true);
// //         emit FeeCollected(0, feeSink, 0, 0, 0, 750);
// //         _lmpVault.updateDebtReporting(_destinations);

// //         // Now we're going to rebalance from DV2 to DV1 but value of U2
// //         // has gone down. It was worth 1 ETH and is now only worth .6 ETH
// //         // We'll assume the rebalancer thinks this is OK and will let it go
// //         // through. Of our 750 debt, 350 would have been attributed to
// //         // to DV2. It's now only worth 210, so totalDebt will end up
// //         // being 750-350+210 = 610. That 210 is worth 105 U1 shares
// //         // that's what the solver will be transferring in
// //         _mockRootPrice(address(_underlyerTwo), 6e17);
// //         _underlyerOne.mint(solver, 105);
// //         vm.startPrank(solver);
// //         _underlyerOne.approve(address(_lmpVault), 105);
// //         _lmpVault.rebalance(
// //             address(_destVaultOne),
// //             address(_underlyerOne), // tokenIn
// //             105,
// //             address(_destVaultTwo), // destinationOut, none when sending out baseAsset
// //             address(_underlyerTwo), // baseAsset, tokenOut
// //             350
// //         );
// //         vm.stopPrank();

// //         // Added 105 shares to DV1+U1 setup
// //         assertEq(_underlyerOne.balanceOf(address(_destVaultOne)), 305);
// //         assertEq(_destVaultOne.balanceOf(address(_lmpVault)), 305);
// //         // We burned everything related DV2
// //         assertEq(_underlyerTwo.balanceOf(address(_destVaultTwo)), 0);
// //         assertEq(_destVaultTwo.balanceOf(address(_lmpVault)), 0);
// //         // Still nothing in idle and we lost 140
// //         assertEq(_lmpVault.totalIdle(), 0);
// //         assertEq(_lmpVault.totalDebt(), 750 - 140);

// //         // Another debt reporting, but we've done nothing but lose money
// //         // so again no fees

// //         vm.expectEmit(true, true, true, true);
// //         emit FeeCollected(0, feeSink, 0, 0, 0, 750 - 140);
// //         _lmpVault.updateDebtReporting(_destinations);

// //         // Now the value of U1 is going up. From 2 ETH to 2.2 ETH
// //         // That makes those 305 shares now worth 671
// //         // Do another debt reporting but we're still below our debt basis
// //         // of 750 so still no fee's
// //         _mockRootPrice(address(_underlyerOne), 22e17);

// //         vm.expectEmit(true, true, true, true);
// //         emit FeeCollected(0, feeSink, 0, 0, 0, 671);
// //         _lmpVault.updateDebtReporting(_destinations);
// //         assertEq(_lmpVault.totalDebt(), 671);

// //         // New user comes along and deposits 1000 more.
// //         address user3 = vm.addr(239_994);
// //         vm.label(user3, "user1");
// //         _asset.mint(user3, 1000);
// //         vm.startPrank(user3);
// //         _asset.approve(address(_lmpVault), 1000);
// //         _lmpVault.deposit(1000, user3);
// //         vm.stopPrank();

// //         // LMP has 750 shares, total assets of 671 with 1000 more coming in
// //         // 1000 * 750 / 671, user gets 1117 shares
// //         assertEq(_lmpVault.balanceOf(user3), 1117);

// //         // No change in debt with that operation but now we have some idle
// //         assertEq(_lmpVault.totalIdle(), 1000);
// //         assertEq(_lmpVault.totalDebt(), 671);

// //         // Another debt reporting, but since we don't take fee's on idle
// //         // it should be 0

// //         vm.expectEmit(true, true, true, true);
// //         emit FeeCollected(0, feeSink, 0, 0, 1000, 671);
// //         _lmpVault.updateDebtReporting(_destinations);

// //         // U1 price goes up to 4 ETH, our 305 shares
// //         // are now worth 1220. With 1000 in idle, total assets are 2220.
// //         // We have 1117+750 = 1867 shares. 1.18 nav/share up from 1
// //         // .18 * 1867 is about a profit of 352. With our 20% fee
// //         // we should get 71. Converted to shares that gets us
// //         // 71_fee * 1867_lmpSupply / 2220_totalAssets = 60(+2 with new totalSupply after additional shares mint)
// // shares
// //         _mockRootPrice(address(_underlyerOne), 4e18);
// //         vm.expectEmit(true, true, true, true);
// //         emit FeeCollected(71, feeSink, 62, 3_528_630, 1000, 1220);
// //         _lmpVault.updateDebtReporting(_destinations);

// //         // Now lets introduce reward value. Deposit rewards, something normally
// //         // only the liquidator will do, into the DV1's rewarder
// //         _accessController.grantRole(Roles.LIQUIDATOR_ROLE, address(this));
// //         _asset.mint(address(this), 10_000);
// //         _asset.approve(address(_destVaultOne.rewarder()), 10_000);
// //         IMainRewarder(_destVaultOne.rewarder()).queueNewRewards(10_000);

// //         // Roll blocks forward and verify the LMP has earned something
// //         vm.roll(block.number + 100);
// //         uint256 earned = IMainRewarder(_destVaultOne.rewarder()).earned(address(_lmpVault));
// //         assertEq(earned, 999);

// //         // So at the next debt reporting our nav should go up by 999
// //         // Previously we were at 1929 shares with 2220 assets
// //         // Or an NAV/share of 1.150855365. Now we're at
// //         // 2220+999 or 3219 assets, total supply 1929 - nav/share - 1.66874028
// //         // That's a NAV increase of roughly 0.517884915. So
// //         // there was 999 in profit. At our 20% fee ~200 (199.xx but we round up)
// //         // To capture 200 asset we need ~128 shares
// //         uint256 feeSinkBeforeBal = _lmpVault.balanceOf(feeSink);
// //         vm.expectEmit(true, true, true, true);
// //         emit FeeCollected(200, feeSink, 128, 9_990_291, 1999, 1220);
// //         _lmpVault.updateDebtReporting(_destinations);
// //         uint256 feeSinkAfterBal = _lmpVault.balanceOf(feeSink);
// //         assertEq(feeSinkAfterBal - feeSinkBeforeBal, 128);
// //         assertEq(_lmpVault.totalSupply(), 2057);

// //         // Users come to withdraw everything. User share breakdown looks this:
// //         // User 1 - 500
// //         // User 2 - 250
// //         // User 3 - 1117
// //         // Fees - 128 + 62 - 190
// //         // Total Supply - 2057
// //         // We have a totalAssets() of 3219
// //         // We assume no slippage
// //         // User 1 - 500/2057*3219 - ~782
// //         // User 2 - 250/(2057-500)*(3219-782) - ~391
// //         // User 3 - 1117/(2057-500-250)*(3219-782-391) - ~1748
// //         // Fees - 190/(2057-500-250-1117)*(3219-782-391-1748) - 298

// //         vm.prank(user1);
// //         uint256 user1Assets = _lmpVault.redeem(500, vm.addr(4847), user1);
// //         vm.prank(user2);
// //         uint256 user2Assets = _lmpVault.redeem(250, vm.addr(5847), user2);
// //         vm.prank(user3);
// //         uint256 user3Assets = _lmpVault.redeem(1117, vm.addr(6847), user3);

// //         // Just our fee shares left
// //         assertEq(_lmpVault.totalSupply(), 190);

// //         vm.prank(feeSink);
// //         uint256 feeSinkAssets = _lmpVault.redeem(190, vm.addr(7847), feeSink);

// //         // Nothing left in the vault
// //         assertEq(_lmpVault.totalSupply(), 0);
// //         assertEq(_lmpVault.totalDebt(), 0);
// //         assertEq(_lmpVault.totalIdle(), 0);

// //         // Make sure users got what they expected
// //         assertEq(_asset.balanceOf(vm.addr(4847)), 782);
// //         assertEq(user1Assets, 782);

// //         assertEq(_asset.balanceOf(vm.addr(5847)), 391);
// //         assertEq(user2Assets, 391);

// //         assertEq(_asset.balanceOf(vm.addr(6847)), 1748);
// //         assertEq(user3Assets, 1748);

// //         assertEq(_asset.balanceOf(vm.addr(7847)), 298);
// //         assertEq(feeSinkAssets, 298);
// //     }

// //     /// Based on @dev https://github.com/Tokemak/2023-06-sherlock-judging/blob/main/invalid/675.md
// //     function test_updateDebtReporting_debtDecreaseRoundingNoUnderflow() public {
// //         _accessController.grantRole(Roles.SOLVER_ROLE, address(this));
// //         _accessController.grantRole(Roles.LMP_FEE_SETTER_ROLE, address(this));

// //         // 1) Value DV1 @ 1e18
// //         _mockRootPrice(address(_underlyerOne), 1e18);

// //         // 2) Deposit 10 wei
// //         _asset.mint(address(this), 1_000_000_000_000_000_010);
// //         _asset.approve(address(_lmpVault), 1_000_000_000_000_000_010);
// //         _lmpVault.deposit(1_000_000_000_000_000_010, address(this));

// //         // 3) Rebalance 10 to DV1
// //         _underlyerOne.mint(address(this), 1_000_000_000_000_000_010);
// //         _underlyerOne.approve(address(_lmpVault), 1_000_000_000_000_000_010);
// //         _lmpVault.rebalance(
// //             address(_destVaultOne),
// //             address(_underlyerOne), // tokenIn
// //             1_000_000_000_000_000_010,
// //             address(0), // destinationOut, none when sending out baseAsset
// //             address(_asset), // baseAsset, tokenOut
// //             1_000_000_000_000_000_010
// //         );

// //         _mockRootPrice(address(_underlyerOne), 1.1e18);

// //         _accessController.grantRole(Roles.LMP_UPDATE_DEBT_REPORTING_ROLE, address(this));
// //         _lmpVault.updateDebtReporting(_destinations);

// //         _lmpVault.redeem(100_000_000_000_000_001, address(this), address(this));

// //         _lmpVault.redeem(100_000_000_000_000_001, address(this), address(this));

// //         _accessController.grantRole(Roles.LMP_UPDATE_DEBT_REPORTING_ROLE, address(this));
// //         _lmpVault.updateDebtReporting(_destinations);
// //     }

// //     /// Based on @dev https://github.com/sherlock-audit/2023-06-tokemak-judging/blob/main/219-M/219.md
// //     function test_OverWalletLimitIsDisabledForSink() public {
// //         address user01 = vm.addr(101);
// //         address user02 = vm.addr(102);
// //         vm.label(user01, "user01");
// //         vm.label(user02, "user02");
// //         _accessController.grantRole(Roles.SOLVER_ROLE, address(this));
// //         _accessController.grantRole(Roles.LMP_FEE_SETTER_ROLE, address(this));

// //         // Setting a sink
// //         address feeSink = vm.addr(555);
// //         vm.label(feeSink, "feeSink");
// //         _lmpVault.setFeeSink(feeSink);
// //         // Setting a fee
// //         _lmpVault.setStreamingFeeBps(2000); // 20%
// //         //Set the per-wallet share limit
// //         _lmpVault.setPerWalletLimit(500);

// //         //user01 `deposit()`
// //         vm.startPrank(user01);
// //         _asset.mint(user01, 500);
// //         _asset.approve(address(_lmpVault), 500);
// //         _lmpVault.deposit(500, user01);
// //         vm.stopPrank();

// //         //user02 `deposit()`
// //         vm.startPrank(user02);
// //         _asset.mint(user02, 500);
// //         _asset.approve(address(_lmpVault), 500);
// //         _lmpVault.deposit(500, user02);
// //         vm.stopPrank();

// //         // Queue up some Destination Vault rewards
// //         _accessController.grantRole(Roles.LMP_REWARD_MANAGER_ROLE, address(this));
// //         _accessController.grantRole(Roles.LIQUIDATOR_ROLE, address(this));

// //         // At time of writing LMPVault always returned true for verifyRebalance
// //         // Rebalance 500 baseAsset for 250 underlyerOne+destVaultOne
// //         uint256 assetBalBefore = _asset.balanceOf(address(this));
// //         _underlyerOne.mint(address(this), 500);
// //         _underlyerOne.approve(address(_lmpVault), 500);
// //         _lmpVault.rebalance(
// //             address(_destVaultOne),
// //             address(_underlyerOne), // tokenIn
// //             250,
// //             address(0), // destinationOut, none when sending out baseAsset
// //             address(_asset), // baseAsset, tokenOut
// //             500
// //         );
// //         uint256 assetBalAfter = _asset.balanceOf(address(this));

// //         _asset.mint(address(this), 2000);
// //         _asset.approve(_destVaultOne.rewarder(), 2000);
// //         IMainRewarder(_destVaultOne.rewarder()).queueNewRewards(2000);

// //         // LMP Vault is correctly tracking 500 remaining in idle, 500 out as debt
// //         uint256 totalIdleAfterFirstRebalance = _lmpVault.totalIdle();
// //         uint256 totalDebtAfterFirstRebalance = _lmpVault.totalDebt();
// //         assertEq(totalIdleAfterFirstRebalance, 500, "totalIdleAfterFirstRebalance");
// //         assertEq(totalDebtAfterFirstRebalance, 500, "totalDebtAfterFirstRebalance");
// //         // The destination vault has the 250 underlying
// //         assertEq(_underlyerOne.balanceOf(address(_destVaultOne)), 250);
// //         // The lmp vault has the 250 of the destination
// //         assertEq(_destVaultOne.balanceOf(address(_lmpVault)), 250);
// //         // Ensure the solver got their funds
// //         assertEq(assetBalAfter - assetBalBefore, 500, "solverAssetBal");

// //         //to simulate the accumulative fees in `sink` address. user01 `deposit()` to `sink`
// //         vm.startPrank(user01);
// //         _asset.mint(user01, 500);
// //         _asset.approve(address(_lmpVault), 500);
// //         _lmpVault.deposit(500, feeSink);
// //         vm.stopPrank();

// //         // Roll the block so that the rewards we queued earlier will become available
// //         vm.roll(block.number + 100);

// //         // `rebalance()`
// //         _asset.mint(address(this), 200);
// //         _asset.approve(address(_lmpVault), 200);

// //         // Would have reverted if we didn't disable the limit for the sink
// //         // vm.expectRevert(); // <== expectRevert
// //         _lmpVault.rebalance(
// //             address(0), // none when sending in base asset
// //             address(_asset), // tokenIn
// //             200,
// //             address(_destVaultOne), // destinationOut
// //             address(_underlyerOne), // tokenOut
// //             100
// //         );
// //     }

// //     function test_Halborn04_Exploit() public {
// //         address user1 = makeAddr("USER_1");
// //         address user2 = makeAddr("USER_2");
// //         address user3 = makeAddr("USER_3");

// //         // Ensure we start from a clean slate
// //         assertEq(_lmpVault.balanceOf(address(this)), 0);
// //         assertEq(_lmpVault.rewarder().balanceOf(address(this)), 0);

// //         // Add rewarder to the system
// //         _accessController.grantRole(Roles.LMP_REWARD_MANAGER_ROLE, address(this));
// //         _lmpVault.rewarder().addToWhitelist(address(this));

// //         // Hal-04: Adding 100 TOKE as vault rewards and waiting until they are claimable.
// //         // Hal-04: Rewarder TOKE balance: 100000000000000000000
// //         _toke.mint(address(this), 100e18);
// //         _toke.approve(address(_lmpVault.rewarder()), 100e18);
// //         _lmpVault.rewarder().queueNewRewards(100e18);
// //         vm.roll(block.number + 10_000);

// //         // Hal-04: User1 gets 500 tokens minted
// //         _asset.mint(user1, 500e18);

// //         // Hal-04: User1 balance is 500
// //         assertEq(_asset.balanceOf(user1), 500e18);
// //         // Hal-04: User2 balance is 0
// //         assertEq(_asset.balanceOf(user2), 0);
// //         // Hal-04: User3 balance is 0
// //         assertEq(_asset.balanceOf(user3), 0);

// //         // Hal-04: User1 deposits 500 tokens in the vault and then instantly transfers the shares to User2
// //         vm.startPrank(user1);
// //         _asset.approve(address(_lmpVault), 500e18);
// //         _lmpVault.deposit(500e18, user1);
// //         _lmpVault.transfer(user2, 500e18);
// //         vm.stopPrank();

// //         // Hal-04: After receiving the funds, User2 will transfer the shares to User3...
// //         vm.prank(user2);
// //         _lmpVault.transfer(user3, 500e18);

// //         // Hal-04: User3 calls redeem, in order to obtain the rewards, setting User1 as receiver for the deposited
// //         // tokens
// //         vm.prank(user3);
// //         _lmpVault.redeem(500e18, user1, user3);

// //         // Hal-04 expected outcomes:
// //         //  - User1 TOKE balance after the exploit: 33333333333333333333
// //         //  - User2 TOKE balance after the exploit: 33333333333333333333
// //         //  - User3 TOKE balance after the exploit: 33333333333333333333

// //         // However, with current updates, User1 should receive all the rewards
// //         assertEq(_toke.balanceOf(user1), 100e18);
// //         assertEq(_toke.balanceOf(user2), 0);
// //         assertEq(_toke.balanceOf(user3), 0);
// //     }

// //     /// Based on @dev https://github.com/sherlock-audit/2023-06-tokemak-judging/blob/main/219-M/219.md
// //     function test_OverWalletLimitIsDisabledWhenBurningToken() public {
// //         // Mint 1000 tokens to the test address
// //         _asset.mint(address(this), 1000);

// //         // Approve the Vault to spend the 1000 tokens on behalf of this address
// //         _asset.approve(address(_lmpVault), 1000);

// //         // Deposit the 1000 tokens into the Vault
// //         _lmpVault.deposit(1000, address(this));

// //         // Set the per-wallet share limit to 500 tokens
// //         _lmpVault.setPerWalletLimit(500);

// //         // Define the fee sink address
// //         _lmpVault.setFeeSink(makeAddr("FEE_SINK"));

// //         // Try to withdraw (burn) 1000 tokens - this should NOT revert if the limit is disabled when burning
// tokens
// //         _lmpVault.withdraw(1000, address(this), address(this));
// //     }

//     function test_flashRebalance_IdleCantLeaveIfShutdown() public {
//         _accessController.grantRole(Roles.SOLVER_ROLE, address(this));
//         FlashRebalancer rebalancer = new FlashRebalancer();

//         _asset.mint(address(this), 1000);
//         _asset.approve(address(_lmpVault), 1000);
//         _lmpVault.deposit(1000, address(this));

//         _underlyerOne.mint(address(this), 500);
//         _underlyerOne.approve(address(_lmpVault), 500);

//         // Tell the test harness how much it should have at mid execution
//         rebalancer.snapshotAsset(address(_asset), 500);

//         _lmpVault.shutdown(ILMPVault.VaultShutdownStatus.Deprecated);

//         vm.expectRevert(abi.encodeWithSelector(LMPVault.VaultShutdown.selector));
//         _lmpVault.flashRebalance(
//             rebalancer,
//             IStrategy.RebalanceParams({
//                 destinationIn: address(_destVaultOne),
//                 tokenIn: address(_underlyerOne), // tokenIn
//                 amountIn: 250,
//                 destinationOut: address(0), // destinationOut, none when sending out baseAsset
//                 tokenOut: address(_asset), // baseAsset, tokenOut
//                 amountOut: 500
//             }),
//             abi.encode("")
//         );
//     }

//     function test_destinationVault_registered() public {
//         address dv = address(_createDV());

//         address[] memory dvs = new address[](1);
//         dvs[0] = dv;

//         assertFalse(_lmpVault.isDestinationRegistered(dv));
//         _lmpVault.addDestinations(dvs);
//         assertTrue(_lmpVault.isDestinationRegistered(dv));
//     }

//     function test_destinationVault_queuedForRemoval() public {
//         address dv = address(_createDV());
//         address[] memory dvs = new address[](1);
//         dvs[0] = dv;
//         _lmpVault.addDestinations(dvs);

//         // create some vault balance to trigger removal queue addition
//         vm.mockCall(dv, abi.encodeWithSelector(IERC20.balanceOf.selector, address(_lmpVault)), abi.encode(100));

//         assertTrue(IDestinationVault(dv).balanceOf(address(_lmpVault)) > 0, "dv balance should be > 0");

//         assertFalse(_lmpVault.isDestinationQueuedForRemoval(dv));
//         _lmpVault.removeDestinations(dvs);
//         assertTrue(_lmpVault.isDestinationQueuedForRemoval(dv));
//     }

//     function test_updateDebtReporting_FlashRebalanceEarnedRewardsAreFactoredIn() public {
//         _accessController.grantRole(Roles.LMP_FEE_SETTER_ROLE, address(this));
//         _accessController.grantRole(Roles.LMP_UPDATE_DEBT_REPORTING_ROLE, address(this));
//         FlashRebalancer rebalancer = new FlashRebalancer();

//         // Going to work with two users for this one to test partial ownership
//         // Both users get 1000 asset initially
//         address user1 = vm.addr(238_904);
//         vm.label(user1, "user1");
//         _asset.mint(user1, 1000);

//         address user2 = vm.addr(89_576);
//         vm.label(user2, "user2");
//         _asset.mint(user2, 1000);

//         // Configure our fees and where they will go
//         address feeSink = vm.addr(1000);
//         _lmpVault.setFeeSink(feeSink);
//         vm.label(feeSink, "feeSink");
//         _lmpVault.setStreamingFeeBps(2000); // 20%

//         // User 1 will deposit 500 and user 2 will deposit 250
//         vm.startPrank(user1);
//         _asset.approve(address(_lmpVault), 500);
//         _lmpVault.deposit(500, user1);
//         vm.stopPrank();

//         vm.startPrank(user2);
//         _asset.approve(address(_lmpVault), 250);
//         _lmpVault.deposit(250, user2);
//         vm.stopPrank();

//         // We only have idle funds, and haven't done a deployment
//         // Taking a snapshot should result in no fee's as we haven't
//         // done anything

//         vm.expectEmit(true, true, true, true);
//         emit FeeCollected(0, feeSink, 0, 0, 750, 0);
//         _lmpVault.updateDebtReporting(_destinations);

//         // Check our initial state before rebalance
//         // Everything should be in idle with no other token balances
//         assertEq(_underlyerOne.balanceOf(address(_destVaultOne)), 0);
//         assertEq(_destVaultOne.balanceOf(address(_lmpVault)), 0);
//         assertEq(_underlyerTwo.balanceOf(address(_destVaultTwo)), 0);
//         assertEq(_destVaultTwo.balanceOf(address(_lmpVault)), 0);
//         assertEq(_lmpVault.totalIdle(), 750);
//         assertEq(_lmpVault.totalDebt(), 0);

//         // Going to perform multiple rebalances. 400 asset to DV1 350 to DV2.
//         // So that'll be 200 Underlyer 1 (U1) and 250 Underlyer 2 (U2) back (U1 is 2:1 price)
//         address solver = vm.addr(34_343);
//         _accessController.grantRole(Roles.SOLVER_ROLE, solver);
//         vm.label(solver, "solver");
//         _underlyerOne.mint(solver, 200);
//         _underlyerTwo.mint(solver, 350);

//         vm.startPrank(solver);
//         _underlyerOne.approve(address(_lmpVault), 200);
//         _underlyerTwo.approve(address(_lmpVault), 350);

//         // Tell the test harness how much it should have at mid execution
//         rebalancer.snapshotAsset(address(_asset), 400);

//         _lmpVault.flashRebalance(
//             rebalancer,
//             IStrategy.RebalanceParams({
//                 destinationIn: address(_destVaultOne),
//                 tokenIn: address(_underlyerOne), // tokenIn
//                 amountIn: 200, // Price is 2:1 for DV1 underlyer
//                 destinationOut: address(0), // destinationOut, none for baseAsset
//                 tokenOut: address(_asset), // baseAsset, tokenOut
//                 amountOut: 400
//             }),
//             abi.encode("")
//         );

//         // Tell the test harness how much it should have at mid execution
//         rebalancer.snapshotAsset(address(_asset), 350);

//         _lmpVault.flashRebalance(
//             rebalancer,
//             IStrategy.RebalanceParams({
//                 destinationIn: address(_destVaultTwo),
//                 tokenIn: address(_underlyerTwo), // tokenIn
//                 amountIn: 350, // Price is 1:1 for DV2 underlyer
//                 destinationOut: address(0), // destinationOut, none for baseAsset
//                 tokenOut: address(_asset), // baseAsset, tokenOut
//                 amountOut: 350
//             }),
//             abi.encode("")
//         );
//         vm.stopPrank();

//         // So at this point, DV1 should have 200 U1, with LMP having 200 DV1
//         // DV2 should have 350 U2, with LMP having 350 DV2
//         // We also rebalanced all our idle so it's at 0 with everything moved to debt

//         assertEq(_underlyerOne.balanceOf(address(_destVaultOne)), 200);
//         assertEq(_destVaultOne.balanceOf(address(_lmpVault)), 200);
//         assertEq(_underlyerTwo.balanceOf(address(_destVaultTwo)), 350);
//         assertEq(_destVaultTwo.balanceOf(address(_lmpVault)), 350);
//         assertEq(_lmpVault.totalIdle(), 0);
//         assertEq(_lmpVault.totalDebt(), 750);
//     }
