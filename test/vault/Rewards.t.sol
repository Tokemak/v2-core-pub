// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2024 Tokemak Foundation. All rights reserved.
pragma solidity >=0.8.7;

import { BaseTest } from "test/BaseTest.t.sol";

import { ISystemRegistry } from "src/interfaces/ISystemRegistry.sol";
import { AccessController } from "src/security/AccessController.sol";
import { SystemRegistry } from "src/SystemRegistry.sol";

import { IRewards } from "src/interfaces/IRewards.sol";
import { SecurityBase } from "src/security/SecurityBase.sol";

import { EIP712, ECDSA } from "openzeppelin-contracts/utils/cryptography/EIP712.sol";
import { Roles } from "src/libs/Roles.sol";
import { Errors } from "src/utils/Errors.sol";
import { Rewards } from "src/vault/Rewards.sol";
import { ISystemRegistry } from "src/interfaces/ISystemRegistry.sol";
import { Vm } from "forge-std/Vm.sol";
import { MockERC20 } from "test/mocks/MockERC20.sol";

// solhint-disable func-name-mixedcase
contract RewardsTest is BaseTest {
    using ECDSA for bytes32;

    IRewards public rewards;
    MockERC20 public vaultToken;
    address public rewardsSigner;
    Vm.Wallet newWallet;

    function setUp() public virtual override {
        BaseTest.setUp();
        vaultToken = new MockERC20("Vault Token", "VT", 6);
        rewardsSigner = address(0x1);
        rewards = new Rewards(systemRegistry, vaultToken, rewardsSigner);
        newWallet = vm.createWallet(string("signer"));
    }
}

contract Constructor is RewardsTest {
    function test_constructor() public {
        assertEq(address(rewards.vaultToken()), address(vaultToken));
        assertEq(rewards.rewardsSigner(), rewardsSigner);
    }

    function test_constructor_withZeroTokenAddress() public {
        MockERC20 token = MockERC20(address(0));
        address signer = address(0x1);
        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "token"));
        Rewards incorrectRewards = new Rewards(systemRegistry, token, signer);
    }

    function test_constructor_withZeroSignerAddress() public {
        MockERC20 token = new MockERC20("Vault Token", "VT", 6);
        address signer = address(0);
        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "signerAddress"));
        Rewards incorrectRewards = new Rewards(systemRegistry, token, signer);
    }
}

contract SetSigner is RewardsTest {
    function test_setSigner() public {
        address newSigner = address(0x2);
        rewards.setSigner(newSigner);
        assertEq(rewards.rewardsSigner(), newSigner);
    }

    function test_setZeroSigner() public {
        address newSigner = address(0);
        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "newSigner"));
        rewards.setSigner(newSigner);
    }

    function test_onlyOwnerCanSetSigner() public {
        address newSigner = address(0x2);
        address user = address(0x3);
        vm.startPrank(user);
        vm.expectRevert(abi.encodeWithSelector(Errors.AccessDenied.selector));
        rewards.setSigner(newSigner);
        vm.stopPrank();
    }
}

contract ClaimSetup is RewardsTest {
    address newWalletPublicKey;
    address recipientWallet;
    uint256 initialRecipientWalletBalance;
    uint256 initialRewardsContractBalance;
    IRewards.Recipient recipient;

    function setUp() public override {
        RewardsTest.setUp();
        newWalletPublicKey = newWallet.addr;
        recipientWallet = address(0x4);
        initialRecipientWalletBalance = vaultToken.balanceOf(recipientWallet);

        recipient = IRewards.Recipient({ chainId: block.chainid, cycle: 1, wallet: recipientWallet, amount: 100 });
    }
}

