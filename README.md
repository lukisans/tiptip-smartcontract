# IDRX Merchant System Deployment Guide

This guide explains how to deploy the IDRX Merchant System contracts using Foundry.

## Prerequisites

1. Install [Foundry](https://book.getfoundry.sh/getting-started/installation)
2. Set up environment variables (create a `.env` file)

## Environment Setup

Create a `.env` file with the following variables:

```bash
# Required for all environments
PRIVATE_KEY=your_private_key_here

# Testnet configuration
TESTNET_IDRX_ADDRESS=0x...
TESTNET_STAKING_ADDRESS=0x...
TESTNET_PLATFORM_OWNER=0x...

# Mainnet configuration
MAINNET_IDRX_ADDRESS=0x...
MAINNET_STAKING_ADDRESS=0x...
MAINNET_PLATFORM_OWNER=0x...
```

Load the environment variables:

```bash
source .env
```

## Deployment Options

### Local Development

Deploy the complete system (MockIDRX, MockStakingIDRX, and FactoryMerchantPool):

```bash
forge script script/DeployIDRXMerchantSystem.s.sol:DeployIDRXMerchantSystem --sig "run(uint8)" 0 -vvv
```

### Testnet Deployment

Deploy only the FactoryMerchantPool using existing token and staking contracts:

```bash
forge script script/DeployIDRXMerchantSystem.s.sol:DeployIDRXMerchantSystem --sig "run(uint8)" 1 --rpc-url $TESTNET_RPC_URL --broadcast -vvv
```

### Mainnet Deployment

Deploy only the FactoryMerchantPool using existing token and staking contracts:

```bash
forge script script/DeployIDRXMerchantSystem.s.sol:DeployIDRXMerchantSystem --sig "run(uint8)" 2 --rpc-url $MAINNET_RPC_URL --broadcast -vvv
```

## Contract Verification

After deployment, verify the contracts on Etherscan:

```bash
# Verify FactoryMerchantPool
forge verify-contract --chain-id [CHAIN_ID] --compiler-version [VERSION] [CONTRACT_ADDRESS] src/FactoryMerchantPool.sol:FactoryMerchantPool --constructor-args $(cast abi-encode "constructor(address,address,address)" [IDRX_ADDRESS] [STAKING_ADDRESS] [PLATFORM_OWNER_ADDRESS]) --etherscan-api-key [YOUR_ETHERSCAN_API_KEY]
```

## Testing the Deployment

After deployment, you can interact with the contracts:

1. Create a merchant pool:

   ```bash
   cast send [FACTORY_ADDRESS] "createMerchantPool(address)" [MERCHANT_ADDRESS] --private-key $PRIVATE_KEY
   ```

2. Check if a merchant has a pool:

   ```bash
   cast call [FACTORY_ADDRESS] "hasMerchantPool(address)" [MERCHANT_ADDRESS]
   ```

3. Get a merchant's pool address:
   ```bash
   cast call [FACTORY_ADDRESS] "getMerchantPool(address)" [MERCHANT_ADDRESS]
   ```

## Contract Architecture

- `MockIDRX`: ERC20 token for testing
- `MockStakingIDRX`: Mock staking contract for IDRX tokens
- `FactoryMerchantPool`: Factory to create merchant-specific pools
- `MerchantPool`: Manages merchant-specific tipping and staking mechanics

## Security Considerations

1. Always verify contract addresses before deployment
2. Use a dedicated wallet for deployment
3. Test thoroughly on testnet before mainnet deployment
4. Consider a security audit before mainnet deployment
