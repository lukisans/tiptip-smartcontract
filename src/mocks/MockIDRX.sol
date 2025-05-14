// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title MockIDRX
 * @dev Mock ERC20 token for testing purposes
 * Gas optimized: Inherits from OpenZeppelin's ERC20 for security and efficient implementation
 */
contract MockIDRX is ERC20, Ownable {
    // Constants to avoid repeated storage reads
    uint8 private constant _DECIMALS = 18;
    uint256 private constant _INITIAL_SUPPLY = 1_000_000_000 * 10 ** 18; // 1 billion tokens

    /**
     * @dev Constructor sets up the token with name, symbol and mints initial supply to deployer
     */
    constructor() ERC20("Mock IDRX", "IDRX") Ownable(msg.sender) {
        _mint(msg.sender, _INITIAL_SUPPLY);
    }

    /**
     * @dev Public mint function for testing scenarios
     * @param to Address to mint tokens to
     * @param amount Amount of tokens to mint
     */
    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }
}
