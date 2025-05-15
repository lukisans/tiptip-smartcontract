// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script} from "forge-std/Script.sol";
import {MockToken} from "../src/mocks/MockToken.sol";
import {MockStakingIDRX} from "../src/mocks/MockStakingIDRX.sol";
import {FactoryMerchantPool} from "../src/core/FactoryMerchantPool.sol";
import {console2} from "forge-std/console2.sol";

/**
 * @title DeployIDRXMerchantSystem
 * @notice Deployment script for the IDRX Merchant System
 * @dev Handles deployment for local, testnet, and mainnet environments
 */
contract DeployIDRXMerchantSystem is Script {
    // Configuration variables
    address public idrxTokenAddress;
    address public stakingContractAddress;
    address public platformOwnerAddress;

    uint256 public constant STAKING_PLATFORM_REWARD = 100_000_000 * 10 ** 18; // 10M tokens

    // Deployment choice
    enum DeploymentEnvironment {
        LOCAL,
        TESTNET,
        MAINNET
    }

    /**
     * @dev Main deployment function
     * @param environment The deployment environment (0=LOCAL, 1=TESTNET, 2=MAINNET)
     */
    function run(uint8 environment) external {
        // Convert to enum for better readability
        DeploymentEnvironment env = DeploymentEnvironment(environment);

        // Load environment-specific configuration
        _loadConfig(env);

        // Get deployer private key and start broadcasting transactions
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        // Deploy contracts based on the environment
        if (env == DeploymentEnvironment.LOCAL) {
            _deployLocalEnvironment();
        } else {
            _deployFactoryOnly();
        }

        vm.stopBroadcast();
    }

    /**
     * @dev Load configuration based on the deployment environment
     * @param environment The deployment environment
     */
    function _loadConfig(DeploymentEnvironment environment) internal {
        if (environment == DeploymentEnvironment.LOCAL) {
            // For local development, we'll use default addresses that will be overridden
            // by actual deployed contract addresses during deployment
            idrxTokenAddress = address(0);
            stakingContractAddress = address(0);
            platformOwnerAddress = vm.addr(vm.envUint("PRIVATE_KEY")); // Use deployer as platform owner
        } else if (environment == DeploymentEnvironment.TESTNET) {
            // Read testnet configuration from environment variables
            idrxTokenAddress = vm.envAddress("TESTNET_IDRX_ADDRESS");
            stakingContractAddress = vm.envAddress("TESTNET_STAKING_ADDRESS");
            platformOwnerAddress = vm.envAddress("TESTNET_PLATFORM_OWNER");
        } else if (environment == DeploymentEnvironment.MAINNET) {
            // Read mainnet configuration from environment variables
            idrxTokenAddress = vm.envAddress("MAINNET_IDRX_ADDRESS");
            stakingContractAddress = vm.envAddress("MAINNET_STAKING_ADDRESS");
            platformOwnerAddress = vm.envAddress("MAINNET_PLATFORM_OWNER");

            // Additional safety check for mainnet deployments
            require(idrxTokenAddress != address(0), "Invalid IDRX token address for mainnet");
            require(stakingContractAddress != address(0), "Invalid staking contract address for mainnet");
            require(platformOwnerAddress != address(0), "Invalid platform owner address for mainnet");
        }
    }

    /**
     * @dev Deploy all contracts for local development
     */
    function _deployLocalEnvironment() internal {
        console2.log("Deploying complete system for local development...");

        // Deploy mock IDRX token
        MockToken idrxToken = new MockToken("Mock IDRX Token", "mIDRX", 18);
        console2.log("MockToken deployed at:", address(idrxToken));
        idrxTokenAddress = address(idrxToken);

        // Deploy mock staking contract
        MockStakingIDRX stakingContract = new MockStakingIDRX(idrxTokenAddress);
        console2.log("MockStakingIDRX deployed at:", address(stakingContract));
        stakingContractAddress = address(stakingContract);

        idrxToken.mint(stakingContractAddress, STAKING_PLATFORM_REWARD);

        // Deploy factory contract
        FactoryMerchantPool factory =
            new FactoryMerchantPool(idrxTokenAddress, stakingContractAddress, platformOwnerAddress);
        console2.log("FactoryMerchantPool deployed at:", address(factory));
    }

    /**
     * @dev Deploy only the factory contract (for testnet/mainnet)
     */
    function _deployFactoryOnly() internal {
        console2.log("Deploying FactoryMerchantPool...");
        console2.log("IDRX Token Address:", idrxTokenAddress);
        console2.log("Staking Contract Address:", stakingContractAddress);
        console2.log("Platform Owner Address:", platformOwnerAddress);

        // Create factory using the already deployed token and staking contracts
        FactoryMerchantPool factory =
            new FactoryMerchantPool(idrxTokenAddress, stakingContractAddress, platformOwnerAddress);

        console2.log("FactoryMerchantPool deployed at:", address(factory));
    }
}
