// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "forge-std/Test.sol";

import "../src/contracts/testing/HIGHERTokenTesting.sol";

contract HIGHERTokenTest is Test {
    HIGHERTokenTesting token;

    address alice = makeAddr("alice");
    address bob = makeAddr("bob");

    function setUp() public {
        vm.createSelectFork("https://rpc.ankr.com/blast", 382338);
        token = new HIGHERTokenTesting("Higher Finance Token", "HIGHER");
        token.setMinter(address(this));
    }

    function test_balanceOf() public {
        assertEq(token.balanceOf(alice), 0);
    }

    function test_Mint() public {
        token.mint(alice, 100e18);
        assertEq(token.balanceOf(alice), 100e18);
        assertEq(token.totalSupply(), 100e18);
        vm.expectRevert("can only mint once");
        token.mint(alice, 100e18);
    }

    function test_Transfer() public {
        token.mint(address(this), 100e18);
        token.transfer(bob, 50e18);
        assertEq(token.balanceOf(address(this)), 50e18);
        assertEq(token.balanceOf(bob), 50e18);

        assertEq(token.tokenShares(address(this)), 0.5e27);
        assertEq(token.tokenShares(bob), 0.5e27);

        vm.prank(bob);
        token.transfer(alice, 10e18);
        assertEq(token.tokenShares(alice), 0.1e27);
        assertEq(token.tokenShares(bob), 0.4e27);
    }

    function test_TransferFrom() public {
        token.mint(address(this), 100e18);
        vm.prank(bob);
        token.approve(address(this), 50e18);
        token.transfer(bob, 50e18);

        token.transferFrom(bob, alice, 10e18);
        assertEq(token.tokenShares(alice), 0.1e27);
        assertEq(token.tokenShares(bob), 0.4e27);
        assertEq(token.balanceOf(alice), 10e18);
        assertEq(token.balanceOf(bob), 40e18);
    }

    function test_Rebase() public {
        token.mint(address(this), 100e18);
        token.transfer(bob, 40e18);
        token.transfer(alice, 10e18);
        assertEq(token.totalSupply(), 100e18);
        token.rebase(50e18);
        assertEq(token.totalSupply(), 50e18);
        assertEq(token.balanceOf(address(this)), 25e18);
        assertEq(token.balanceOf(bob), 20e18);
        assertEq(token.balanceOf(alice), 5e18);
        assertEq(token.tokenShares(address(this)), 0.5e27);
        assertEq(token.tokenShares(bob), 0.4e27);
        assertEq(token.tokenShares(alice), 0.1e27);

        token.rebase(200e18);
        assertEq(token.totalSupply(), 200e18);
        assertEq(token.balanceOf(address(this)), 100e18);
        assertEq(token.balanceOf(bob), 80e18);
        assertEq(token.balanceOf(alice), 20e18);
        assertEq(token.tokenShares(address(this)), 0.5e27);
        assertEq(token.tokenShares(bob), 0.4e27);
        assertEq(token.tokenShares(alice), 0.1e27);
    }

    function test_getCurrentTwapPrice() public {}
}
