// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

// adapted from
// https://github.com/convex-eth/platform/blob/main/contracts/contracts/VirtualBalanceRewardPool.sol

import "./Interfaces.sol";
import { IERC20 } from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";

contract VirtualBalanceWrapper {
    using SafeERC20 for IERC20;

    IDeposit public deposits;

    function totalSupply() public view returns (uint256) {
        return deposits.totalSupply();
    }

    function balanceOf(address account) public view returns (uint256) {
        return deposits.balanceOf(account);
    }
}

/// @notice No permissions and loose behaviors around staking/withdrawing for others. Testing only
contract VirtualBalanceRewardPool is VirtualBalanceWrapper {
    using SafeERC20 for IERC20;

    IERC20 public rewardToken;
    uint256 public constant duration = 7 days;

    uint256 public periodFinish = 0;
    uint256 public rewardRate = 0;
    uint256 public lastUpdateTime;
    uint256 public rewardPerTokenStored;
    uint256 public queuedRewards = 0;
    uint256 public currentRewards = 0;
    uint256 public historicalRewards = 0;
    uint256 public newRewardRatio = 830;
    mapping(address => uint256) public userRewardPerTokenPaid;
    mapping(address => uint256) public rewards;

    event RewardAdded(uint256 reward);
    event Staked(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event RewardPaid(address indexed user, uint256 reward);

    constructor(address deposit_, address reward_) {
        deposits = IDeposit(deposit_);
        rewardToken = IERC20(reward_);
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
        return min(block.timestamp, periodFinish);
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

    //update reward, emit, call linked reward's stake
    function stake(address _account, uint256 amount) external updateReward(_account) {
        require(msg.sender == address(deposits), "!authorized");
        // require(amount > 0, 'VirtualDepositRewardPool: Cannot stake 0');
        emit Staked(_account, amount);
    }

    function withdraw(address _account, uint256 amount) public updateReward(_account) {
        require(msg.sender == address(deposits), "!authorized");
        //require(amount > 0, 'VirtualDepositRewardPool : Cannot withdraw 0');

        emit Withdrawn(_account, amount);
    }

    function getReward(address _account) public updateReward(_account) {
        uint256 reward = earned(_account);
        if (reward > 0) {
            rewards[_account] = 0;
            rewardToken.safeTransfer(_account, reward);
            emit RewardPaid(_account, reward);
        }
    }

    function getReward() external {
        getReward(msg.sender);
    }

    function donate(uint256 _amount) external {
        IERC20(rewardToken).safeTransferFrom(msg.sender, address(this), _amount);
        queuedRewards = queuedRewards + _amount;
    }

    function queueNewRewards(uint256 _rewards) external {
        _rewards = _rewards + queuedRewards;

        if (block.timestamp >= periodFinish) {
            notifyRewardAmount(_rewards);
            queuedRewards = 0;
            return;
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
    }

    function notifyRewardAmount(uint256 reward) internal updateReward(address(0)) {
        historicalRewards = historicalRewards + reward;
        if (block.timestamp >= periodFinish) {
            rewardRate = reward / duration;
        } else {
            uint256 remaining = periodFinish - block.timestamp;
            uint256 leftover = remaining * rewardRate;
            reward = reward + leftover;
            rewardRate = reward / duration;
        }
        currentRewards = reward;
        lastUpdateTime = block.timestamp;
        periodFinish = block.timestamp + duration;
        emit RewardAdded(reward);
    }

    function min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }
}
