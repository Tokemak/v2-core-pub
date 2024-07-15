// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2024 Tokemak Foundation. All rights reserved.

pragma solidity >=0.8.7;

import { IERC20 } from "openzeppelin-contracts/token/ERC20/ERC20.sol";

import { PctFeeSplitter } from "src/vault/fees/PctFeeSplitter.sol";
import { IPctFeeSplitter } from "src/interfaces/vault/fees/IPctFeeSplitter.sol";

import { Roles } from "src/libs/Roles.sol";
import { BaseTest } from "test/BaseTest.t.sol";
import { Errors } from "src/utils/Errors.sol";
import { WETH_MAINNET } from "test/utils/Addresses.sol";

// solhint-disable func-name-mixedcase
contract PctFeeSplitterTest is BaseTest {
    PctFeeSplitter public pctFeeSplitter;

    function setUp() public override {
        forkBlock = 20_190_540;
        super.setUp();
        pctFeeSplitter = new PctFeeSplitter(systemRegistry);
    }

    function _setFeeRecipients() public {
        PctFeeSplitter.FeeRecipient[] memory feeRecipients = new PctFeeSplitter.FeeRecipient[](3);
        feeRecipients[0] = IPctFeeSplitter.FeeRecipient({ pct: 5000, recipient: address(0x1) });
        feeRecipients[1] = IPctFeeSplitter.FeeRecipient({ pct: 4000, recipient: address(0x2) });
        feeRecipients[2] = IPctFeeSplitter.FeeRecipient({ pct: 1000, recipient: address(0x3) });

        //Grant Role
        accessController.grantRole(Roles.AUTO_POOL_MANAGER, address(this));

        pctFeeSplitter.setFeeRecipients(feeRecipients);
    }
}

contract SetFeeRecipients is PctFeeSplitterTest {
    function test_setFeeRecipients_RevertInvalidRole() public {
        PctFeeSplitter.FeeRecipient[] memory feeRecipients = new PctFeeSplitter.FeeRecipient[](2);
        feeRecipients[0] = IPctFeeSplitter.FeeRecipient({ pct: 5000, recipient: address(0x1) });
        feeRecipients[1] = IPctFeeSplitter.FeeRecipient({ pct: 4000, recipient: address(0x2) });

        vm.expectRevert(abi.encodeWithSelector(Errors.AccessDenied.selector));
        pctFeeSplitter.setFeeRecipients(feeRecipients);
    }

    function test_setFeeRecipients_RevertInvalidPct() public {
        PctFeeSplitter.FeeRecipient[] memory feeRecipients = new PctFeeSplitter.FeeRecipient[](2);
        feeRecipients[0] = IPctFeeSplitter.FeeRecipient({ pct: 5000, recipient: address(0x1) });
        feeRecipients[1] = IPctFeeSplitter.FeeRecipient({ pct: 4000, recipient: address(0x2) });

        //Grant Role
        accessController.grantRole(Roles.AUTO_POOL_MANAGER, address(this));

        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidParams.selector));
        pctFeeSplitter.setFeeRecipients(feeRecipients);
    }

    function test_setFeeRecipients() public {
        PctFeeSplitter.FeeRecipient[] memory feeRecipients = new PctFeeSplitter.FeeRecipient[](3);
        feeRecipients[0] = IPctFeeSplitter.FeeRecipient({ pct: 5000, recipient: address(0x1) });
        feeRecipients[1] = IPctFeeSplitter.FeeRecipient({ pct: 4000, recipient: address(0x2) });
        feeRecipients[2] = IPctFeeSplitter.FeeRecipient({ pct: 1000, recipient: address(0x3) });

        //Grant Role
        accessController.grantRole(Roles.AUTO_POOL_MANAGER, address(this));

        pctFeeSplitter.setFeeRecipients(feeRecipients);
    }

    function test_setFeeRecipientsAgain() public {
        PctFeeSplitter.FeeRecipient[] memory feeRecipients = new PctFeeSplitter.FeeRecipient[](3);
        feeRecipients[0] = IPctFeeSplitter.FeeRecipient({ pct: 5000, recipient: address(0x1) });
        feeRecipients[1] = IPctFeeSplitter.FeeRecipient({ pct: 4000, recipient: address(0x2) });
        feeRecipients[2] = IPctFeeSplitter.FeeRecipient({ pct: 1000, recipient: address(0x3) });

        //Grant Role
        accessController.grantRole(Roles.AUTO_POOL_MANAGER, address(this));

        pctFeeSplitter.setFeeRecipients(feeRecipients);

        PctFeeSplitter.FeeRecipient[] memory feeRecipientsAgain = new PctFeeSplitter.FeeRecipient[](2);
        feeRecipientsAgain[0] = IPctFeeSplitter.FeeRecipient({ pct: 7000, recipient: address(0x999) });
        feeRecipientsAgain[1] = IPctFeeSplitter.FeeRecipient({ pct: 3000, recipient: address(0x269) });

        pctFeeSplitter.setFeeRecipients(feeRecipientsAgain);

        uint16 currentFeePercentage;
        address currentFeeRecipient;

        (currentFeePercentage, currentFeeRecipient) = pctFeeSplitter.feeRecipients(0);
        assertEq(currentFeePercentage, feeRecipientsAgain[0].pct);
        assertEq(currentFeeRecipient, feeRecipientsAgain[0].recipient);
        (currentFeePercentage, currentFeeRecipient) = pctFeeSplitter.feeRecipients(1);
        assertEq(currentFeePercentage, feeRecipientsAgain[1].pct);
        assertEq(currentFeeRecipient, feeRecipientsAgain[1].recipient);

        vm.expectRevert();
        (currentFeePercentage, currentFeeRecipient) = pctFeeSplitter.feeRecipients(2);
    }
}

contract ClaimFees is PctFeeSplitterTest {
    function test_claimFees_RevertInvalidRecipient() public {
        _setFeeRecipients();
        deal(WETH_MAINNET, address(pctFeeSplitter), 10 * 1e18);
        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidSigner.selector, address(this)));
        pctFeeSplitter.claimFees(WETH_MAINNET);
    }

    function test_claimFees() public {
        uint256[] memory balBefore = new uint256[](3);
        uint256[] memory balAfter = new uint256[](3);

        _setFeeRecipients();
        balBefore[0] = IERC20(WETH_MAINNET).balanceOf(address(0x1));
        balBefore[1] = IERC20(WETH_MAINNET).balanceOf(address(0x2));
        balBefore[2] = IERC20(WETH_MAINNET).balanceOf(address(0x3));

        deal(WETH_MAINNET, address(pctFeeSplitter), 10 * 1e18);

        //Update fee Recipient
        vm.prank(address(0x1));

        pctFeeSplitter.claimFees(WETH_MAINNET);

        balAfter[0] = IERC20(WETH_MAINNET).balanceOf(address(0x1));
        balAfter[1] = IERC20(WETH_MAINNET).balanceOf(address(0x2));
        balAfter[2] = IERC20(WETH_MAINNET).balanceOf(address(0x3));

        assertEq(balAfter[0] - balBefore[0], 5 * 1e18);
        assertEq(balAfter[1] - balBefore[1], 4 * 1e18);
        assertEq(balAfter[2] - balBefore[2], 1 * 1e18);
    }
}