contract Claim is ClaimSetup {
    function test_claimCorrectSignature(uint256 claimAmount) public {
        // address newWallet = address(0x3);
        vm.assume(claimAmount > 0);
        recipient.amount = claimAmount;

        vaultToken.mint(address(rewards), claimAmount);
        initialRewardsContractBalance = vaultToken.balanceOf(address(rewards));

        bytes32 hashedRecipient = rewards.genHash(recipient);
        rewards.setSigner(newWalletPublicKey);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(newWallet, hashedRecipient);
        vm.startPrank(recipientWallet);
        uint256 claimedAmount = rewards.claim(recipient, v, r, s);
        assertEq(claimedAmount, recipient.amount);
        assertEq(vaultToken.balanceOf(recipientWallet), initialRecipientWalletBalance + recipient.amount);
        assertEq(vaultToken.balanceOf(address(rewards)), initialRewardsContractBalance - recipient.amount);
        vm.stopPrank();
    }

    function test_claimCorrectSignatureZeroAmount() public {
        //zero amount
        recipient.amount = 0;

        uint256 mintAmount = 100;
        vaultToken.mint(address(rewards), mintAmount);
        initialRewardsContractBalance = vaultToken.balanceOf(address(rewards));

        bytes32 hashedRecipient = rewards.genHash(recipient);
        rewards.setSigner(newWalletPublicKey);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(newWallet, hashedRecipient);
        vm.startPrank(recipientWallet);
        vm.expectRevert(Errors.ZeroAmount.selector);
        uint256 claimedAmount = rewards.claim(recipient, v, r, s);
        vm.stopPrank();
    }

    function test_claimIncorrectSignature() public {
        IRewards.Recipient memory recipient;

        address user = address(0x3);

        recipient.chainId = block.chainid;
        recipient.cycle = 1;
        recipient.wallet = user;
        recipient.amount = 100;

        vaultToken.mint(address(rewards), 100);
        bytes32 hashedRecipient = rewards.genHash(recipient);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(newWallet, hashedRecipient);

        vm.startPrank(user);
        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidSigner.selector, newWalletPublicKey));
        uint256 claimedAmount = rewards.claim(recipient, v, r, s);
    }

    function test_claimInvalidChainId() public {
        recipient.chainId = block.chainid + 1;
        recipient.wallet = newWalletPublicKey;
        vaultToken.mint(address(rewards), 100);
        bytes32 hashedRecipient = rewards.genHash(recipient);
        rewards.setSigner(newWalletPublicKey);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(newWallet, hashedRecipient);
        vm.startPrank(newWalletPublicKey);
        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidChainId.selector, recipient.chainId));
        uint256 claimedAmount = rewards.claim(recipient, v, r, s);
    }

    function test_claimExcessAmount() public {
        uint256 base_amount = 100;

        recipient.amount = base_amount + 100;
        recipient.wallet = newWalletPublicKey;
        vaultToken.mint(address(rewards), base_amount);
        bytes32 hashedRecipient = rewards.genHash(recipient);
        rewards.setSigner(newWalletPublicKey);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(newWallet, hashedRecipient);
        vm.startPrank(newWalletPublicKey);
        vm.expectRevert(abi.encodeWithSelector(Errors.InsufficientBalance.selector, address(vaultToken)));
        uint256 claimedAmount = rewards.claim(recipient, v, r, s);
    }

    function test_claimForCorrectSignature(uint256 claimAmount) public {
        // address newWallet = address(0x3);
        vm.assume(claimAmount > 0);
        recipient.amount = claimAmount;

        vaultToken.mint(address(rewards), claimAmount);
        initialRewardsContractBalance = vaultToken.balanceOf(address(rewards));
        initialRecipientWalletBalance = vaultToken.balanceOf(recipientWallet);

        bytes32 hashedRecipient = rewards.genHash(recipient);
        rewards.setSigner(newWalletPublicKey);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(newWallet, hashedRecipient);
        vm.startPrank(address(systemRegistry.lmpVaultRouter()));
        uint256 claimedAmount = rewards.claimFor(recipient, v, r, s);
        assertEq(claimedAmount, recipient.amount);
        assertEq(vaultToken.balanceOf(address(rewards)), initialRewardsContractBalance - recipient.amount);
        assertEq(vaultToken.balanceOf(recipientWallet), initialRecipientWalletBalance + recipient.amount);
        vm.stopPrank();
    }
}
