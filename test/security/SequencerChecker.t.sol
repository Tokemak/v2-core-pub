// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity 0.8.17;

import { Test } from "forge-std/Test.sol";
import { Errors } from "src/utils/Errors.sol";
import { ISystemRegistry } from "src/interfaces/ISystemRegistry.sol";
import { SequencerChecker, IAggregatorV3Interface } from "src/security/SequencerChecker.sol";

// solhint-disable func-name-mixedcase,const-name-snakecase

contract SequencerCheckerTest is Test {
    SequencerChecker public checker;
    ISystemRegistry public registry;
    address public baseFeed;

    function setUp() public virtual {
        baseFeed = makeAddr("BASE_SEQUENCER_FEED");
        registry = ISystemRegistry(makeAddr("SYSTEM_REGISTRY"));
        checker = new SequencerChecker(registry, IAggregatorV3Interface(baseFeed));
    }
}

contract ConstructorTests is SequencerCheckerTest {
    function test_RevertIf_SequencerFeedZero() public {
        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "_sequencerUptimeFeed"));
        new SequencerChecker(registry, IAggregatorV3Interface(address(0)));
    }

    function test_sequencerUptimeFeed_Set() public {
        assertEq(address(checker.sequencerUptimeFeed()), baseFeed);
    }
}

contract CheckSequencerUptimeFeedTests is SequencerCheckerTest {
    uint80 public constant mockedRoundId = 100;
    int256 public constant mockedAnswer = 0; // true
    uint256 public constant mockedStartedAt = 1000;

    function setUp() public override {
        super.setUp();
        vm.warp(100_000);
    }

    function test_RevertsIf_AnswerGtOne() public {
        _mockFeedReturn(mockedRoundId, 2, mockedStartedAt);
        vm.expectRevert(Errors.InvalidDataReturned.selector);
        checker.checkSequencerUptimeFeed();
    }

    function test_RevertIf_roundId_Zero() public {
        _mockFeedReturn(0, mockedAnswer, mockedStartedAt);
        vm.expectRevert(Errors.InvalidDataReturned.selector);
        checker.checkSequencerUptimeFeed();
    }

    function test_RevertIf_startedAt_Zero() public {
        _mockFeedReturn(mockedRoundId, mockedAnswer, 0);
        vm.expectRevert(Errors.InvalidDataReturned.selector);
        checker.checkSequencerUptimeFeed();
    }

    function test_AnswerOfOne_ReturnsFalse() public {
        _mockFeedReturn(mockedRoundId, 1, mockedStartedAt);
        bool returnVal = checker.checkSequencerUptimeFeed();
        assertEq(returnVal, false);
    }

    function test_AnswerOfZero_WithoutGracePeriodPassing_ReturnsFalse() public {
        _mockFeedReturn(mockedRoundId, mockedAnswer, block.timestamp - 1);
        bool returnVal = checker.checkSequencerUptimeFeed();
        assertEq(returnVal, false);
    }

    function test_AnswerZero_StartedAtCorrect_ReturnsTrue() public {
        _mockFeedReturn(mockedRoundId, mockedAnswer, block.timestamp - (checker.GRACE_PERIOD() + 10_000));
        bool returnVal = checker.checkSequencerUptimeFeed();
        assertEq(returnVal, true);
    }

    function _mockFeedReturn(uint80 roundId, int256 answer, uint256 startedAt) private {
        vm.mockCall(
            baseFeed,
            abi.encodeWithSelector(IAggregatorV3Interface.latestRoundData.selector),
            abi.encode(roundId, answer, startedAt, 1, 1)
        );
    }
}
