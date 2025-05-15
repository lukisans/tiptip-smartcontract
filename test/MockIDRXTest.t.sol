// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "../src/mocks/MockIDRX.sol";

contract MockIDRXTest is Test {
    MockIDRX public token;
    address public deployer;
    address public user1;
    address public user2;

    // Setup test environment
    function setUp() public {
        deployer = address(this);
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");

        // Deploy token
        token = new MockIDRX();

        // Allocate some tokens to test users
        token.transfer(user1, 1_000_000 * 1e18);
        token.transfer(user2, 500_000 * 1e18);
    }

    // Initial supply should be 1 billion tokens
    function testInitialSupply() public view {
        assertEq(token.totalSupply(), 1_000_000_000 * 1e18);
    }

    // Test basic transfer functionality
    function testTransfer() public {
        uint256 initialBalance = token.balanceOf(user1);

        vm.prank(user1);
        token.transfer(user2, 100_000 * 1e18);

        assertEq(token.balanceOf(user1), initialBalance - 100_000 * 1e18);
        assertEq(token.balanceOf(user2), 600_000 * 1e18);
    }

    // Test mint function (only owner)
    function testMintAsOwner() public {
        uint256 initialSupply = token.totalSupply();
        uint256 mintAmount = 5_000_000 * 1e18;

        token.mint(user1, mintAmount);

        assertEq(token.totalSupply(), initialSupply + mintAmount);
        assertEq(token.balanceOf(user1), 1_000_000 * 1e18 + mintAmount);
    }

    // Test that non-owners cannot mint
    function testMintAsNonOwner() public {
        vm.prank(user1);
        vm.expectRevert();
        token.mint(user1, 1000 * 1e18);
    }

    // Test approval and transferFrom
    function testApproveAndTransferFrom() public {
        vm.prank(user1);
        token.approve(user2, 50_000 * 1e18);

        assertEq(token.allowance(user1, user2), 50_000 * 1e18);

        vm.prank(user2);
        token.transferFrom(user1, user2, 50_000 * 1e18);

        assertEq(token.balanceOf(user1), 950_000 * 1e18);
        assertEq(token.balanceOf(user2), 550_000 * 1e18);
    }
}
