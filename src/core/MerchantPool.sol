// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IStakingIDRX} from "../interfaces/IStakingIDRX.sol";
import {Initializable} from "@openzeppelin-upgradeable/contracts/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin-upgradeable/contracts/access/OwnableUpgradeable.sol";

/**
 * @title MerchantPool
 * @notice This contract manages merchant-specific tipping and staking mechanics with IDRX tokens.
 *         Merchants can receive tips, stake tokens to obtain premium fee discounts, and withdraw funds.
 *         The platform collects a small portion of staking rewards as its fee.
 */
contract MerchantPool is Initializable, OwnableUpgradeable {
    using SafeERC20 for IERC20;

    // Constants
    uint256 private constant PREMIUM_TRESHOLD = 10_000_000 * 1e18;
    uint256 private constant VOLUME_TRESHOLD = 1_000_000 * 1e18;
    uint256 private constant FEE_DECREMENT = 10;
    uint256 private constant FEE_PRECISION = 10_000;
    uint256 private constant LIMIT_DECREAMENT_FEE = 200;
    uint256 private constant PREMIUM_FEE = 100;
    uint256 private constant PLATFORM_FIXED_APR = 300; // 3.00% APR for platform

    uint256 private constant MINIMAL_AMOUNT_TIP = 1_000;

    // Variables
    address public platformAddress;
    address public merchantOwnerAddress;
    IERC20 public token;
    IStakingIDRX public stakingContract;

    // Storage variables
    uint96 public baseFee;
    uint160 public totalVolumeProcessed;

    // Merchant staking
    uint256 public merchantStakingId;
    uint256 public merchantStakingExpiry;

    // Initialization flag
    bool private initialized;

    // Error custom
    error MerchantPool__merchantOwnerAddressCannotBeZero();
    error MerchantPool__platformAddressCannotBeZero();
    error MerchantPool__stakingContractAddressCannotBeZero();
    error MerchantPool__idrxAddressCannotBeZero();
    error MerchantPool__feeCannotExceed100Percent();
    error MerchantPool__stakeNotMeetMinimalAmount();
    error MerchantPool__invalidStakeType();
    error MerchantPool__noActiveStaking();
    error MerchantPool__stakePeriodNotYetReachExpiry();
    error MerchantPool__stakingNotFound();
    error MerchantPool__stakingNotActive();
    error MerchantPool__amountMustBeMoreThanZero();
    error MerchantPool__insufficientBalance();
    error MerchantPool__amountTipMustBeMoreThanMinimal();
    error MerchantPool__onlyPlatformOwnerCanAccess(address);
    error MerchantPool__alreadyInitialized();

    // Event
    event StakingDeposited(uint256 merchantStakeId, uint256 amount, uint256 stakeType, uint256 merchantStakeExpiry);
    event StakingWithdrawn(
        uint256 merchantStakingId, uint256 principalAmount, uint256 merchantReward, uint256 platformReward
    );
    event MerchantWithdrawal(uint256 amount);
    event TipReceived(address indexed from, uint256 amount, uint256 fee);
    event MerchantPoolInitialized(address merchant, address platform, address idrx, address staking, uint96 baseFee);

    // Modifier
    modifier onlyPlatformOwner() {
        if (msg.sender != platformAddress) revert MerchantPool__onlyPlatformOwnerCanAccess(msg.sender);
        _;
    }

    /**
     * @dev Empty constructor for proxy pattern
     * @dev Note: This leaves the contract uninitialized and requires a call to initialize()
     */
    constructor() {
        _disableInitializers();
    }

    /**
     * @dev Initializes the MerchantPool contract.
     * @param _merchant Merchant owner's address
     * @param _platform Platform's address to collect fees
     * @param _staking Address of the staking contract
     * @param _idrx Address of the IDRX token
     * @param _baseFee Initial base fee (scaled by FEE_PRECISION)
     */
    function initialize(address _merchant, address _platform, address _staking, address _idrx, uint96 _baseFee)
        external
        initializer
    {
        if (initialized) revert MerchantPool__alreadyInitialized();

        if (_merchant == address(0)) revert MerchantPool__merchantOwnerAddressCannotBeZero();
        if (_platform == address(0)) revert MerchantPool__platformAddressCannotBeZero();
        if (_staking == address(0)) revert MerchantPool__stakingContractAddressCannotBeZero();
        if (_idrx == address(0)) revert MerchantPool__idrxAddressCannotBeZero();
        if (_baseFee > FEE_PRECISION) revert MerchantPool__feeCannotExceed100Percent();

        __Ownable_init(msg.sender);

        merchantOwnerAddress = _merchant;
        platformAddress = _platform;
        token = IERC20(_idrx);
        stakingContract = IStakingIDRX(_staking);
        baseFee = _baseFee;

        _transferOwnership(_merchant);

        initialized = true;

        emit MerchantPoolInitialized(_merchant, _platform, _idrx, _staking, _baseFee);
    }

    /**
     * @dev Check if merchant has premium status
     * @return True if merchant has premium status
     */
    function hasPremium() public view returns (bool) {
        return block.timestamp < merchantStakingExpiry;
    }

    /**
     * @dev Get current fee rate
     * @return Currentfee rate (scaled by FEE_PRECISION)
     */
    function _computeFeeRate() internal returns (uint256) {
        uint256 feeRate = PREMIUM_FEE;
        if (!hasPremium()) {
            uint256 volumeDiscount = totalVolumeProcessed / VOLUME_TRESHOLD;
            totalVolumeProcessed = 0;

            unchecked {
                feeRate = baseFee == LIMIT_DECREAMENT_FEE
                    ? LIMIT_DECREAMENT_FEE
                    : baseFee - ((volumeDiscount * FEE_PRECISION) / 1_000);
            }
            baseFee = uint96(feeRate);
        }
        return feeRate;
    }

    /**
     * @dev Calculate fee based on platform rules
     * @param amount Amount to calculate fee for
     * @return fee Fee Amount
     */
    function calculateFee(uint256 amount) public returns (uint256) {
        uint256 feeRate = _computeFeeRate();
        return (amount * feeRate) / FEE_PRECISION;
    }

    /**
     * @dev Receive tip for merchant
     * @param amount Amount of IDRX tokens to tip
     */
    function tip(uint256 amount) external {
        if (amount == 0) revert MerchantPool__amountTipMustBeMoreThanMinimal();

        token.safeTransferFrom(msg.sender, address(this), amount);

        uint256 fee = calculateFee(amount);
        uint256 merchantAmount;

        unchecked {
            merchantAmount = amount - fee;
            totalVolumeProcessed += uint160(amount);
        }

        if (fee > 0) {
            token.safeTransfer(platformAddress, fee);
        }

        token.safeTransfer(merchantOwnerAddress, merchantAmount);
        emit TipReceived(msg.sender, amount, fee);
    }

    /**
     * @dev Stake tokens for premium merchant benefit
     * @param amount Amount of IDRX will be staked
     * @param stakeType Type of stake (0-3)
     */
    function stakeForPremium(uint256 amount, uint256 stakeType) external onlyOwner {
        if (amount < PREMIUM_TRESHOLD) revert MerchantPool__stakeNotMeetMinimalAmount();

        if (stakeType > 3) revert MerchantPool__invalidStakeType();

        (,, uint256 duration) = stakingContract.stakeTypes(stakeType);
        if (duration == 0) revert MerchantPool__invalidStakeType();

        token.safeTransferFrom(msg.sender, address(this), amount);
        token.safeIncreaseAllowance(address(stakingContract), amount);

        uint256 countStakeBefore = stakingContract.stakeCount();
        // Create new stake
        stakingContract.newStake(amount, stakeType);

        merchantStakingId = countStakeBefore;
        merchantStakingExpiry = block.timestamp + duration;

        emit StakingDeposited(merchantStakingId, amount, stakeType, merchantStakingExpiry);
    }

    /**
     * @dev Withdraw stake after expiry reach
     * Principal goes to merchant owner
     * Platform receives fixed 3% APR
     * Merchant receives the remaining reward
     */
    function withdrawStake() external onlyOwner {
        if (merchantStakingId == 0) revert MerchantPool__noActiveStaking();
        if (block.timestamp < merchantStakingExpiry) revert MerchantPool__stakePeriodNotYetReachExpiry();

        // Get staking info
        uint256[] memory stakedIdArray = new uint256[](1);
        stakedIdArray[0] = merchantStakingId;

        IStakingIDRX.Stake[] memory stakes = stakingContract.getStake(stakedIdArray);
        if (stakes.length == 0) revert MerchantPool__stakingNotFound();

        IStakingIDRX.Stake memory stake = stakes[0];
        if (!stake.isActive) revert MerchantPool__stakingNotActive();

        // Track initial balance before claiming
        uint256 initialBalance = token.balanceOf(address(this));

        // Claim rewards and principal from staking contract
        stakingContract.claimStakeReward(merchantStakingId);
        stakingContract.claimStakePrincipal(merchantStakingId);

        // Calculate amounts to distribute
        uint256 finalBalance = token.balanceOf(address(this));
        uint256 totalReceived = finalBalance - initialBalance;
        uint256 principalAmount = stake.stakeAmount;

        // Calculate platform reward based on fixed 3% APR
        uint256 stakeDuration = stake.unlockTimestamp - stake.createdTimestamp;
        uint256 platformReward = (principalAmount * PLATFORM_FIXED_APR * stakeDuration) / (10000 * 365 days);

        // Merchant gets the remaining rewards
        uint256 totalReward = totalReceived - principalAmount;
        uint256 merchantReward = totalReward > platformReward ? totalReward - platformReward : 0;

        // Reset staking variables
        merchantStakingId = 0;
        merchantStakingExpiry = 0;

        // Transfer principal and merchant's portion of rewards to merchant
        uint256 merchantAmount = principalAmount + merchantReward;
        if (merchantAmount > 0) {
            token.safeTransfer(merchantOwnerAddress, merchantAmount);
        }

        // Transfer platform's portion of rewards to platform
        if (platformReward > 0) {
            token.safeTransfer(platformAddress, platformReward);
        }

        emit StakingWithdrawn(merchantStakingId, principalAmount, merchantReward, platformReward);
    }

    /**
     * @dev Withdraw tokens from contract (only merchant can call)
     * @param amount Amount of withdraw
     */
    function withdraw(uint256 amount) external onlyOwner {
        if (amount == 0) revert MerchantPool__amountMustBeMoreThanZero();
        uint256 availableBalance = token.balanceOf(address(this));
        if (availableBalance < amount) revert MerchantPool__insufficientBalance();

        token.safeTransfer(merchantOwnerAddress, amount);
        emit MerchantWithdrawal(amount);
    }

    // Getter
    /**
     * @dev Get current fee rate
     * @return Currentfee rate (scaled by FEE_PRECISION)
     */
    function getCurrentFeeRate() external returns (uint256) {
        return _computeFeeRate();
    }
}
