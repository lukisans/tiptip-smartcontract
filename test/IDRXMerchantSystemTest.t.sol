// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import {MockToken} from "../src/mocks/MockToken.sol";
import {MockStakingIDRX} from "../src/mocks/MockStakingIDRX.sol";
import {FactoryMerchantPool} from "../src/core/FactoryMerchantPool.sol";
import {MerchantPool} from "../src/core/MerchantPool.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title IDRXMerchantSystemTest
 * @notice Comprehensive test suite for the IDRX Merchant System
 * @dev Tests all core functionality of the merchant pool system
 */
contract IDRXMerchantSystemTest is Test {
    // Contracts
    MockToken public token;
    MockStakingIDRX public stakingContract;
    FactoryMerchantPool public factory;

    // Actors
    address public deployer;
    address public platformOwner;
    address public merchant1;
    address public merchant2;
    address public customer1;
    address public customer2;

    // Constants
    uint256 public constant INITIAL_TOKEN_AMOUNT = 100_000_000 * 10 ** 18; // 10M tokens
    uint256 public constant TIP_AMOUNT = 100_000 * 10 ** 18; // 100K tokens
    uint256 public constant PREMIUM_STAKE_AMOUNT = 100_000_000 * 10 ** 18; // 10M tokens

    // Setup test environment
    function setUp() public {
        // Create actors with meaningful labels
        deployer = makeAddr("deployer");
        platformOwner = makeAddr("platformOwner");
        merchant1 = makeAddr("merchant1");
        merchant2 = makeAddr("merchant2");
        customer1 = makeAddr("customer1");
        customer2 = makeAddr("customer2");

        // Set deployer as active account
        vm.startPrank(deployer);

        // Deploy contracts
        token = new MockToken("Mock IDRX Token", "mIDRX", 18);
        stakingContract = new MockStakingIDRX(address(token));
        factory = new FactoryMerchantPool(address(token), address(stakingContract), platformOwner);

        // Distribute tokens for testing
        token.mint(merchant1, INITIAL_TOKEN_AMOUNT);
        token.mint(merchant2, INITIAL_TOKEN_AMOUNT);
        token.mint(customer1, INITIAL_TOKEN_AMOUNT);
        token.mint(customer2, INITIAL_TOKEN_AMOUNT);
        token.mint(address(stakingContract), INITIAL_TOKEN_AMOUNT * 10);

        vm.stopPrank();
    }

    // Test factory deployment and initial configuration
    function testFactoryDeployment() public view {
        assertEq(factory.token(), address(token), "IDRX token address mismatch");
        assertEq(factory.stakingContract(), address(stakingContract), "Staking contract address mismatch");
        assertEq(factory.platformAddress(), platformOwner, "Platform owner address mismatch");
        assertEq(factory.defaultBaseFee(), 400, "Default base fee should be 4%");
        assertTrue(
            address(factory.merchantPoolImplementation()) != address(0), "Implementation address should not be zero"
        );
    }

    // Test merchant pool creation
    function testMerchantPoolCreation() public {
        // Create merchant pool for merchant1
        vm.prank(deployer);
        address poolAddress = factory.createMerchantPool(merchant1);

        // Verify pool creation
        assertTrue(poolAddress != address(0), "Pool address should not be zero");
        assertTrue(factory.hasMerchantPool(merchant1), "Factory should recognize merchant1 has a pool");
        assertEq(factory.getMerchantPool(merchant1), poolAddress, "getMerchantPool should return correct address");

        // Verify pool initialization
        MerchantPool pool = MerchantPool(poolAddress);
        assertEq(pool.merchantOwnerAddress(), merchant1, "Pool merchant owner should be merchant1");
        assertEq(pool.platformAddress(), platformOwner, "Pool platform address should be platformOwner");
        assertEq(address(pool.stakingContract()), address(stakingContract), "Pool staking contract should match");
        assertEq(address(pool.token()), address(token), "Pool IDRX token should match");
        assertEq(pool.baseFee(), factory.defaultBaseFee(), "Pool base fee should match factory default");
        assertEq(pool.owner(), merchant1, "Pool owner should be merchant1");
    }

    // Test creating multiple merchant pools
    function testCreateMultipleMerchantPools() public {
        vm.startPrank(deployer);

        // Create pools for both merchants
        address pool1 = factory.createMerchantPool(merchant1);
        address pool2 = factory.createMerchantPool(merchant2);

        // Verify different addresses
        assertTrue(pool1 != pool2, "Different merchants should get different pools");

        // Verify bulk get function
        address[] memory merchants = new address[](2);
        merchants[0] = merchant1;
        merchants[1] = merchant2;

        address[] memory pools = factory.getMerchantPools(merchants);
        assertEq(pools[0], pool1, "First pool address should match");
        assertEq(pools[1], pool2, "Second pool address should match");

        vm.stopPrank();
    }

    // Test merchant pool creation failures
    function testRevertMerchantPoolCreationWhenAlreadyHavePoolAndWhenAddressIsZero() public {
        // Test duplicate merchant
        vm.startPrank(deployer);
        factory.createMerchantPool(merchant1);

        // This should fail
        vm.expectRevert(FactoryMerchantPool.FactoryMerchantPool__merchantAlreadyHasPool.selector);
        factory.createMerchantPool(merchant1);

        // Test zero address merchant
        vm.expectRevert(FactoryMerchantPool.FactoryMerchantPool__merchantAddressCannotBeZero.selector);
        factory.createMerchantPool(address(0));

        vm.stopPrank();
    }

    // Test updating default fee
    function testUpdateDefaultFee() public {
        uint96 newFee = 450; // 5%

        // Only owner should be able to update fee
        vm.prank(merchant1);
        vm.expectRevert();
        factory.updateDefaultFee(newFee);

        // Owner updates fee
        vm.prank(deployer);
        factory.updateDefaultFee(newFee);

        // Verify fee update
        assertEq(factory.defaultBaseFee(), newFee, "Default fee should be updated");

        // Test fee limit
        vm.prank(deployer);
        vm.expectRevert();
        factory.updateDefaultFee(10001); // 100.01% should fail
    }

    // Test tipping functionality
    function testTipping() public {
        // Setup merchant pool
        vm.prank(deployer);
        address poolAddress = factory.createMerchantPool(merchant1);
        MerchantPool pool = MerchantPool(poolAddress);

        // Get initial balances
        uint256 initialMerchantBalance = token.balanceOf(merchant1);
        uint256 initialPlatformBalance = token.balanceOf(platformOwner);

        // Customer approves and tips
        vm.startPrank(customer1);
        token.approve(poolAddress, TIP_AMOUNT);
        pool.tip(TIP_AMOUNT);
        vm.stopPrank();

        // Calculate expected fee and merchant amount
        uint256 feeRate = pool.getCurrentFeeRate();
        uint256 expectedFee = (TIP_AMOUNT * feeRate) / 10000;
        uint256 expectedMerchantAmount = TIP_AMOUNT - expectedFee;

        // Verify balances after tip
        assertEq(
            token.balanceOf(merchant1),
            initialMerchantBalance + expectedMerchantAmount,
            "Merchant should receive tip minus fee"
        );
        assertEq(token.balanceOf(platformOwner), initialPlatformBalance + expectedFee, "Platform should receive fee");

        // Verify volume tracking
        assertEq(uint256(pool.totalVolumeProcessed()), TIP_AMOUNT, "Volume should be tracked correctly");
    }

    // Test premium staking functionality
    function testPremiumStaking() public {
        // Setup merchant pool
        vm.prank(deployer);
        address poolAddress = factory.createMerchantPool(merchant1);
        MerchantPool pool = MerchantPool(poolAddress);

        // Verify initial premium status
        assertFalse(pool.hasPremium(), "Should not have premium initially");

        // Initial fee should be standard rate
        assertEq(pool.getCurrentFeeRate(), pool.baseFee(), "Initial fee should be base fee");

        // Merchant stakes for premium
        vm.startPrank(merchant1);
        token.approve(poolAddress, PREMIUM_STAKE_AMOUNT);
        pool.stakeForPremium(PREMIUM_STAKE_AMOUNT, 0); // 30-day stake
        vm.stopPrank();

        // Verify premium status
        assertTrue(pool.hasPremium(), "Should have premium after staking");

        // Fee should be reduced to premium rate
        assertEq(pool.getCurrentFeeRate(), 100, "Fee should be reduced to premium rate (1%)");

        // Advance time past premium period
        uint256 stakeExpiry = pool.merchantStakingExpiry();
        vm.warp(stakeExpiry + 1);

        // Verify premium expired
        assertFalse(pool.hasPremium(), "Premium should expire after stake period");

        // Fee should return to standard
        assertEq(pool.getCurrentFeeRate(), pool.baseFee(), "Fee should return to standard after premium expires");
    }

    // Test stake withdrawal functionality
    function testStakeWithdrawal() public {
        // Setup merchant pool
        vm.prank(deployer);
        address poolAddress = factory.createMerchantPool(merchant1);
        MerchantPool pool = MerchantPool(poolAddress);

        // Merchant stakes for premium
        vm.startPrank(merchant1);
        token.approve(poolAddress, PREMIUM_STAKE_AMOUNT);
        pool.stakeForPremium(PREMIUM_STAKE_AMOUNT, 0); // 30-day stake

        // Record staking ID and expiry
        uint256 stakeExpiry = pool.merchantStakingExpiry();

        // Try to withdraw before expiry (should fail)
        vm.expectRevert(MerchantPool.MerchantPool__stakePeriodNotYetReachExpiry.selector);
        pool.withdrawStake();

        // Advance time past stake period
        vm.warp(stakeExpiry + 1);

        // Get balances before withdrawal
        uint256 merchantBalanceBefore = token.balanceOf(merchant1);
        uint256 platformBalanceBefore = token.balanceOf(platformOwner);

        // Withdraw stake
        pool.withdrawStake();
        vm.stopPrank();

        // Verify stake ID and expiry are reset
        assertEq(pool.merchantStakingId(), 0, "Stake ID should be reset");
        assertEq(pool.merchantStakingExpiry(), 0, "Stake expiry should be reset");

        // Verify merchant received principal and most rewards
        assertTrue(
            token.balanceOf(merchant1) > merchantBalanceBefore + PREMIUM_STAKE_AMOUNT,
            "Merchant should receive principal plus some rewards"
        );

        // Verify platform received some rewards
        assertTrue(token.balanceOf(platformOwner) > platformBalanceBefore, "Platform should receive some rewards");
    }

    // Test volume discount effect on fees
    function testVolumeDiscount() public {
        // Setup merchant pool
        vm.prank(deployer);
        address poolAddress = factory.createMerchantPool(merchant1);
        MerchantPool pool = MerchantPool(poolAddress);

        // Initial fee should be base fee (400 = 4%)
        assertEq(pool.getCurrentFeeRate(), 400, "Initial fee should be base fee");

        // Process large volume to trigger volume discount
        uint256 largeVolume = 1_000_000 * 10 ** 18; // 1M tokens

        // Manually set volume processed (for testing)
        _simulateVolume(customer1, poolAddress, largeVolume);

        // Fee should now be reduced by 10 basis points (3.9%)
        assertEq(pool.getCurrentFeeRate(), 390, "Fee should be reduced after volume discount");

        _simulateVolume(customer1, poolAddress, largeVolume * 4);

        // Fee should now be reduced by 50 basis points (3.5%)
        assertEq(pool.getCurrentFeeRate(), 350, "Fee should be further reduced after more volume");

        _simulateVolume(customer1, poolAddress, largeVolume * 15);

        // Fee should now be reduced by 50 basis points (3.5%)
        assertEq(pool.getCurrentFeeRate(), 200, "Fee should be further reduced after more volume");

        _simulateVolume(customer1, poolAddress, largeVolume * 1);

        // Fee should now be reduced by 50 basis points (3.5%)
        assertEq(pool.getCurrentFeeRate(), 200, "Fee should not be further reduced after reach 2%");
    }

    // Test error cases for premium staking
    function testPremiumStakingErrors() public {
        // Setup merchant pool
        vm.prank(deployer);
        address poolAddress = factory.createMerchantPool(merchant1);
        MerchantPool pool = MerchantPool(poolAddress);

        // Try to stake below minimum
        vm.startPrank(merchant1);
        token.approve(poolAddress, 1_000_000 * 10 ** 18); // Only 1M tokens

        vm.expectRevert(MerchantPool.MerchantPool__stakeNotMeetMinimalAmount.selector);
        pool.stakeForPremium(1_000_000 * 10 ** 18, 0);

        // Try invalid stake type
        token.approve(poolAddress, PREMIUM_STAKE_AMOUNT);
        vm.expectRevert(MerchantPool.MerchantPool__invalidStakeType.selector);
        pool.stakeForPremium(PREMIUM_STAKE_AMOUNT, 4); // Invalid type

        vm.stopPrank();
    }

    function _simulateVolume(address from, address to, uint256 volume) internal {
        vm.startPrank(from);
        token.approve(to, volume);
        MerchantPool(to).tip(volume);
        vm.stopPrank();
    }
}
