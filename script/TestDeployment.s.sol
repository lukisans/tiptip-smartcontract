// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script} from "forge-std/Script.sol";
import {FactoryMerchantPool} from "../src/core/FactoryMerchantPool.sol";
import {MerchantPool} from "../src/core/MerchantPool.sol";
import {MockIDRX} from "../src/mocks/MockIDRX.sol";
import {MockStakingIDRX} from "../src/mocks/MockStakingIDRX.sol";
import {console2} from "forge-std/console2.sol";

/**
 * @title TestDeployment
 * @notice Integration test script for the IDRX Merchant System
 * @dev Tests basic contract interactions after deployment
 */
contract TestDeployment is Script {
    MockIDRX public idrxToken;
    MockStakingIDRX public stakingContract;
    FactoryMerchantPool public factory;
    address merchantAddress;
    address platformOwnerAddress;

    function setUp() public {
        // Setup addresses for testing
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        platformOwnerAddress = vm.addr(deployerPrivateKey);
        merchantAddress = makeAddr("merchant");

        // Start transaction broadcasting
        vm.startBroadcast(deployerPrivateKey);

        // Deploy contracts
        idrxToken = new MockIDRX();
        stakingContract = new MockStakingIDRX(address(idrxToken));
        factory = new FactoryMerchantPool(address(idrxToken), address(stakingContract), platformOwnerAddress);

        // Mint some tokens to merchantAddress for testing
        idrxToken.mint(merchantAddress, 100_000_000 * 10 ** 18);

        vm.stopBroadcast();
    }

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        // Test factory configuration
        console2.log("IDRX Token address:", address(idrxToken));
        console2.log("Staking contract address:", address(stakingContract));
        console2.log("Factory address:", address(factory));
        console2.log("Platform owner address:", platformOwnerAddress);
        console2.log("Merchant address:", merchantAddress);

        // Create a merchant pool
        address poolAddress = factory.createMerchantPool(merchantAddress);
        console2.log("Merchant pool created at:", poolAddress);

        // Verify the pool was created correctly
        bool hasMerchant = factory.hasMerchantPool(merchantAddress);
        console2.log("Merchant has pool:", hasMerchant);

        address retrievedPool = factory.getMerchantPool(merchantAddress);
        console2.log("Retrieved pool address:", retrievedPool);
        require(retrievedPool == poolAddress, "Pool address mismatch");

        // Test default fee
        uint96 defaultFee = factory.defaultBaseFee();
        console2.log("Default fee:", defaultFee);

        // Update default fee (as the owner)
        factory.updateDefaultFee(500); // Update to 5%
        console2.log("Updated default fee:", factory.defaultBaseFee());

        vm.stopBroadcast();

        console2.log("Integration test completed successfully!");
    }
}
