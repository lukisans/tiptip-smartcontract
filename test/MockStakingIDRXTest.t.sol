// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "../src/mocks/MockToken.sol";
import "../src/mocks/MockStakingIDRX.sol";

contract MockStakingIDRXTest is Test {
    MockToken public token;
    MockStakingIDRX public staking;

    address public deployer;
    address public user1;
    address public user2;

    uint256 STAKING_REWARD_BANK = 10_000_000 * 1e18;

    // Setup test environment
    function setUp() public {
        deployer = address(this);
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");

        // Deploy token
        token = new MockToken("Mock IDRX Token", "mIDRX", 18);

        // Deploy staking contract
        staking = new MockStakingIDRX(address(token));

        // Allocate tokens for testing
        token.mint(user1, 1_000_000 * 1e18);
        token.mint(user2, 500_000 * 1e18);
        token.mint(address(staking), STAKING_REWARD_BANK);
    }

    // Test creating a new stake
    function testNewStake() public {
        uint256 stakeAmount = 100_000 * 1e18;
        uint256 stakeType = 0; // 1 month

        // Approve tokens for staking
        vm.startPrank(user1);
        token.approve(address(staking), stakeAmount);

        // Create stake
        staking.newStake(stakeAmount, stakeType);
        vm.stopPrank();

        // Check stake count increased
        assertEq(staking.stakeCount(), 2);

        // Check stake details
        uint256[] memory stakeIds = new uint256[](1);
        stakeIds[0] = 1;

        IStakingIDRX.Stake[] memory stakes = staking.getStake(stakeIds);
        IStakingIDRX.Stake memory stake = stakes[0];

        assertEq(stake.stakeId, 1);
        assertEq(stake.stakeType, stakeType);
        assertEq(stake.staker, user1);
        assertTrue(stake.isActive);
        assertFalse(stake.isUnbonding);
        assertEq(stake.stakeAmount, stakeAmount);

        // Check token transfer occurred
        assertEq(token.balanceOf(address(staking)), stakeAmount + STAKING_REWARD_BANK);
        assertEq(token.balanceOf(user1), 900_000 * 1e18);
    }

    // Test stake rewards calculation (1 month stake)
    function testStakeReward() public {
        uint256 stakeAmount = 1_000_000 * 1e18;
        uint256 stakeType = 0; // 1 month

        // Get stake type details
        (uint256 rewardModifier,, uint256 duration) = staking.stakeTypes(stakeType);

        // Calculate expected reward (similar to contract calculation)
        uint256 expectedReward = stakeAmount * rewardModifier * duration / (10000 * 365 days);

        // Create stake
        vm.startPrank(user1);
        token.approve(address(staking), stakeAmount);
        staking.newStake(stakeAmount, stakeType);
        vm.stopPrank();

        // Check reward matches expected
        uint256[] memory stakeIds = new uint256[](1);
        stakeIds[0] = 1;

        IStakingIDRX.Stake[] memory stakes = staking.getStake(stakeIds);
        IStakingIDRX.Stake memory stake = stakes[0];

        assertEq(stake.rewardAmount, expectedReward);
    }

    // Test claiming rewards after lock period
    function testClaimStakeReward() public {
        uint256 stakeAmount = 1_000_000 * 1e18;
        uint256 stakeType = 0; // 1 month

        // Create stake
        vm.startPrank(user1);
        token.approve(address(staking), stakeAmount);
        staking.newStake(stakeAmount, stakeType);

        // Fast forward past lock period
        (,, uint256 duration) = staking.stakeTypes(stakeType);
        vm.warp(block.timestamp + duration + 1);

        // Get expected reward
        uint256[] memory stakeIds = new uint256[](1);
        stakeIds[0] = 1;
        IStakingIDRX.Stake[] memory stakes = staking.getStake(stakeIds);
        uint256 expectedReward = stakes[0].rewardAmount;

        // Record balance before claim
        uint256 balanceBefore = token.balanceOf(user1);

        // Claim reward
        staking.claimStakeReward(1);
        vm.stopPrank();

        // Check rewards claimed
        uint256 balanceAfter = token.balanceOf(user1);
        assertEq(balanceAfter - balanceBefore, expectedReward);

        // Verify stake state
        stakes = staking.getStake(stakeIds);
        assertEq(stakes[0].claimedAmount, expectedReward);
        assertTrue(stakes[0].claimedTimestamp > 0);
    }

    // Test claiming principal after lock period
    function testClaimStakePrincipal() public {
        uint256 stakeAmount = 1_000_000 * 1e18;
        uint256 stakeType = 0; // 1 month

        // Create stake
        vm.startPrank(user1);
        token.approve(address(staking), stakeAmount);
        staking.newStake(stakeAmount, stakeType);

        // Fast forward past lock period
        (,, uint256 duration) = staking.stakeTypes(stakeType);
        vm.warp(block.timestamp + duration + 1);

        // Record balance before claim
        uint256 balanceBefore = token.balanceOf(user1);

        // Claim principal
        staking.claimStakePrincipal(1);
        vm.stopPrank();

        // Check principal returned
        uint256 balanceAfter = token.balanceOf(user1);
        assertEq(balanceAfter - balanceBefore, stakeAmount);

        // Verify stake state
        uint256[] memory stakeIds = new uint256[](1);
        stakeIds[0] = 1;
        IStakingIDRX.Stake[] memory stakes = staking.getStake(stakeIds);
        assertFalse(stakes[0].isActive);
    }

    // Test unbonding before lock period
    function testUnbondStake() public {
        uint256 stakeAmount = 1_000_000 * 1e18;
        uint256 stakeType = 2; // 6 months

        // Create stake
        vm.startPrank(user1);
        token.approve(address(staking), stakeAmount);
        staking.newStake(stakeAmount, stakeType);

        // Unbond after 1 month
        vm.warp(block.timestamp + 30 days);
        staking.unbondStake(1);

        // Check stake state
        uint256[] memory stakeIds = new uint256[](1);
        stakeIds[0] = 1;
        IStakingIDRX.Stake[] memory stakes = staking.getStake(stakeIds);
        assertTrue(stakes[0].isUnbonding);
        assertEq(stakes[0].unbondingTimestamp, block.timestamp + staking.unbondingPeriod());

        // Wait for unbonding period
        vm.warp(block.timestamp + staking.unbondingPeriod() + 1);

        // Claim unbonded principal
        staking.claimStakePrincipalUnbonded(1);
        vm.stopPrank();

        // Check principal returned and state updated
        stakes = staking.getStake(stakeIds);
        assertFalse(stakes[0].isActive);
        assertFalse(stakes[0].isUnbonding);
    }

    // Test owner functions
    function testSetStakeType() public {
        // Only owner can set stake types
        uint256 newRewardModifier = 500; // 5%
        uint256 newDurationModifier = 150;
        uint256 newDuration = 120 days;

        staking.setStakeType(4, newRewardModifier, newDurationModifier, newDuration);

        // Check stake type updated
        (uint256 rewardMod, uint256 durationMod, uint256 duration) = staking.stakeTypes(4);
        assertEq(rewardMod, newRewardModifier);
        assertEq(durationMod, newDurationModifier);
        assertEq(duration, newDuration);
    }

    // Test non-owner cannot set stake types
    function testNonOwnerCannotSetStakeType() public {
        vm.prank(user1);
        vm.expectRevert();
        staking.setStakeType(4, 500, 150, 120 days);
    }
}
