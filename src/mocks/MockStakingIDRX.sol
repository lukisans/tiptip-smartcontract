// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IStakingIDRX} from "../interfaces/IStakingIDRX.sol";

/**
 * @title MockStakingIDRX
 * @dev Mock staking contract for IDRX token with custom error handling
 */
contract MockStakingIDRX is IStakingIDRX, Ownable {
    using SafeERC20 for IERC20;

    // Immutable storage for gas savings
    IERC20 public immutable token;

    // Counters
    uint256 public stakeCount;
    uint256 public unbondingPeriod = 7 days;

    // Stake types with APR configurations
    mapping(uint256 => StakeType) public override stakeTypes;
    mapping(uint256 => Stake) public stakes;

    // --- Errors ---
    error MockStakingIDRX__StakeAmountZero();
    error MockStakingIDRX__InvalidStakeType();
    error MockStakingIDRX__StakeTypeNotConfigured();
    error MockStakingIDRX__NotStakeOwner(address);
    error MockStakingIDRX__StakeNotActive();
    error MockStakingIDRX__StakeStillLocked();
    error MockStakingIDRX__RewardAlreadyClaimed();
    error MockStakingIDRX__AlreadyUnbonding();
    error MockStakingIDRX__StakeAlreadyUnlocked();
    error MockStakingIDRX__NotInUnbonding();
    error MockStakingIDRX__UnbondingNotOver();
    error MockStakingIDRX__ETHTransferFailed();

    // --- Events ---
    event addNewStake(
        uint256 stakeId,
        uint256 stakeType,
        address staker,
        uint256 stakeAmount,
        uint256 rewardAmount,
        uint256 createdTimestamp,
        uint256 unlockTimestamp
    );

    event claimReward(uint256 stakeId, address staker, uint256 claimedAmount, uint256 claimedTimestamp);
    event stakeUnbonded(uint256 stakeId, uint256 unbondingTimestamp);
    event withdrawPrincipal(uint256 stakeId, address staker, uint256 principalAmount, uint256 claimedTimestamp);
    event withdrawPrincipalUnbonded(uint256 stakeId, address staker, uint256 principalAmount, uint256 claimedTimestamp);
    event stakeTypeModified(uint256 index, uint256 rewardModifier, uint256 durationModifier, uint256 duration);
    event newUnbondingPeriod(uint256 p);

    constructor(address _token) Ownable(msg.sender) {
        token = IERC20(_token);

        setStakeType(0, 380, 100, 30 days);
        setStakeType(1, 400, 100, 90 days);
        setStakeType(2, 432, 100, 180 days);
        setStakeType(3, 456, 100, 365 days);

        // Make to 1, 0 is sign of has no staking
        stakeCount = 1;
    }

    function isStakingContract() external pure returns (bool) {
        return true;
    }

    function implementation() external view returns (address) {
        return address(this);
    }

    function stakeToken() external view override returns (address) {
        return address(token);
    }

    function owner() public view override returns (address) {
        return Ownable.owner();
    }

    function newStake(uint256 amount, uint256 stakeType) external override {
        if (amount == 0) revert MockStakingIDRX__StakeAmountZero();
        if (stakeType >= 4) revert MockStakingIDRX__InvalidStakeType();

        StakeType memory sType = stakeTypes[stakeType];
        if (sType.duration == 0) revert MockStakingIDRX__StakeTypeNotConfigured();

        token.safeTransferFrom(msg.sender, address(this), amount);

        uint256 rewardAmount = calculateReward(amount, sType.rewardModifier, sType.duration);
        uint256 unlockTime = block.timestamp + sType.duration;
        uint256 newStakeId = stakeCount;

        stakes[newStakeId] = Stake({
            stakeId: newStakeId,
            stakeType: stakeType,
            staker: msg.sender,
            isActive: true,
            isUnbonding: false,
            stakeAmount: amount,
            rewardAmount: rewardAmount,
            createdTimestamp: block.timestamp,
            claimedAmount: 0,
            claimedTimestamp: 0,
            unlockTimestamp: unlockTime,
            unbondingTimestamp: 0
        });

        unchecked {
            stakeCount++;
        }

        emit addNewStake(newStakeId, stakeType, msg.sender, amount, rewardAmount, block.timestamp, unlockTime);
    }

    function calculateReward(uint256 amount, uint256 rewardModifier, uint256 duration)
        internal
        pure
        returns (uint256)
    {
        unchecked {
            return (amount * rewardModifier * duration) / (10000 * 365 days);
        }
    }

    function claimStakeReward(uint256 stakeId) external override {
        Stake storage stake = stakes[stakeId];

        if (stake.staker != msg.sender) revert MockStakingIDRX__NotStakeOwner(stake.staker);
        if (!stake.isActive) revert MockStakingIDRX__StakeNotActive();
        if (block.timestamp < stake.unlockTimestamp) revert MockStakingIDRX__StakeStillLocked();
        if (stake.claimedAmount > 0) revert MockStakingIDRX__RewardAlreadyClaimed();

        stake.claimedAmount = stake.rewardAmount;
        stake.claimedTimestamp = block.timestamp;

        token.safeTransfer(msg.sender, stake.rewardAmount);

        emit claimReward(stakeId, msg.sender, stake.rewardAmount, block.timestamp);
    }

    function claimStakePrincipal(uint256 stakeId) external override {
        Stake storage stake = stakes[stakeId];

        if (stake.staker != msg.sender) revert MockStakingIDRX__NotStakeOwner(stake.staker);
        if (!stake.isActive) revert MockStakingIDRX__StakeNotActive();
        if (block.timestamp < stake.unlockTimestamp) revert MockStakingIDRX__StakeStillLocked();

        uint256 principalAmount = stake.stakeAmount;

        stake.isActive = false;

        token.safeTransfer(msg.sender, principalAmount);

        emit withdrawPrincipal(stakeId, msg.sender, principalAmount, block.timestamp);
    }

    function unbondStake(uint256 stakeId) external {
        Stake storage stake = stakes[stakeId];

        if (stake.staker != msg.sender) revert MockStakingIDRX__NotStakeOwner(stake.staker);
        if (!stake.isActive) revert MockStakingIDRX__StakeNotActive();
        if (stake.isUnbonding) revert MockStakingIDRX__AlreadyUnbonding();
        if (block.timestamp >= stake.unlockTimestamp) revert MockStakingIDRX__StakeAlreadyUnlocked();

        stake.isUnbonding = true;
        stake.unbondingTimestamp = block.timestamp + unbondingPeriod;

        emit stakeUnbonded(stakeId, stake.unbondingTimestamp);
    }

    function claimStakePrincipalUnbonded(uint256 stakeId) external {
        Stake storage stake = stakes[stakeId];

        if (stake.staker != msg.sender) revert MockStakingIDRX__NotStakeOwner(stake.staker);
        if (!stake.isActive) revert MockStakingIDRX__StakeNotActive();
        if (!stake.isUnbonding) revert MockStakingIDRX__NotInUnbonding();
        if (block.timestamp < stake.unbondingTimestamp) revert MockStakingIDRX__UnbondingNotOver();

        uint256 principalAmount = stake.stakeAmount;

        stake.isActive = false;
        stake.isUnbonding = false;

        token.safeTransfer(msg.sender, principalAmount);

        emit withdrawPrincipalUnbonded(stakeId, msg.sender, principalAmount, block.timestamp);
    }

    function getStake(uint256[] calldata stakeIds) external view override returns (Stake[] memory) {
        Stake[] memory result = new Stake[](stakeIds.length);

        for (uint256 i = 0; i < stakeIds.length; i++) {
            result[i] = stakes[stakeIds[i]];
        }

        return result;
    }

    function setStakeType(uint256 index, uint256 rewardModifier, uint256 durationModifier, uint256 duration)
        public
        onlyOwner
    {
        stakeTypes[index] =
            StakeType({rewardModifier: rewardModifier, durationModifier: durationModifier, duration: duration});

        emit stakeTypeModified(index, rewardModifier, durationModifier, duration);
    }

    function setUnbondingPeriod(uint256 p) external onlyOwner {
        unbondingPeriod = p;
        emit newUnbondingPeriod(p);
    }

    function withdraw(address payable to) external onlyOwner {
        (bool success,) = to.call{value: address(this).balance}("");
        if (!success) revert MockStakingIDRX__ETHTransferFailed();
    }

    function withdrawToken(address tokenAddress, address to, uint256 amount) external onlyOwner {
        IERC20(tokenAddress).safeTransfer(to, amount);
    }

    receive() external payable {}
}
