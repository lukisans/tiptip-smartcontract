// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {MerchantPool} from "./MerchantPool.sol";

contract FactoryMerchantPool is Ownable {
    // Immutable addresses for cloning
    address public immutable merchantPoolImplementation;
    address public immutable token;
    address public immutable stakingContract;
    address public immutable platformAddress;

    uint96 public defaultBaseFee = 400; // 4% for all merchant except they buy premium

    // Mapping of deployed merchant pools
    mapping(address => address) public merchantToPool;

    // Error
    error FactoryMerchantPool__platformOwnerAddressCannotBeZero();
    error FactoryMerchantPool__stakingAddressCannotBeZero();
    error FactoryMerchantPool__idrxAddressCannotBeZero();
    error FactoryMerchantPool__merchantAddressCannotBeZero();
    error FactoryMerchantPool__merchantAlreadyHasPool();

    // Event
    event MerchantPoolCreated(address indexed merchantAddress, address indexed newPool);
    event DefaultFeeUpdated(uint96 newFee);

    /**
     * @dev Constructor
     * @param _idrx Address of IDRX Token
     * @param _staking Address Of Staking platform
     * @param _ownerPlatform Address of receive platform fee
     */
    constructor(address _idrx, address _staking, address _ownerPlatform) Ownable(msg.sender) {
        if (_ownerPlatform == address(0)) revert FactoryMerchantPool__platformOwnerAddressCannotBeZero();

        if (_staking == address(0)) revert FactoryMerchantPool__stakingAddressCannotBeZero();

        if (_idrx == address(0)) revert FactoryMerchantPool__idrxAddressCannotBeZero();

        merchantPoolImplementation = address(new MerchantPool());
        token = _idrx;
        stakingContract = _staking;
        platformAddress = _ownerPlatform;
    }

    /**
     * @dev Create a new merchant pool
     * @param merchant Address of the merchant/content creator
     * @return Address of new created merchant pool
     */
    function createMerchantPool(address merchant) external returns (address) {
        if (merchant == address(0)) revert FactoryMerchantPool__merchantAddressCannotBeZero();

        if (merchantToPool[merchant] != address(0)) revert FactoryMerchantPool__merchantAlreadyHasPool();

        address newPool = Clones.clone(merchantPoolImplementation);

        MerchantPool(newPool).initialize(merchant, platformAddress, stakingContract, token, defaultBaseFee);

        merchantToPool[merchant] = newPool;
        emit MerchantPoolCreated(merchant, newPool);
        return newPool;
    }

    /**
     * @dev Update default base fee (owner only)
     * @param newFee New default base fee
     */
    function updateDefaultFee(uint96 newFee) external onlyOwner {
        require(newFee <= 10000, "Fee cannot exceed 100%");
        defaultBaseFee = newFee;
        emit DefaultFeeUpdated(newFee);
    }

    /**
     * @dev Check if an address has a merchant pool
     * @param merchantAddress Address to check
     * @return Whether the merchant has a pool
     */
    function hasMerchantPool(address merchantAddress) external view returns (bool) {
        return merchantToPool[merchantAddress] != address(0);
    }

    /**
     * @dev Get merchant pool address
     * @param merchantAddress Merchant address
     * @return Pool address
     */
    function getMerchantPool(address merchantAddress) external view returns (address) {
        return merchantToPool[merchantAddress];
    }

    /**
     * @dev Get number of merchant pools created
     * @param merchantAddresses Array of merchant addresses to check
     * @return Array of corresponding pool addresses (zero address if none)
     */
    function getMerchantPools(address[] calldata merchantAddresses) external view returns (address[] memory) {
        address[] memory pools = new address[](merchantAddresses.length);

        for (uint256 i = 0; i < merchantAddresses.length; i++) {
            pools[i] = merchantToPool[merchantAddresses[i]];
        }

        return pools;
    }
}
