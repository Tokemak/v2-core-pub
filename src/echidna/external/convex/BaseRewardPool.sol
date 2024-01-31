// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

/* solhint-disable func-name-mixedcase,max-line-length,const-name-snakecase,no-console */

import { IRewards } from "src/echidna/external/convex/Interfaces.sol";
import { IERC20 } from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";
import { console } from "forge-std/console.sol";
// adapted from:
// https://github.com/convex-eth/platform/blob/ad8f90a4df441c789d1f4163c5d99f7ccd67fd4e/contracts/contracts/BaseRewardPool.sol

/// @title Convex base rewarder
/// @notice No permissions and loose behaviors around staking/withdrawing for others. Testing only
contract BaseRewardPool {
    using SafeERC20 for IERC20;

    IERC20 public rewardToken;
    IERC20 public stakingToken;
    uint256 public constant duration = 7 days;

    uint256 public periodFinish = 0;
    uint256 public rewardRate = 0;
    uint256 public lastUpdateTime;
    uint256 public rewardPerTokenStored;
    uint256 public queuedRewards = 0;
    uint256 public currentRewards = 0;
    uint256 public historicalRewards = 0;
    uint256 public constant newRewardRatio = 830;
    uint256 private _totalSupply;
    mapping(address => uint256) public userRewardPerTokenPaid;
    mapping(address => uint256) public rewards;
    mapping(address => uint256) private _balances;

    address[] public extraRewards;

    event RewardAdded(uint256 reward);
    event Staked(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event RewardPaid(address indexed user, uint256 reward);

    constructor(address stakingToken_, address rewardToken_) {
        stakingToken = IERC20(stakingToken_);
        rewardToken = IERC20(rewardToken_);
    }

    function totalSupply() public view returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) public view returns (uint256) {
        return _balances[account];
    }

    function extraRewardsLength() public view returns (uint256) {
        return extraRewards.length;
    }

    function addExtraReward(address _reward) external returns (bool) {
        require(_reward != address(0), "!reward setting");

        extraRewards.push(_reward);
        return true;
    }

    function clearExtraRewards() external {
        delete extraRewards;
    }

    modifier updateReward(address account) {
        rewardPerTokenStored = rewardPerToken();
        lastUpdateTime = lastTimeRewardApplicable();
        if (account != address(0)) {
            rewards[account] = earned(account);
            userRewardPerTokenPaid[account] = rewardPerTokenStored;
        }
        _;
    }

    function lastTimeRewardApplicable() public view returns (uint256) {
        return block.timestamp < periodFinish ? block.timestamp : periodFinish;
    }

    function rewardPerToken() public view returns (uint256) {
        if (totalSupply() == 0) {
            return rewardPerTokenStored;
        }
        return
            rewardPerTokenStored + (((lastTimeRewardApplicable() - lastUpdateTime) * rewardRate * 1e18) / totalSupply());
    }

    function earned(address account) public view returns (uint256) {
        return ((balanceOf(account) * (rewardPerToken() - userRewardPerTokenPaid[account])) / 1e18) + rewards[account];
    }

    function stakeFor(address _for, uint256 _amount) public updateReward(_for) returns (bool) {
        require(_amount > 0, "RewardPool : Cannot stake 0");

        //also stake to linked rewards
        for (uint256 i = 0; i < extraRewards.length; i++) {
            IRewards(extraRewards[i]).stake(msg.sender, _amount);
        }

        //give to _for
        _totalSupply = _totalSupply + _amount;
        _balances[_for] = _balances[_for] + _amount;

        //take away from sender
        stakingToken.safeTransferFrom(msg.sender, address(this), _amount);
        emit Staked(_for, _amount);

        return true;
    }

    function withdrawFor(address _for, uint256 amount, bool claim) public updateReward(_for) returns (bool) {
        require(amount > 0, "RewardPool : Cannot withdraw 0");

        //also withdraw from linked rewards
        for (uint256 i = 0; i < extraRewards.length; i++) {
            IRewards(extraRewards[i]).withdraw(msg.sender, amount);
        }

        _totalSupply = _totalSupply - (amount);
        _balances[_for] = _balances[_for] - (amount);

        stakingToken.safeTransfer(_for, amount);
        emit Withdrawn(_for, amount);

        if (claim) {
            getReward(_for);
        }

        return true;
    }

    function getReward(address _account) public updateReward(_account) returns (bool) {
        uint256 reward = earned(_account);
        if (reward > 0) {
            rewards[_account] = 0;
            rewardToken.safeTransfer(_account, reward);
            emit RewardPaid(_account, reward);
        }

        return true;
    }

    function getReward() external returns (bool) {
        getReward(msg.sender);
        return true;
    }

    function donate(uint256 _amount) external returns (bool) {
        IERC20(rewardToken).safeTransferFrom(msg.sender, address(this), _amount);
        queuedRewards = queuedRewards + _amount;
        return true;
    }

    function queueNewRewards(uint256 _rewards) external returns (bool) {
        _rewards = _rewards + queuedRewards;

        if (block.timestamp >= periodFinish) {
            notifyRewardAmount(_rewards);
            queuedRewards = 0;
            return true;
        }

        //et = now - (finish-duration)
        uint256 elapsedTime = block.timestamp - (periodFinish - duration);
        //current at now: rewardRate * elapsedTime
        uint256 currentAtNow = rewardRate * elapsedTime;
        uint256 queuedRatio = currentAtNow * 1000 / _rewards;

        if (queuedRatio < newRewardRatio) {
            notifyRewardAmount(_rewards);
            queuedRewards = 0;
        } else {
            queuedRewards = _rewards;
        }
        return true;
    }

    function notifyRewardAmount(uint256 reward) internal updateReward(address(0)) {
        historicalRewards = historicalRewards + (reward);
        if (block.timestamp >= periodFinish) {
            rewardRate = reward / (duration);
        } else {
            uint256 remaining = periodFinish - block.timestamp;
            uint256 leftover = remaining * rewardRate;
            reward = reward + leftover;
            rewardRate = reward / duration;
        }
        if (rewardRate == 1) {
            console.log("rewardRate 1 ", reward, duration);
        }
        currentRewards = reward;
        lastUpdateTime = block.timestamp;
        periodFinish = block.timestamp + duration;
        emit RewardAdded(reward);
    }
}
