// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import "../src/mocks/MockIDRX.sol";
import "../src/mocks/MockStakingIDRX.sol";
import "../src/core/MerchantPool.sol";

contract MerchantPoolTest is Test {
    MockIDRX public token;
    MockStakingIDRX public staking;
    MerchantPool public pool;

    address public deployer;
    address public platform;
    address public merchant;
    address public tipper1;
    address public tipper2;

    uint96 public baseFee = 400; // 4%

    // Setup test environment
    function setUp() public {
        deployer = address(this);
        platform = makeAddr("platform");
        merchant = makeAddr("merchant");
        tipper1 = makeAddr("tipper1");
        tipper2 = makeAddr("tipper2");

        // Deploy token
        token = new MockIDRX();

        // Deploy staking contract
        staking = new MockStakingIDRX(address(token));

        // Deploy merchant pool
        MerchantPool merchantPoolImplementation = new MerchantPool();
        address newPool = Clones.clone(address(merchantPoolImplementation));
        pool = MerchantPool(newPool);

        MerchantPool(newPool).initialize(merchant, platform, address(token), address(staking), baseFee);

        // Allocate tokens for testing
        token.transfer(tipper1, 100_000 * 1e18);
        token.transfer(tipper2, 100_000 * 1e18);
        token.transfer(merchant, 50_000_000 * 1e18); // For staking
    }

    // Test basic tipping functionality
    function testTip() public {
        uint256 tipAmount = 1_000 * 1e18;
        uint256 expectedFee = tipAmount * baseFee / 10000; // 4% fee
        uint256 expectedMerchantAmount = tipAmount - expectedFee;

        // Initial balances
        uint256 platformBalanceBefore = token.balanceOf(platform);
        uint256 merchantBalanceBefore = token.balanceOf(merchant);

        // Tip
        vm.startPrank(tipper1);
        token.approve(address(pool), tipAmount);
        pool.tip(tipAmount);
        vm.stopPrank();

        // Check balances after tip
        assertEq(token.balanceOf(platform) - platformBalanceBefore, expectedFee);
        assertEq(token.balanceOf(merchant) - merchantBalanceBefore, expectedMerchantAmount);
    }

    // Test dynamic fee reduction with volume
    function testDynamicFeeReduction() public {
        // Tip 1,000,000 IDRX (threshold for 0.1% fee reduction)
        uint256 tipAmount = 1_000_000 * 1e18;

        vm.startPrank(tipper1);
        token.approve(address(pool), tipAmount);
        pool.tip(tipAmount);
        vm.stopPrank();

        // Check fee reduced to 3.9%
        uint256 expectedFeeRate = 390; // 3.9%
        assertEq(pool.getCurrentFeeRate(), expectedFeeRate);

        // Tip another 1,000,000 IDRX
        vm.startPrank(tipper2);
        token.approve(address(pool), tipAmount);
        pool.tip(tipAmount);
        vm.stopPrank();

        // Check fee reduced to 3.8%
        expectedFeeRate = 380; // 3.8%
        assertEq(pool.getCurrentFeeRate(), expectedFeeRate);
    }

    // Test premium fee with staking
    function testPremiumFeeWithStaking() public {
        // Merchant stakes 10M IDRX for premium (1% fee)
        uint256 stakeAmount = 10_000_000 * 1e18;
        uint256 stakeType = 0; // 1 month

        vm.startPrank(merchant);
        token.approve(address(pool), stakeAmount);
        pool.stakeForPremium(stakeAmount, stakeType);
        vm.stopPrank();

        // Verify premium status
        assertTrue(pool.hasPremium());
        assertEq(pool.getCurrentFeeRate(), 100); // 1% premium fee

        // Tip with premium fee
        uint256 tipAmount = 1_000 * 1e18;
        uint256 expectedFee = tipAmount * 100 / 10000; // 1% fee
        uint256 expectedMerchantAmount = tipAmount - expectedFee;

        // Initial balances
        uint256 platformBalanceBefore = token.balanceOf(platform);
        uint256 merchantBalanceBefore = token.balanceOf(merchant);

        // Tip
        vm.startPrank(tipper1);
        token.approve(address(pool), tipAmount);
        pool.tip(tipAmount);
        vm.stopPrank();

        // Check balances after tip
        assertEq(token.balanceOf(platform) - platformBalanceBefore, expectedFee);
        assertEq(token.balanceOf(merchant) - merchantBalanceBefore, expectedMerchantAmount);
    }

    // Test premium expiry
    function testPremiumExpiry() public {
        // Merchant stakes 10M IDRX for premium (1% fee)
        uint256 stakeAmount = 10_000_000 * 1e18;
        uint256 stakeType = 0; // 1 month

        (,, uint256 duration) = staking.stakeTypes(stakeType);

        vm.startPrank(merchant);
        token.approve(address(pool), stakeAmount);
        pool.stakeForPremium(stakeAmount, stakeType);
        vm.stopPrank();

        // Verify premium status
        assertTrue(pool.hasPremium());

        // Move forward past staking period
        vm.warp(block.timestamp + duration + 1);

        // Verify premium expired
        assertFalse(pool.hasPremium());
        assertEq(pool.getCurrentFeeRate(), baseFee); // Back to base fee
    }

    // Test stake withdrawal
    function testStakeWithdrawal() public {
        // Merchant stakes 10M IDRX
        uint256 stakeAmount = 10_000_000 * 1e18;
        uint256 stakeType = 0; // 1 month

        (,, uint256 duration) = staking.stakeTypes(stakeType);

        vm.startPrank(merchant);
        token.approve(address(pool), stakeAmount);
        pool.stakeForPremium(stakeAmount, stakeType);

        // Move forward past staking period
        vm.warp(block.timestamp + duration + 1);

        // Withdraw stake
        pool.withdrawStake();
        vm.stopPrank();

        // Verify stake withdrawn
        assertEq(pool.merchantStakingId(), 0);
        assertEq(pool.merchantStakingExpiry(), 0);
    }

    // Test minimum fee limit
    function testMinimumFeeLimit() public {
        // Tip enough to reduce fee below minimum (2%)
        uint256 tipAmount = 1_000_000 * 1e18;

        // Tip 20 times to reduce fee below minimum
        for (uint256 i = 0; i < 20; i++) {
            vm.startPrank(tipper1);
            token.approve(address(pool), tipAmount);
            pool.tip(tipAmount);
            vm.stopPrank();
        }

        // Fee should be capped at minimum 2%
        assertEq(pool.getCurrentFeeRate(), 200); // 2% minimum
    }
}
